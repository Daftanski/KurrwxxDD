#!/bin/bash
# Usage: mtu.sh [port] [mtu]   Jumbo MTU (default port 0, 9000) on guest netdev + host tap: full-size DF ping both ways, 1 byte more with DF refused, MTU above maxmtu refused. Needs: ixd.sh done, port not in a bridge. Changes: port MTU (restored). Time: ~15 s.
. "$(dirname "$0")/../lib.sh"
P=${1:-0}
MTU=${2:-9000}
S=$((MTU - 28))
guest_need
dmesg_mark
port_up $P || finish
D=${PORT_DEV[$P]}

g "ip link set dev $D mtu $MTU" || true
ip link set dev $(tap $P) mtu $MTU
check_eq "port $P guest mtu" "$(g "cat /sys/class/net/$D/mtu")" $MTU
# An MTU change may reset the queues: link back first.
port_wait_carrier $P 1 30
guest_ping $P 1 > /dev/null

check "port $P guest->host $S DF" "$(guest_ping $P 3 -M do -s $S)" " [23] received"
check "port $P host->guest $S DF" "$(host_ping $P 3 -M do -s $S)" " [23] received"
# Local error "message too long": nothing received.
check "port $P guest $((S + 1)) DF refused" "$(guest_ping $P 1 -M do -s $((S + 1)))" " 0 received"

MAX=$(g "ip -d link show dev $D" | grep -oP 'maxmtu \K[0-9]+' || true)
check "port $P maxmtu" "${MAX:-none}" "^[0-9]+$"
if [ -n "$MAX" ]; then
    check_eq "port $P mtu $((MAX + 1)) refused" "$(g "ip link set dev $D mtu $((MAX + 1)) 2> /dev/null && echo accepted || echo refused")" refused
fi

port_down $P
check_eq "port $P mtu restored" "$(g "cat /sys/class/net/$D/mtu")" ${PORT_MTU[$P]}
check_dmesg "dmesg clean"
finish
