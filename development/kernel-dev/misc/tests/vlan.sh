#!/bin/bash
# Usage: vlan.sh [A:B] [id]   Loopback pair (default 0:1, VLAN 50): 802.1Q netdev on both ports, ping A->B and B->A over it, frames on the host tap carry the tag; VLAN removed. Needs: ixd.sh done, ports not in a bridge. Changes: ports, host taps (restored). Time: ~15 s.
# From: BATS hsd1808609984 (create vlan on pf) + traffic.
. "$(dirname "$0")/../lib.sh"
read -r A B <<< "$(pair_split $1)"
ID=${2:-50}
N=10
VA=10.98.0.1
VB=10.98.0.2
guest_need
dmesg_mark
loop_up $A $B || finish
VDA=kdev-v$ID
VDB=kdev-v$ID

at_exit 'g "ip link del $VDA" 2> /dev/null; gb "ip link del $VDB" 2> /dev/null'
g "ip link add link $LOOP_DEV_A name $VDA type vlan id $ID && ip addr add $VA/24 dev $VDA && ip link set $VDA up" || true
gb "ip link add link $LOOP_DEV_B name $VDB type vlan id $ID && ip addr add $VB/24 dev $VDB && ip link set $VDB up" || true
check "port $A vlan $ID netdev" "$(g "ip -d link show dev $VDA" 2>&1 | grep -oE 'vlan protocol \S+ id [0-9]+' || echo none)" "802.1Q id $ID$"
check "port $B vlan $ID netdev" "$(gb "ip -d link show dev $VDB" 2>&1 | grep -oE 'vlan protocol \S+ id [0-9]+' || echo none)" "802.1Q id $ID$"

# Tagged frames on the host side of port A (the bridge passes the tag through).
hcap_start $(tap $A) "vlan $ID and icmp"

# First packets after vlan up may go to ARP.
g "ping -n -c 3 -i 0.05 -W 1 -I $VDA $VB" > /dev/null 2>&1 || true
check "port $A -> port $B vlan $ID" "$(g "ping -n -c $N -i 0.05 -W 1 -I $VDA $VB" 2>&1 | grep transmitted || true)" " ($N|$((N - 1))) received"
check "port $B -> port $A vlan $ID" "$(gb "ping -n -c $N -i 0.05 -W 1 -I $VDB $VA" 2>&1 | grep transmitted || true)" " ($N|$((N - 1))) received"
check_ge "tap $(tap $A) tagged icmp (vlan $ID)" "$(hcap_stop)" $((2 * N))

g "ip link del $VDA" || true
gb "ip link del $VDB" || true
check_eq "vlan $ID removed" "$(g "ip link show dev $VDA" 2> /dev/null | grep -c . || true)" 0
loop_down
check_dmesg "dmesg clean"
finish
