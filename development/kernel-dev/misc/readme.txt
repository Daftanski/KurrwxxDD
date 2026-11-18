# misc/ - kernel-dev tests (run on the Simics host, no LAVA)

## Run (from the dev machine)

   ssh root@<host ip> /root/SimicsWorkspace/development/kernel-dev/misc/run-tests.sh [step ...]

   run-tests.sh                - all = restart boot ixd ping
   run-tests.sh boot ixd       - only these steps (no restart: tests the running guest)
   tests/<name>.sh [args]      - one test; prints PASS/FAIL lines, exit 1 on any FAIL
   Output ends with "== failed: <list>" (none = all passed).
   A failed restart or boot stops the run.
   restart kills the running Simics: check nobody uses the host (who, guest sessions).

   Deploy the tests after a change: ../../setup-kernel-dev.sh <host ip>
   (update-simics-kernel.sh does it too).

## Tests

   boot:  waits for guest ssh (default 20 min), uname -r / -v == image/kernel-version
          (written by core/install.sh; CI kernel: INFO only), dmesg has no
          BUG / Oops / WARNING / Call Trace.
   ixd:   ixd loaded; PFs bound to ixd: PFD 1, PFP 8; 8 devlink physical ports;
          port P has a netdev with its MAC and devlink says "physical port P";
          no ixd error / fail / timeout in dmesg.
   ping:  per port: guest netdev up + 192.168.P.101/24, host cnic_tap_0_P
          192.168.P.200/24, carrier 1, ping both ways (>= 3 of 5), then removes the
          addresses. A port inside a bridge (e.g. after set-multi.sh) is a FAIL,
          not touched.

## How the guest is reached

   Guest eth0 is bridged to the lab LAN (sim_br0), IP by DHCP, no lease log.
   lib.sh finds it by the MAC ($i210_mac of the launch script): pings ff02::1
   on sim_br0, takes IPv4 / IPv6 link-local neighbours with that MAC, uses the
   first that answers ssh. Host key changes every boot: no known_hosts.

## Ports

   Port P: host cnic_tap_0_P <-> guest netdev with MAC
     PFD: 0a:0P:00:08:03:18     PFP: 0a:00:00:0P:03:1P
   Guest netdev names do not follow the ports (PFP: eth1 = port 2): use guest_dev P.
   PFD/PFP: logs/pfp, written by core/launch-simics.sh
     (PFP=TRUE|FALSE env, else the host's own $pfp line).

## Rules

   1. Line 2 of a test: "# Usage: <name>.sh [args]   What. Needs: <state>."
   2. Source lib.sh; shared code goes to lib.sh, no local copies.
   3. Guest commands: guest_need once, then g "<cmd>".
   4. Results only via check / check_eq, end with finish.
   5. A test restores what it changes (addresses, link state).
   6. Add a test to "all" in run-tests.sh only after it passes alone.
