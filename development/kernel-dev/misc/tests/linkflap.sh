#!/bin/bash
# Usage: linkflap.sh [A:B] [n]   Loopback pair (default 0:1, 5): ip link down/up of port A n times, carrier back each time, then ping A->B and B->A. Needs: ixd.sh done, ports not in a bridge. Changes: ports, host taps (restored). Time: ~5 s + 2 s/flap.
. "$(dirname "$0")/../lib.sh"
read -r A B <<< "$(pair_split $1)"
N=${2:-5}
guest_need
dmesg_mark
loop_up $A $B || finish

for I in $(seq $N); do
    g "ip link set $LOOP_DEV_A down"
    check_eq "port $A flap $I down" "$(g "cat /sys/class/net/$LOOP_DEV_A/operstate")" down
    g "ip link set $LOOP_DEV_A up"
    loop_wait_carrier 1 30
    check_eq "port $A flap $I up" "$(loop_carrier a)" 1
done

# Addresses stay over down/up.
loop_first_traffic
check "port $A -> port $B" "$(loop_ping_ab 10)" " (10|9) received"
check "port $B -> port $A" "$(loop_ping_ba 10)" " (10|9) received"

loop_down
check_dmesg "dmesg clean"
finish
