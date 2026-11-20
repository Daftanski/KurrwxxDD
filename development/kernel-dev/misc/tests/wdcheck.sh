#!/bin/bash
# Usage: wdcheck.sh [seconds]   Watchdog self-test: writes a fake "BUG:" line to the guest kernel log and waits (default 180 s); the watchdog must kill it and stop the run (this step then FAILs with "FAIL watchdog: kernel: ... kdev watchdog self-test"). Not in a suite. Needs: boot.sh done. Changes: guest kernel log (fake BUG line: run it last, boot.sh fails until restart). Time: ~30 s.
. "$(dirname "$0")/../lib.sh"
guest_need
g "echo 'BUG: kdev watchdog self-test (fake, from wdcheck.sh)' > /dev/kmsg"
echo "INFO fake BUG line written, waiting ${1:-180} s for the watchdog"
sleep ${1:-180}
echo "FAIL watchdog did not stop the test in ${1:-180} s"
exit 1
