#!/bin/bash
# Usage: pfreset.sh [A:B] [n]   Loopback pair (default 0:1, 3): n times PCI function reset of port A's PF (sysfs device/reset) + ethtool -t (refused cleanly if unsupported); after each: netdev back, link, ping A->B / B->A, no BUG/ixd error. Needs: ixd.sh done, PFP (port = own PF), ports not in a bridge. Changes: driver (PF reset; on F5 port A stays dead until restart), host taps (restored). Time: ~2 min/cycle on F5.
# From: BATS hsd18021458126 (PF reset + selftest in a loop, no crash); reset via PCI FLR instead of i40e debugfs.
. "$(dirname "$0")/../lib.sh"
read -r A B <<< "$(pair_split $1)"
N=${2:-3}
guest_need
if [ "$PFP" != TRUE ]; then
    echo "FAIL pfreset needs PFP (PFD: all ports on one PF, a reset takes all of them)"
    exit 1
fi
dmesg_mark
loop_up $A $B || finish
PCI=$(g "basename \$(readlink -f /sys/class/net/$LOOP_DEV_A/device)")
echo "INFO port $A ($LOOP_DEV_A) PF $PCI"

for I in $(seq $N); do
    check "cycle $I reset $PCI" "$(g "echo 1 > /sys/bus/pci/devices/$PCI/reset 2>&1; echo rc=\$?" | tr '\n' ' ')" "rc=0 $"
    # Netdev may be re-created: wait for it (by MAC), then for link + traffic.
    for S in $(seq 60); do
        D=$(guest_dev $A)
        [ -n "$D" ] && break
        sleep 2
    done
    check "cycle $I port $A netdev" "${D:-none}" "^eth[0-9]+$"
    [ -n "$D" ] || break
    if [ "$D" != "$LOOP_DEV_A" ]; then
        echo "INFO cycle $I netdev renamed $LOOP_DEV_A -> $D"
        LOOP_DEV_A=$D
    fi
    g "ip addr replace $LOOP_IP_A/24 dev $D; ip link set $D up" || true
    loop_wait_carrier 1 60
    check_eq "cycle $I port $A link" "$(loop_carrier a)" 1
    loop_first_traffic
    check "cycle $I port $A -> port $B" "$(loop_ping_ab 10)" " (10|9) received"
    check "cycle $I port $B -> port $A" "$(loop_ping_ba 10)" " (10|9) received"

    OUT=$(g "ethtool -t $D 2>&1; echo rc=\$?" | tr '\n' ' ')
    echo "INFO cycle $I ethtool -t: $OUT"
    check "cycle $I ethtool -t done or refused" "$OUT" "rc=[0-9]+ $"
done

loop_down
check_dmesg "dmesg clean"
finish
