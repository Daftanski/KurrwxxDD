#!/bin/bash
# Usage: run-tests.sh [step ...]   step = suite, restart, install, a test name, or name:arg,arg (= tests/name.sh arg arg)
#        run-tests.sh list         catalog: one line per test (args, what, Needs, Changes, Time) + suites
# Default: all. Run only through LAVA (lava-test.sh kernel ...), never by hand.
# restart = core/restart.sh (returns at once), boot waits for the guest.
# install = stop Simics, put image/kernel_output.tar.gz into the image, restart.
# A failed restart or install, or boot without a guest (exit 2), stops the run.
HERE=$(dirname "$(readlink -f "$0")")
DEV=/root/SimicsWorkspace/development/kernel-dev
ALL="restart boot ixd ping"
NET="large mtu linkflap stats"
DRIVER="sf reload"
# Ported from BATS. Not in a suite: allmulti (F4), pfreset (F5, kills port A until restart).
FEAT="vlan queues rss coalesce ntuple speed"

if [ "$1" = list ]; then
    for F in "$HERE"/tests/*.sh; do
        sed -n '2s/^# Usage: //p' "$F"
    done
    echo "steps: restart (~0, boot waits) | install (kernel from update-simics-kernel.sh + restart, ~3 min) | name:arg,arg"
    echo "suites: all = $ALL (~6 min) | net = $NET | feat = $FEAT | driver = $DRIVER | full = all net feat driver (~8 min) | not in a suite: allmulti (F4), pfreset (F5, run last)"
    exit 0
fi

STEPS=""
for S in ${*:-all}; do
    case $S in
        all)    STEPS+=" $ALL" ;;
        net)    STEPS+=" $NET" ;;
        driver) STEPS+=" $DRIVER" ;;
        feat)   STEPS+=" $FEAT" ;;
        full)   STEPS+=" $ALL $NET $FEAT $DRIVER" ;;
        *)      STEPS+=" $S" ;;
    esac
done
FAILED=""

for S in $STEPS; do
    echo "== $S"
    case $S in
        restart)
            $DEV/core/restart.sh > /dev/null || { FAILED+=" $S"; break; } ;;
        install)
            # install.sh rewrites the .craff the running Simics uses: stop it first.
            killall -9 simics 2> /dev/null || true
            while pgrep -x simics > /dev/null; do sleep 1; done
            { $DEV/core/install.sh && $DEV/core/restart.sh; } > /dev/null || { FAILED+=" $S"; break; } ;;
        *)
            T=${S%%:*}
            ARGS=()
            [[ $S == *:* ]] && IFS=, read -ra ARGS <<< "${S#*:}"
            if [ ! -x $HERE/tests/$T.sh ]; then
                echo "FAIL no test $T (run-tests.sh list)"
                FAILED+=" $S"
                continue
            fi
            # boot exit 2 = no guest: later steps cannot run.
            RC=0
            $HERE/tests/$T.sh "${ARGS[@]}" || RC=$?
            if [ $RC != 0 ]; then
                FAILED+=" $S"
                [ $T = boot ] && [ $RC = 2 ] && break
            fi ;;
    esac
done

echo "== failed:${FAILED:- none}"
[ -z "$FAILED" ]
