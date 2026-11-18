#!/bin/bash
# Usage: run-tests.sh [step ...]   step = suite, "restart", or a test name from tests/
#        run-tests.sh list         catalog: one line per test (args, what, Needs, Changes, Time) + suites
# Default: all. restart = core/restart.sh (returns at once), boot waits for the guest.
# A failed restart or boot stops the run: later steps need the guest.
# Test arguments: run tests/<name>.sh [args] directly.
HERE=$(dirname "$(readlink -f "$0")")
DEV=/root/SimicsWorkspace/development/kernel-dev
ALL="restart boot ixd ping"
NET="large mtu linkflap stats"
# Not in a suite until they pass alone (readme rule 6): sf, reload.

if [ "$1" = list ]; then
    for F in "$HERE"/tests/*.sh; do
        sed -n '2s/^# Usage: //p' "$F"
    done
    echo "suites: all = $ALL | net = $NET | full = all net | not in a suite yet: sf reload"
    exit 0
fi

STEPS=""
for S in ${*:-all}; do
    case $S in
        all)    STEPS+=" $ALL" ;;
        net)    STEPS+=" $NET" ;;
        full)   STEPS+=" $ALL $NET" ;;
        *)      STEPS+=" $S" ;;
    esac
done
FAILED=""

for S in $STEPS; do
    echo "== $S"
    if [ $S = restart ]; then
        $DEV/core/restart.sh > /dev/null || { FAILED+=" restart"; break; }
    else
        $HERE/tests/$S.sh || { FAILED+=" $S"; [ $S = boot ] && break; }
    fi
done

echo "== failed:${FAILED:- none}"
[ -z "$FAILED" ]
