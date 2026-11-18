---
name: lava-test
description: Use when a driver/kernel/test change must be verified on Simics (UEFI driver E4999X10.EFI or Linux kernel / ixd), or the user asks to run Simics tests. Runs tests only through the LAVA queue with one command and a 3-5 line answer. KurrwxxDD workspace.
---

# lava-test - Simics tests through LAVA

Rule: Simics tests run ONLY through LAVA. Never ssh to a host to run
run-tests.sh, restart.sh or install.sh. No need to ask before a job that
restarts Simics (the queue protects other jobs).

`L=~/lava/svl/lava-test.sh`, `D=~/tools/KurrwxxDD/development`.

## 1. Pick tests (do NOT read test sources)

    $L list kernel        # or: $L list uefi
One line per test: `name.sh [args]  What. Needs: <state>. Changes: .. Time: ..`,
then steps and suites. Choose the fewest tests that cover the change, and put
the steps their "Needs:" require first (fresh state = `restart`).
Full suite (`all`, `full`) only when the user asks.

## 2. Deploy what changed (host = config.txt host-ip-<n> whose role tag you use)

- Test scripts changed:  `$D/setup-kernel-dev.sh <ip> copy`  /  `$D/setup-uefi-dev.sh <ip>`
- Kernel changed (run in the kernel tree): `$D/update-simics-kernel.sh <ip>`
  (build + copy only), then put `install boot` first in the steps.
- UEFI driver changed: nic-core `EXEC_CNIC_BUILD.sh <ip>`, then `restart` first.

## 3. Run

    $L <kernel|uefi> <tag> <step ...>
- tag = device tag = first word of the host role in config.txt, lowercase (pfd, pfp).
- step = test name, `name:arg,arg` (= name.sh arg arg), `restart`, kernel `install`, or suite.
- Examples: `$L kernel pfp ixd mtu:0,9000`   `$L kernel pfp install boot ixd ping`
  `$L uefi pfd restart load ping`
- Blocks until done. Set the tool timeout to the queue wait plus the sum of the
  tests' Time plus 10 min. If the call times out anyway: `$L wait <job id>`
  (the id is printed on the first line).

## 4. Read the answer

    job 7 FAIL (Finished/Complete, 2m41s) kernel pfp: ixd mtu:0,9000
      29 checks passed, 1 failed. == failed: ixd
      ixd: FAIL dmesg ixd errors (got '2', want '0')
      log: ~/lava/svl/logs/7.txt
- PASS (exit 0): done. Report one line.
- FAIL (exit 1): read only that test's part of the log (`grep -n -A40 '^== <step>'`),
  then that test's source and the "Known"/"Findings" part of
  `$D/<setup>-dev/misc/readme.txt`.
- ERROR (exit 2): the job broke (LAVA, ssh, host). Lines shown are the cause;
  details: `$D/doc/lava/02-usage.txt`.

## New test

Rules in `$D/<setup>-dev/misc/readme.txt`. Line 2 of the test is its catalog
entry (`# Usage: ...`); keep it complete, measure Time. Deploy (step 2), then
run it alone before adding it to a suite.
