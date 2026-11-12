# misc/ - tests and helpers (need Simics started by core/restart.sh)

Each test explained in detail: ../doc/02-test-guide.txt

## Layout

   run-tests.sh          - runs suites / steps, prints "== failed: ..."
   lib.sh                - ALL shared code (ports, UEFI Shell session, parsing, checks)
   helpers/              - manual tools on the Simics host (execute-simics-cmd.sh)
   dev/                  - dev machine only: ut-nic-core.sh (build + run all nic-core unit tests, L0.2)
   tests/net/<name>.sh   - network tests (traffic, boot)
   tests/func/<name>.sh  - driver functional tests (load, protocols, HII, ...)
   tools/<tool>/         - UEFI apps used by tests; build.sh puts the .efi in core/usb-drive/

## Run

   run-tests.sh                 - all = net + func
   run-tests.sh func            - one suite (net, func)
   run-tests.sh restart ping    - only the given steps, in this order
   tests/*/<name>.sh [args]     - one test; prints PASS/FAIL lines, exit 1 on any FAIL
   Logs: /tmp/<name>.log (UEFI side of the last session), /tmp/<name>-* (host side).

## Tests

   net:  ping, port-isolation, mcast, foreign-mac, large, parallel, dhcp,
         download, ipv6, pxe, http-boot
   func: load, protocols, identity, diag, hii, bind, driver-log, unload, leak

   large:     pings of 1472/4000/8000 bytes (IP fragments), both ways.
   parallel:  host pings all ports at the same time.
   dhcp:      dnsmasq gives UEFI an IP, host pings it, back to static.
   download:  1 MB over TFTP (tftp.efi) and HTTP (http.efi), files must match.
   ipv6:      ifconfig6 + ping6 both ways (via shell.efi).
   pxe:       dnsmasq (DHCP + TFTP); UEFI runs pxeboot.efi <MAC> per port,
              the NBP is pxeboot.efi again ("PXEBOOT: NBP running").
   http-boot: same over HTTP (vendor class HTTPClient, python3 http.server).

   load:      load Success, in "drivers", one child per port with its MAC.
   protocols: dh -v of the image (binding, names, diag, health, unload) and
              of each child (NII31, HII, AIP, device path; FMP on one child).
   identity:  version hex == version in the name, controller name,
              name under drivers -l <lang>.
   diag:      drvdiag -s / -e / -m Success, then ping.
   hii:       hii.efi show of the main form per port: MAC, driver name,
              PCI address / device ID (vs dh -v PCIIO), link; fr-FR title;
              set Blink LEDs; then ping (HII access must not stop the queues).
   bind:      disconnect / connect -r the controller, then ping.
   unload:    load, ping, unload; repeat.
   leak:      load/unload cycles; memmap free pages must not drop.
              leak.sh [full|nc|ncc|bind|bindh|stage] [cycles] [max pages]

   Extra tests (not in run-tests.sh yet):
   net/sizes.sh [ports]     ping size sweep 0..30000 both ways.
   net/flood.sh [port] [n]  host ping -f, then normal pings both ways.
   func/load2.sh            2nd load of the image: 0 controllers, unload -n,
                            1st image still works.
   func/child.sh [port]     disconnect one child: 7 left, others ping;
                            connect -r brings it back.
   func/stress.sh [bind|load|reconnect] [cycles]
                            many cycles; 8 children each time, openinfo
                            count stays the same, then ping.
   func/nictest.sh          protocol members via nictest.efi (cn2, health,
                            aip, fmp, nii/!PXE, snp, efi version, cdb).
   func/unload-busy.sh      unload while the host pings, reload, all ports ping.
   func/memfail.sh [pages]  nictest eatmem, connect, free; everything works after.
   func/warm-reset.sh [n]   reset -w n times: load + ping each boot.
   net/frames.sh            raw frames (tools/frames/frames.py): short, bad
                            checksum, oversize, burst, broadcast storm.
   net/soak.sh [seconds]    host pings all ports 1/s, UEFI pings port 0.

## Tools (prebuilt in core/usb-drive/, rebuild on the dev machine)

   tools/netcmds/build.sh <edk2 dir>      tftp.efi, http.efi, shell.efi (ping6, ifconfig6)
   tools/pxeboot/build.sh <edk2 dir>      pxeboot.efi (e.g. nic-core/edk2)
   tools/hii/build.sh <hii-test-tool dir> hii.efi (github.com/intel-sandbox/hii-test-tool)
   tools/nictest/build.sh <edk2 dir>      nictest.efi (protocol calls, NICTEST lines)

   ping6 example: shell.efi -nostartup -exit ping6 2001:db8:0::200
   hii example:   hii.efi list; hii.efi show <formset> 0x200
   nictest:       nictest.efi cn2|health|aip|fmp|nii|snp|snpf|ver|cdb [driver name part]
                  nictest.efi eatmem alloc [pages left]|free   nictest.efi ebs
   frames.py:     tools/frames/frames.py <tap> echo|bcast|raw ... (host, needs root)

## Rules

   1. Line 2 of a test: "# Usage: <name>.sh [args]   What. Needs: <state>."
      State: fresh boot | driver loaded | ping.sh done (loaded + ifconfig)
      | driver not loaded | any.
   2. Source lib.sh: . "$(dirname "$0")/../../lib.sh". No local copies of
      helpers; if two tests need the same code, it goes to lib.sh.
   3. UEFI side: uefi_begin, uefi_cmd / uefi_* ..., uefi_end, OUT=$(uefi_log).
      Mark parts with uefi_part <name>, cut them with log_part "$OUT" <name>.
   4. Results only via check / check_eq / check_le, end with finish.
   5. A test stops what it starts (dnsmasq, http.server, tcpdump) and
      restores what it changes (e.g. static IP after dhcp).
   6. Host files only in /tmp/<name>*.
   7. Ports: port P = UEFI eth<P+1> 192.168.P.101, MAC 0A:0P:00:08:03:18
      <-> host cnic_tap_0_P 192.168.P.200. Use tap/eth/uefi_ip/host_ip/mac.
   8. Add a test to a suite in run-tests.sh only after it passes alone.
   9. Every expect wait has a 300 s timeout: a wrong wait regex costs 300 s.

## Helpers

   helpers/execute-simics-cmd.sh  - run Simics CLI commands on the running Simics
