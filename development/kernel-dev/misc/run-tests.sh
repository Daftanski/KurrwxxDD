#!/bin/bash
# Usage: run-tests.sh [step ...]   step = suite (all), "restart", or a test name from tests/
# Default: all. restart = core/restart.sh (returns at once), boot waits for the guest.
# A failed restart or boot stops the run: later steps need the guest.
DEV=/root/SimicsWorkspace/development/kernel-dev
ALL="restart boot ixd ping"
STEPS=""
for S in ${*:-all}; do
    case $S in
        all) STEPS+=" $ALL" ;;
        *)   STEPS+=" $S" ;;
    esac
done
FAILED=""

for S in $STEPS; do
    echo "== $S"
    if [ $S = restart ]; then
        $DEV/core/restart.sh > /dev/null || { FAILED+=" restart"; break; }
    else
        $DEV/misc/tests/$S.sh || { FAILED+=" $S"; [ $S = boot ] && break; }
    fi
done

echo "== failed:${FAILED:- none}"
[ -z "$FAILED" ]
