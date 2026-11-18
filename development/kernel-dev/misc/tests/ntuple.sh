#!/bin/bash
# Usage: ntuple.sh [A:B]   Loopback pair (default 0:1): on port A an ip6 src-ip rule is added, listed by ethtool -n and deleted; an ip6 src-ip rule (B's link-local -> last RX queue) steers B's ping6: that queue's rx_q-N_pkts grows by >= n-1; ip4 rule support = INFO. Needs: ixd.sh done, ports not in a bridge. Changes: ports (rules removed), host taps (restored). Time: ~20 s.
# From: BATS hsd16016894461 (ip6 src-ip single tuple rule added + visible) + steering check.
. "$(dirname "$0")/../lib.sh"
read -r A B <<< "$(pair_split $1)"
N=20
SRC6=2001:db8:0:f101::2
guest_need
dmesg_mark
loop_up $A $B || finish
D=$LOOP_DEV_A
check_eq "port $A ntuple-filters" "$(g "ethtool -k $D" | awk '/^ntuple-filters:/ { print $2 }')" on

# add_rule <spec>: ethtool -N ... -> rule id ("Added rule with ID <n>"); on error
# empty, ethtool's message printed as INFO (stderr, not captured by $(...)).
add_rule() {
    local OUT
    OUT=$(g "ethtool -N $D $* 2>&1" || true)
    grep -oP 'Added rule with ID \K[0-9]+' <<< "$OUT" || { echo "INFO ethtool -N $D $*: $OUT" | tr '\n' ' ' >&2; echo >&2; }
}

# --- BATS case: ip6 rule added, visible, deleted ------------------------------
ID6=$(add_rule flow-type ip6 src-ip $SRC6 action 1)
check "port $A ip6 rule added" "${ID6:-none}" "^[0-9]+$"
if [ -n "$ID6" ]; then
    at_exit "g \"ethtool -N $D delete $ID6 2> /dev/null\""
    check "port $A ip6 rule listed" "$(g "ethtool -n $D" | grep -c "$SRC6" || true)" "^[1-9]"
    g "ethtool -N $D delete $ID6" || true
    check_eq "port $A ip6 rule deleted" "$(g "ethtool -n $D" | grep -c "$SRC6" || true)" 0
fi

# --- ip4 rule: supported? (INFO, BATS covers ip6 only) ------------------------
ID4=$(add_rule flow-type ip4 src-ip $LOOP_IP_B action 1 2> /dev/null)
if [ -n "$ID4" ]; then
    echo "INFO port $A ip4 user flow rules supported"
    g "ethtool -N $D delete $ID4" || true
else
    echo "INFO port $A ip4 user flow rules not supported (EOPNOTSUPP)"
fi

# --- Steering: B's ping6 (link-local) lands in the last RX queue --------------
Q=$(( $(g "ethtool -l $D" | awk '/^Current/ { c = 1 } c && /^Combined:/ { print $2 }') - 1 ))
qrx() {
    g "ethtool -S $D" | awk -v q="rx_q-$1_pkts:" '$1 == q { print $2 }'
}
LLA=$(g "ip -6 -o addr show dev $D scope link" | grep -oP 'inet6 \K[^/]+' | head -1)
LLB=$(gb "ip -6 -o addr show dev $LOOP_DEV_B scope link" | grep -oP 'inet6 \K[^/]+' | head -1)
check "port $A/$B link-local addresses" "${LLA:-none} ${LLB:-none}" "^fe80.* fe80"
# Static neighbours: NDP is multicast, which ixd ports do not receive (F4).
MACA=$(g "cat /sys/class/net/$D/address")
MACB=$(gb "cat /sys/class/net/$LOOP_DEV_B/address")
g "ip -6 neigh replace $LLB lladdr $MACB dev $D nud permanent" || true
gb "ip -6 neigh replace $LLA lladdr $MACA dev $LOOP_DEV_B nud permanent" || true
# qall: "q:pkts ..." of all RX queues (where did packets go).
qall() {
    g "ethtool -S $D" | awk -F'[-_: ]+' '/^ *rx_q-[0-9]+_pkts:/ { printf "%s:%s ", $4, $NF }'
}
ping6_ba() {
    gb "ping -6 -n -c $N -i 0.05 -W 1 -I $LOOP_DEV_B $LLA" 2>&1 | grep transmitted || true
}
# Control: IPv6 without any rule (static neighbours, DAD done).
loop_wait_dad
check_eq "port $A/$B ipv6 not tentative" "$(g "ip -6 addr show dev $D tentative" | grep -c inet6 || true)$(gb "ip -6 addr show dev $LOOP_DEV_B tentative" | grep -c inet6 || true)" 00
B0=$(qall)
check "port $B -> port $A ping6, no rule (control)" "$(ping6_ba)" " ($N|$((N - 1))) received"
echo "INFO rx queues before: $B0 after: $(qall)"

ID6=$(add_rule flow-type ip6 src-ip $LLB action $Q)
check "port $A ip6 rule src $LLB -> queue $Q added" "${ID6:-none}" "^[0-9]+$"
if [ -n "$ID6" ] && [ -n "$LLA" ]; then
    at_exit "g \"ethtool -N $D delete $ID6 2> /dev/null\""
    R0=$(qrx $Q)
    B0=$(qall)
    check "port $B -> port $A ping6, steered" "$(ping6_ba)" " ($N|$((N - 1))) received"
    echo "INFO rx queues before: $B0 after: $(qall)"
    R1=$(qrx $Q)
    check_ge "port $A rx_q-${Q}_pkts + (steered)" $((${R1:-0} - ${R0:-0})) $((N - 1))
    g "ethtool -N $D delete $ID6" || true
    check_eq "port $A ip6 steering rule deleted" "$(g "ethtool -n $D" | grep -c "$LLB" || true)" 0
fi

check "port $A -> port $B" "$(loop_ping_ab 10)" " (10|9) received"
loop_down
check_dmesg "dmesg clean"
finish
