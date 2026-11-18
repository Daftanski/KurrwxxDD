#!/bin/bash
# Usage: allmulti.sh [A:B]   Loopback pair (default 0:1): B sends to group 224.1.1.1 (frames checked on the host tap); port A receives it when joined, with ALLMULTI on, not with it off (tcpdump -p, no promisc); control: unicast seen by the same capture. Needs: ixd.sh done, ports not in a bridge. Changes: ports, host taps (restored). Time: ~30 s.
# From: BATS hsd1807734575 (entering / leaving allmulti mode) + multicast receive check.
. "$(dirname "$0")/../lib.sh"
read -r A B <<< "$(pair_split $1)"
N=10
GRP=224.1.1.1
GMAC=01:00:5e:01:01:01
guest_need
dmesg_mark
loop_up $A $B || finish
D=$LOOP_DEV_A
at_exit "g \"ip link set dev $D allmulticast off; ip maddr del $GMAC dev $D 2> /dev/null\""
# B needs a multicast route in its netns (no default route there).
gb "ip route add 224.0.0.0/4 dev $LOOP_DEV_B" || true

# mc <label> <want: min | 0>: B sends N to the group; check wire (host tap A) and port A rx.
mc() {
    hcap_start $(tap $A) "ether dst $GMAC"
    gcap_start $D "ether dst $GMAC"
    gb "ping -n -c $N -i 0.05 -W 1 -I $LOOP_DEV_B $GRP" > /dev/null 2>&1 || true
    RX=$(gcap_stop)
    WIRE=$(hcap_stop)
    check_ge "port $B multicast on the wire ($1)" "$WIRE" $((N - 1))
    if [ $2 = 0 ]; then
        check_eq "port $A multicast rx, $1" "$RX" 0
    else
        check_ge "port $A multicast rx, $1" "$RX" $2
    fi
}

# Control: the capture sees unicast from B (rules out the capture method).
gcap_start $D "icmp and src $LOOP_IP_B"
loop_ping_ba $N > /dev/null
check_ge "port $A capture works (unicast from $B)" "$(gcap_stop)" $((N - 1))

g "ip maddr add $GMAC dev $D" || true
mc "group joined" $((N - 1))
g "ip maddr del $GMAC dev $D" || true

g "ip link set dev $D allmulticast on"
check_eq "port $A ALLMULTI on" "$(g "ip link show dev $D" | head -1 | grep -c ALLMULTI || true)" 1
mc "allmulti on" $((N - 1))

g "ip link set dev $D allmulticast off"
check_eq "port $A ALLMULTI off" "$(g "ip link show dev $D" | head -1 | grep -c ALLMULTI || true)" 0
mc "allmulti off" 0

check "port $A -> port $B" "$(loop_ping_ab 10)" " (10|9) received"
loop_down
check_dmesg "dmesg clean"
finish
