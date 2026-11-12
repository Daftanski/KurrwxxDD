#!/bin/bash
# Usage: run-repeat.sh <suite> [times]   Runs run-tests.sh <suite> several times (L7.3, default 3) and counts the failed steps per run. Needs: Simics host (run in the background: a run of "all" takes about 1 h).
DEV=/root/SimicsWorkspace/development/uefi-dev
SUITE=${1:?usage: run-repeat.sh <suite> [times]}
TIMES=${2:-3}
BAD=0

for I in $(seq 1 $TIMES); do
    $DEV/misc/run-tests.sh $SUITE > /tmp/repeat-$SUITE-$I.log 2>&1 || BAD=$((BAD + 1))
    echo "run $I: $(grep -a '^== failed' /tmp/repeat-$SUITE-$I.log)"
done
echo "runs with failures: $BAD of $TIMES"
[ $BAD -eq 0 ]
