#!/bin/bash
# Usage: run-tests.sh [step ...]   step = suite, restart, install, a test name, or name:arg,arg (= tests/name.sh arg arg)
#        run-tests.sh expand <step ...>   only print the resolved steps
#        run-tests.sh list         catalog: one line per test (args, what, Needs, Changes, Time) + suites
# Default: all. Run only through LAVA (lava-test.sh kernel ...), never by hand.
# restart = core/restart.sh (returns at once), boot waits for the guest.
# install = stop Simics, put image/kernel_output.tar.gz into the image, restart.
# A failed restart or install, boot without a guest (exit 2) or the watchdog
# (kernel crash / hung guest) stops the run.
HERE=$(dirname "$(readlink -f "$0")")
DEV=/root/SimicsWorkspace/development/kernel-dev
ALL="restart boot ixd ping"
NET="large mtu linkflap stats"
# bridge after reload: reload after bridge hangs (F3 reproducer).
DRIVER="sf reload bridge"
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

EXPAND=""
if [ "$1" = expand ]; then
    EXPAND=1
    shift
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
# expand: print the steps the run would do (suites resolved), one per line.
if [ -n "$EXPAND" ]; then
    printf '%s\n' $STEPS
    exit 0
fi
# Watchdog (watchdog.sh) next to every test after boot: a kernel crash or hung
# guest fails the step at once and stops the run. WATCHDOG=0: off.
WD_FLAG=/tmp/kdev-guest-dead
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
            if [ $T = boot ] || [ "$WATCHDOG" = 0 ]; then
                $HERE/tests/$T.sh "${ARGS[@]}" || RC=$?
            else
                # Own process group (set -m) so the watchdog can kill the whole test.
                rm -f $WD_FLAG
                set -m
                $HERE/tests/$T.sh "${ARGS[@]}" &
                TP=$!
                set +m
                WD_FLAG=$WD_FLAG $HERE/watchdog.sh $TP &
                WP=$!
                wait $TP || RC=$?
                kill $WP 2> /dev/null
                wait $WP 2> /dev/null
            fi
            if [ $RC != 0 ]; then
                FAILED+=" $S"
                [ $T = boot ] && [ $RC = 2 ] && break
                # Watchdog: guest crashed / hung, later steps cannot run.
                [ -f $WD_FLAG ] && break
            fi ;;
    esac
done

echo "== failed:${FAILED:- none}"
[ -z "$FAILED" ]
