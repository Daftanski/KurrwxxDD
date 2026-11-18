#!/bin/bash
# Usage: run-tests.sh [step ...]   step = suite (net, func, long, all), "restart", a test name, or name:arg,arg (= tests/*/name.sh arg arg)
#        run-tests.sh list         catalog: one line per test + suites
# Default: all (net + func). long = soak 10 min + warm reset 10 x (about 40 min), not in all. Tests after a restart depend on the steps before them.
# Run only through LAVA (lava-test.sh uefi ...), never by hand.
HERE=$(dirname "$(readlink -f "$0")")
DEV=/root/SimicsWorkspace/development/uefi-dev
NET="restart ping port-isolation mcast foreign-mac large sizes flood frames parallel dhcp download vlan linkflap ipv6 driver-log restart pxe restart http-boot"
FUNC="restart load protocols identity nictest diag hii hiiall bind child load2 connect1 connect-rdp hold stress memfail fw-dead fw-balance driver-log restart unload unload-busy leak restart load ebs restart"
# Not in a suite (they FAIL until the findings D12-D15 are fixed): snpstate, snpdamage, txfill.
LONG="restart load soak restart warm-reset"

if [ "$1" = list ]; then
    for F in "$HERE"/tests/*/*.sh; do
        sed -n '2s/^# Usage: //p' "$F"
    done
    echo "steps: restart (~2 min, boot to UEFI shell, loads nothing) | name:arg,arg"
    echo "suites: net = $NET"
    echo "        func = $FUNC"
    echo "        long = $LONG | all = net func (~45 min)"
    exit 0
fi

STEPS=""
for S in ${*:-all}; do
    case $S in
        all)  STEPS+=" $NET $FUNC" ;;
        net)  STEPS+=" $NET" ;;
        func) STEPS+=" $FUNC" ;;
        long) STEPS+=" $LONG" ;;
        *)    STEPS+=" $S" ;;
    esac
done
FAILED=""

for S in $STEPS; do
    echo "== $S"
    if [ $S = restart ]; then
        $DEV/core/restart.sh > /dev/null || { FAILED+=" restart"; break; }
    else
        T=${S%%:*}
        ARGS=()
        [[ $S == *:* ]] && IFS=, read -ra ARGS <<< "${S#*:}"
        F=$(ls $HERE/tests/*/$T.sh 2> /dev/null | head -1)
        if [ -z "$F" ]; then
            echo "FAIL no test $T (run-tests.sh list)"
            FAILED+=" $S"
            continue
        fi
        $F "${ARGS[@]}" || FAILED+=" $S"
    fi
done

echo "== failed:${FAILED:- none}"
[ -z "$FAILED" ]
