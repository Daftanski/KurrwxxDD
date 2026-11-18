#!/bin/bash
# Usage: mtu.sh [A:B] [mtu]   Loopback pair (default 0:1, 9000): MTU on both ports + taps; full-size DF ping A->B and B->A, 1 byte more with DF refused, MTU above maxmtu refused; MTU restored. Needs: ixd.sh done, ports not in a bridge. Changes: ports, host taps (restored). Time: ~40 s.
. "$(dirname "$0")/../lib.sh"
read -r A B <<< "$(pair_split $1)"
MTU=${2:-9000}
S=$((MTU - 28))
guest_need
dmesg_mark
loop_up $A $B || finish

loop_mtu $MTU
check_eq "port $A mtu" "$(g "cat /sys/class/net/$LOOP_DEV_A/mtu")" $MTU
check_eq "port $B mtu" "$(gb "cat /sys/class/net/$LOOP_DEV_B/mtu")" $MTU
# An MTU change may reset the queues: links + traffic back first.
loop_wait_carrier 1 30
loop_first_traffic

check "port $A -> port $B $S DF" "$(loop_ping_ab 3 -M do -s $S)" " [23] received"
check "port $B -> port $A $S DF" "$(loop_ping_ba 3 -M do -s $S)" " [23] received"
# Local error "message too long": nothing received.
check "port $A $((S + 1)) DF refused" "$(loop_ping_ab 1 -M do -s $((S + 1)))" " 0 received"

MAX=$(g "ip -d link show dev $LOOP_DEV_A" | grep -oP 'maxmtu \K[0-9]+' || true)
check "port $A maxmtu" "${MAX:-none}" "^[0-9]+$"
if [ -n "$MAX" ]; then
    check_eq "port $A mtu $((MAX + 1)) refused" "$(g "ip link set dev $LOOP_DEV_A mtu $((MAX + 1)) 2> /dev/null && echo accepted || echo refused")" refused
fi

D=$LOOP_DEV_A
WANT=${LOOP_SAVE[mtuA]}
loop_down
check_eq "port $A mtu restored" "$(g "cat /sys/class/net/$D/mtu")" $WANT
check_dmesg "dmesg clean"
finish
