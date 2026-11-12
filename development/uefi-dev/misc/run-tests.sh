#!/bin/bash
# Usage: run-tests.sh [step ...]   step = suite (net, func, long, all), "restart", or a test name from tests/*/
# Default: all (net + func). long = soak 10 min + warm reset 10 x (about 40 min), not in all. Tests after a restart depend on the steps before them.
DEV=/root/SimicsWorkspace/development/uefi-dev
NET="restart ping port-isolation mcast foreign-mac large sizes flood frames parallel dhcp download vlan linkflap ipv6 driver-log restart pxe restart http-boot"
FUNC="restart load protocols identity nictest diag hii hiiall bind child load2 connect1 connect-rdp hold stress memfail fw-dead fw-balance driver-log restart unload unload-busy leak restart load ebs restart"
# Not in a suite (they FAIL until the findings D12-D15 are fixed): snpstate, snpdamage, txfill.
LONG="restart load soak restart warm-reset"
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
        $DEV/misc/tests/*/$S.sh || FAILED+=" $S"
    fi
done

echo "== failed:${FAILED:- none}"
[ -z "$FAILED" ]
