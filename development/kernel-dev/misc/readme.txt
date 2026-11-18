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
          or suite (all, net, feat, driver, full).
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
   - First traffic after the first link up since boot can be slow: loop_up waits
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
      Also in loopback (LAVA job 8, port 0 <-> port 1, no host stack): guest
      RX of IP fragments, not the host path.
   F3 2026-11-18 LAVA job 8 (full, CI kernel, PFP): reload.sh (rmmod +
      modprobe ixd after the net tests) -> no ports after 5 min. All 8 PF
      init tasks blocked in libie_ctlq_xn_send (ixd_map_pmat,
      ixd_mod_send_base_table, ixd_vc_dev_init), later "SEM: failed to clear
      base-table entries ... -110": CP mailbox does not answer. reload
      passed in jobs 4, 5 and 9 (after restart): intermittent. Guest stays
      broken: next job needs restart. reload.sh prints the blocked stacks.
   F4 2026-11-18 LAVA job 15 (CI kernel, PFP, loopback 0:1): multicast RX
      does not work. B's frames to 01:00:5e:01:01:01 reach host tap A (10/10),
      the same tcpdump -p on port A sees unicast (10/10), but 0 multicast
      frames, also with the group joined (ip maddr add) or ALLMULTI on.
      Driver does not program a multicast/allmulti rx rule (only "SEM rx rule
      match port forward to vsi" in dmesg)? allmulti.sh, not in a suite.
   F2 reproducible since job 14: allmulti.sh, port 1 (eth3) when loop_down
      moves it back from the netns (queues disabled): "Failed to receive
      marker packets".
   F1/F2 stay in dmesg until restart: boot.sh and ixd.sh (whole dmesg) FAIL until then.

## Traffic model: loopback (all traffic tests)

   Every traffic test runs between two guest ports wired back to back, like
   kernel selftests (local side + remote side in a netns). No host IP stack.
     host:  bridge kdev-loop with cnic_tap_0_A + cnic_tap_0_B = the cable
     guest: A = LOOP_DEV_A, 10.99.0.1, init ns   -> g  "<cmd>"
            B = LOOP_DEV_B, 10.99.0.2, netns kdev-peer -> gb "<cmd>"
            (B in a netns: else the kernel short-cuts traffic between two
            local addresses)
   Test args take pairs "A:B" (default 0:1; ping.sh: all 0:1 2:3 4:5 6:7).
   PFP: port P = PF P, so 0:1 = PF0 <-> PF1. PFD: all ports on one PF.
   lib.sh: loop_up A B, loop_down (also on any exit: guest netns, addresses,
   MTU, link state, host taps + their MTU/addresses, bridge), loop_ping_ab /
   loop_ping_ba, loop_mtu, loop_carrier a|b, loop_wait_carrier,
   loop_first_traffic, tap_rx P (packets that left the guest on port P).

## How the guest is reached

   Guest eth0 is bridged to the lab LAN (sim_br0), IP by DHCP, no lease log.
   lib.sh finds it by the MAC ($i210_mac of the host's launch script): pings ff02::1
   on sim_br0, takes IPv4 / IPv6 link-local neighbours with that MAC, uses the
   first that answers ssh (one shared connection, /tmp/kdev-ssh-*).
   Host key changes every boot: no known_hosts.

## Ports

   Port P: guest netdev with MAC (PFD 0a:0P:00:08:03:18, PFP 0a:00:00:0P:03:1P)
     <-> host cnic_tap_0_P. Guest netdev names do not follow the ports
     (PFP: eth1 = port 2): use guest_dev P.
   PFD/PFP: logs/pfp, written by core/launch-simics.sh
     (PFP=TRUE|FALSE env, else the host's own $pfp line).
   A port or tap in a bridge (someone's setup, e.g. set-multi.sh) is a FAIL,
   never touched.

## Rules (new test)

   1. Line 2: "# Usage: <name>.sh [args]   What. Needs: <state>. Changes: <none|port(s)|driver>. Time: <t>."
      It is the catalog entry: an AI picks tests from it alone. Measure Time.
   2. Source lib.sh; shared code goes to lib.sh, no local copies.
   3. Guest: guest_need once, then g "<cmd>". Traffic: always loopback:
      read -r A B <<< "$(pair_split $1)"; loop_up $A $B || finish; ...
      loop_down. Side B commands: gb "<cmd>" (no ' inside).
      Errors: dmesg_mark at start, check_dmesg at end.
   4. Results only via check / check_eq / check_ge (PASS/FAIL lines), end with finish.
   5. A test restores what it changes. loop_up state is restored on any exit;
      own cleanup: at_exit "<cmd>" (runs first). Never trap EXIT in a test.
   7. Ported from BATS (drivers.ethernet.linux.bats): line 3 = "# From: BATS
      hsd<id>[, hsd<id>]". Port the idea, add loopback traffic, not the code.
      Changes: driver tests refuse to destroy someone's setup (SFs, bridges).
   6. Add a test to a suite in run-tests.sh only after it passes alone (LAVA job
      with only that test).
