# misc/ - kernel-dev tests (run on the Simics host, ONLY through LAVA)

## Catalog (no need to read the tests)

   ~/lava/svl/lava-test.sh list kernel     (= bash run-tests.sh list, local)
   One line per test = line 2 of tests/<name>.sh:
     <name>.sh [args]   What. Needs: <state>. Changes: <what>. Time: <wall time>.
   Changes: none | port(s) (restored) | driver (ixd state of the guest).
   Last lines: extra steps and suites.

## Run (from the workstation, through the LAVA queue)

   ~/lava/svl/lava-test.sh kernel <tag> <step ...>
   step = test name, name:arg,arg (= tests/name.sh arg arg), restart, install,
          or suite (all, net, driver, full).
     restart  - kill Simics, start it again (boot waits for the guest)
     install  - image/kernel_output.tar.gz (from update-simics-kernel.sh) into
                the image, then restart. Follow with boot.
   Examples: lava-test.sh kernel pfp install boot ixd ping
             lava-test.sh kernel pfp ixd mtu:0,9000
   Output (run-tests.sh): PASS/FAIL/INFO lines, "== <step>", ends with
   "== failed: <list>". A failed restart or install, or no guest in boot, stops the run.
   Never run run-tests.sh / tests / core scripts on the host by hand.

   Deploy after a test change: ../../setup-kernel-dev.sh <host ip> copy
   (copy = files only; without it also core/setup.sh, the image).

## Known (Simics)

   - Guest virtual time runs ~30x slower than wall time: a guest-side sleep or
     ping interval of 1 s costs ~30 s. Guest pings use -i 0.05 -W 1 (lib.sh).
   - VSI HW counters (ethtool rx/tx-unicast_pkts, ip -s link) stay 0; per-queue
     rx/tx_q-*_pkts work. stats.sh: VSI = INFO, HWSTATS=1 makes them checks.
   - First traffic after the first link up since boot can be slow: port_up waits
     up to 60 s for a reply and reports the time ("first traffic").
   - Some kernel messages print once per boot (DO_ONCE, e.g. "hw csum failure"):
     only the first test that triggers it reports it; boot.sh (whole dmesg)
     reports it in every later run until the next restart.
   - dmesg ring buffer is full already after boot (ixd is verbose): a test marks
     its start with a line in /dev/kmsg (dmesg_mark), never a line count.

## Findings (open)

   F1 2026-11-18 CI kernel 6.18.1 #27, PFP, port 0: large.sh (fragmented ping
      host->guest) -> "ixd 0001:fb:00.0 eth6: hw csum failure", skb 1480 B IP
      fragment, ip_summed=CHECKSUM_COMPLETE. idpf_rx_csum (idpf_txrx.c ~3302)
      trusts raw_csum when RAW_CSUM_INV=0. Model or driver: not known yet.
   F2 2026-11-18 same setup: once on a port 0 link down (mtu/linkflap/abort
      runs): "eth6: Failed to receive marker packets" (idpf_virtchnl.c ~373,
      TX SW marker not completed on queue disable). Not seen again in a
      later net run. Again in LAVA job 5 (ping.sh, port 7 eth8 link down,
      CI kernel). Intermittent; maybe the slow Simics time vs the wait timeout.
   F1 also on CI kernel 6.18.1-ixd-32236.22707 (LAVA job 4, large.sh, port 0
      eth7). Same run: guest->host 1472 B ping lost 2 of 3 replies (1500 B
      frames, guest RX): maybe the same csum fault (bad csum = drop). Not proven.
   Both stay in dmesg until restart: boot.sh and ixd.sh (whole dmesg) FAIL until then.

## Loopback (two ports back to back, like kernel selftests)

   loop_up A B (lib.sh): host bridge kdev-loop with cnic_tap_0_A + cnic_tap_0_B
   = a cable; on the guest port B goes into netns kdev-peer (else the kernel
   short-cuts traffic between two local addresses). A = 10.99.0.1 (init ns),
   B = 10.99.0.2 (kdev-peer). g "<cmd>" runs on side A, gb "<cmd>" on side B.
   loop_ping_ab / loop_ping_ba; tap_rx P proves packets left the guest.
   loop_down (also on any exit) restores guest netns + host taps.
   PFP: port P = PF P, so loopback.sh 0 1 = PF0 <-> PF1.

## How the guest is reached

   Guest eth0 is bridged to the lab LAN (sim_br0), IP by DHCP, no lease log.
   lib.sh finds it by the MAC ($i210_mac of the host's launch script): pings ff02::1
   on sim_br0, takes IPv4 / IPv6 link-local neighbours with that MAC, uses the
   first that answers ssh (one shared connection, /tmp/kdev-ssh-*).
   Host key changes every boot: no known_hosts.

## Ports

   Port P: host cnic_tap_0_P 192.168.P.200 <-> guest netdev with MAC (192.168.P.101)
     PFD: 0a:0P:00:08:03:18     PFP: 0a:00:00:0P:03:1P
   Guest netdev names do not follow the ports (PFP: eth1 = port 2): use guest_dev P.
   PFD/PFP: logs/pfp, written by core/launch-simics.sh
     (PFP=TRUE|FALSE env, else the host's own $pfp line).
   A port in a bridge (someone's setup, e.g. set-multi.sh) is a FAIL, never touched.

## Rules (new test)

   1. Line 2: "# Usage: <name>.sh [args]   What. Needs: <state>. Changes: <none|port(s)|driver>. Time: <t>."
      It is the catalog entry: an AI picks tests from it alone. Measure Time.
   2. Source lib.sh; shared code goes to lib.sh, no local copies.
   3. Guest: guest_need once, then g "<cmd>". Traffic: port_up P ... port_down P,
      guest_ping / host_ping. Errors: dmesg_mark at start, check_dmesg at end.
   4. Results only via check / check_eq / check_ge (PASS/FAIL lines), end with finish.
   5. A test restores what it changes. port_up state is restored on any exit
      (EXIT trap in lib.sh); a test with its own trap EXIT must call ports_restore.
      Changes: driver tests refuse to destroy someone's setup (SFs, bridges).
   6. Add a test to a suite in run-tests.sh only after it passes alone (LAVA job
      with only that test).
