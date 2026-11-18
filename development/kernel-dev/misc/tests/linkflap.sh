#!/bin/bash
# Usage: linkflap.sh [port] [n]   Guest ip link down/up n times (default port 0, 5): carrier back each time, then ping both ways. Needs: ixd.sh done, port not in a bridge. Changes: port (restored). Time: ~15 s + 10 s/flap.
. "$(dirname "$0")/../lib.sh"
P=${1:-0}
N=${2:-5}
guest_need
dmesg_mark
port_up $P || finish
D=${PORT_DEV[$P]}

for I in $(seq $N); do
    g "ip link set $D down"
    check_eq "port $P flap $I down" "$(g "cat /sys/class/net/$D/operstate")" down
    g "ip link set $D up"
    port_wait_carrier $P 1 30
    check_eq "port $P flap $I up" "$(port_carrier $P)" 1
done

# Addresses stay over down/up; first ping may be lost to ARP.
guest_ping $P 1 > /dev/null
check "port $P guest->host" "$(guest_ping $P 5)" " [345] received"
check "port $P host->guest" "$(host_ping $P 5)" " [345] received"

port_down $P
check_dmesg "dmesg clean"
finish
