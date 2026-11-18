# misc/ - kernel-dev tests (run on the Simics host, no LAVA)

## Catalog (no need to read the tests)

   bash run-tests.sh list      (works on the dev machine too, no ssh)
   One line per test = line 2 of tests/<name>.sh:
     <name>.sh [args]   What. Needs: <state>. Changes: <what>. Time: <wall time>.
   Changes: none | port(s) (restored) | driver (ixd state of the guest).
   Last line: the suites.

## Run (from the dev machine)

   ssh root@<host ip> /root/SimicsWorkspace/development/kernel-dev/misc/run-tests.sh [step ...]

   step = test name, restart, or suite (all, net, full; see list).
   run-tests.sh                - all = restart boot ixd ping
   run-tests.sh boot ixd net   - no restart: tests the running guest
   tests/<name>.sh [args]      - one test with args; PASS/FAIL/INFO lines, exit 1 on any FAIL
   Output ends with "== failed: <list>" (none = all passed).
   A failed restart or boot stops the run.
   restart kills the running Simics: check nobody uses the host (who, guest sessions).

   Deploy after a change: ../../setup-kernel-dev.sh <host ip> copy
   (copy = files only; without it also core/setup.sh, the image; update-simics-kernel.sh does both).

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

## Findings (open)

   F1 2026-11-18 CI kernel 6.18.1 #27, PFP, port 0: large.sh (fragmented ping
      host->guest) -> "ixd 0001:fb:00.0 eth6: hw csum failure", skb 1480 B IP
      fragment, ip_summed=CHECKSUM_COMPLETE. idpf_rx_csum (idpf_txrx.c ~3302)
      trusts raw_csum when RAW_CSUM_INV=0. Model or driver: not known yet.
   F2 2026-11-18 same setup: once on a port 0 link down (mtu/linkflap/abort
      runs): "eth6: Failed to receive marker packets" (idpf_virtchnl.c ~373,
      TX SW marker not completed on queue disable). Not seen again in a
      later net run. Intermittent; maybe the slow Simics time vs the wait timeout.
   Both stay in dmesg until restart: boot.sh and ixd.sh (whole dmesg) FAIL until then.

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
   6. Add a test to a suite in run-tests.sh only after it passes alone.
