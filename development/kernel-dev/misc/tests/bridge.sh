#!/bin/bash
# Usage: bridge.sh [A:B] [case ...]   Bridge offload on port A's PF (switchdev): guest bridge = uplink A + representors of 2 SFs (SF netdevs in netns); LP = port B. Cases (default sf0-sf1 lp-sf0 sf0-lp; age = F7 check, not default) sf0->sf1, lp->sf0, sf0->lp (initiator first, fresh bridge + ARP each): ping both ways, initiator's ARP seen on the slow path (control), FDB entries of both MACs "offload", then a 2nd burst not seen on uplink/representors (slow path); sf<->sf not on the host tap, lp<->sf on it; age: lp->sf0 for > 2x bridge ageing time (AGE=3 s) stays offloaded (FAILs: F7). Step: bridge:0:1,age. Needs: ixd.sh done, eswitch switchdev, ports not in a bridge. Changes: driver (2 SFs added + removed), ports, host taps (restored). Time: ~1 min, + ~1 min with age.
# Setup like scripts/set-switchdev-pfp.sh (SFs in netns, representors + uplink in a bridge).
. "$(dirname "$0")/../lib.sh"
read -r A B <<< "$(pair_split $1)"
N=20
BR=kdev-br
guest_need
dmesg_mark
loop_up $A $B || finish
U=$LOOP_DEV_A
PCI=$(pci_of $U)
check_eq "port $A eswitch (pci/$PCI)" "$(g "devlink dev eswitch show pci/$PCI" | grep -oP 'mode \K\S+' || true)" switchdev
[ $FAILS = 0 ] || finish

# Endpoints: netns, IP, MAC. LP = port B (loopback side B). Uplink A is a bridge port: no IP.
declare -A NS IP MAC
NS[lp]=$LOOP_NS
IP[lp]=$LOOP_IP_B
MAC[lp]=$(gb "cat /sys/class/net/$LOOP_DEV_B/address")
g "ip addr flush dev $U" || true
declare -a SFR
for I in 0 1; do
    E=sf$I
    sf_add $PCI $((70 + I)) || finish
    SFR[$I]=$SF_REPR
    NS[$E]=kdev-$E
    IP[$E]=10.99.0.$((11 + I))
    g "ip netns add ${NS[$E]}; ip link set $SF_DEV netns ${NS[$E]}
       ip -n ${NS[$E]} addr add ${IP[$E]}/24 dev $SF_DEV
       ip -n ${NS[$E]} link set $SF_DEV up; ip -n ${NS[$E]} link set lo up" || true
    # Netns gone -> SF netdev back to the init ns, then sf_add's hook deletes the SF.
    at_exit "g \"ip netns del ${NS[$E]} 2> /dev/null\""
    MAC[$E]=$(gn ${NS[$E]} "cat /sys/class/net/$SF_DEV/address")
    echo "INFO $E: sfnum $((70 + I)) $SF_PORT repr $SF_REPR netdev $SF_DEV (${NS[$E]}, ${IP[$E]}, ${MAC[$E]})"
    check_eq "$E carrier" "$(gn ${NS[$E]} "cat /sys/class/net/$SF_DEV/carrier" 2> /dev/null || echo none)" 1
done
echo "INFO lp: port $B $LOOP_DEV_B (${NS[lp]}, ${IP[lp]}, ${MAC[lp]}); uplink port $A $U ($PCI)"
at_exit "g \"ip link del $BR 2> /dev/null\""

# ping_from <from> <to> <count>: "transmitted" line.
ping_from() {
    gn ${NS[$1]} "ping -n -c $3 -i 0.05 -W 1 ${IP[$2]}" 2>&1 | grep transmitted || true
}
# fdb <mac>: the bridge FDB line of <mac> (empty if not learned).
fdb() {
    g "bridge fdb show br $BR" | grep -i "^$1 " | head -1 || true
}

# bcase <from> <to>: one case on a fresh bridge (nothing learned, empty ARP caches).
bcase() {
    local F=$1 T=$2 L="$1->$2" E S CU C0 C1 W
    g "ip link add $BR type bridge stp_state 0 forward_delay 0
       ip link set $U master $BR; ip link set ${SFR[0]} up master $BR; ip link set ${SFR[1]} up master $BR
       ip link set $BR up" || true
    for E in sf0 sf1 lp; do gn ${NS[$E]} "ip neigh flush all" || true; done
    check_eq "$L bridge ports forwarding" "$(g "bridge link show master $BR" | grep -c 'state forwarding' || true)" 3

    # 1st burst, initiator only: ARP (flooded) + learning on the slow path, then offload.
    # Every ICMP seen on the uplink / representors = slow path; report which
    # device, request/reply and seq. Control: the initiator's ARP is seen there.
    gcap_start $U "arp or icmp" up
    gcap_start ${SFR[0]} "arp or icmp" r0
    gcap_start ${SFR[1]} "arp or icmp" r1
    check "$L ping (1st)" "$(ping_from $F $T $N)" " ($N|$((N - 1))) received"
    gcap_stop up r0 r1 > /dev/null
    local ARP=0 SLOW=0 LATE=0 D X Y
    for D in up r0 r1; do
        X=$(gcap_lines $D)
        case "$F:$D" in lp:up|sf0:r0|sf1:r1) ARP=$(grep -c ARP <<< "$X" || true) ;; esac
        # "... ICMP echo request, id 7, seq 3, length 64" -> "request:3"
        Y=$(grep -oP 'echo \K(request|reply), id \d+, seq \d+' <<< "$X" | sed 's/, id [0-9]*, seq /:/' | tr '\n' ' ' || true)
        echo "INFO $L 1st burst slow path on $D: ${Y:-none}"
        SLOW=$((SLOW + $(wc -w <<< "$Y")))
        # Learning may take the first packets; after seq 3 all must be offloaded.
        LATE=$((LATE + $(tr ' ' '\n' <<< "$Y" | awk -F: '$2 > 3' | grep -c . || true)))
    done
    check_ge "$L slow path arp on $F's bridge port (control)" "$ARP" 1
    echo "INFO $L 1st burst: $SLOW ICMP on the slow path (of $((2 * N)) request+reply, counted per device)"
    check_eq "$L 1st burst slow path icmp after seq 3" "$LATE" 0

    for E in $F $T; do
        for S in $(seq 30); do
            [[ $(fdb ${MAC[$E]}) == *offload* ]] && break
            sleep 1
        done
        check "$L fdb $E ${MAC[$E]} offloaded" "$(fdb ${MAC[$E]} | sed 's/ *$//'; true)" " offload"
    done

    check "$T->$F ping" "$(ping_from $T $F $N)" " ($N|$((N - 1))) received"
    # 2nd burst: must be switched by the card. Slow path = ICMP seen on uplink / representors.
    gcap_start $U icmp up
    gcap_start ${SFR[0]} icmp r0
    gcap_start ${SFR[1]} icmp r1
    hcap_start $(tap $A) icmp
    check "$L ping, offloaded" "$(ping_from $F $T $N)" " ($N|$((N - 1))) received"
    read -r CU C0 C1 <<< "$(gcap_stop up r0 r1)"
    W=$(hcap_stop)
    check_eq "$L slow path icmp (uplink ${CU:-?}, repr0 ${C0:-?}, repr1 ${C1:-?})" $((${CU:-99} + ${C0:-99} + ${C1:-99})) 0
    if [[ $F$T == *lp* ]]; then
        check_ge "$L icmp on host tap $(tap $A) (on the wire)" "$W" $((2 * N - 2))
    else
        check_eq "$L icmp on host tap $(tap $A) (switched in the card)" "$W" 0
    fi

    g "ip link del $BR" || true
    for E in $F $T; do
        check_eq "$L fdb $E gone with the bridge" "$(g "bridge fdb show" | grep -ci "^${MAC[$E]} .*offload" || true)" 0
    done
}

CASES=${*:2}
CASES=${CASES:-sf0-sf1 lp-sf0 sf0-lp}
for C in $CASES; do
    [ $C = age ] && continue
    bcase ${C%-*} ${C#*-}
done

# bage: ageing case. Continuous lp->sf0 traffic, bridge ageing time AGE s (guest time).
# An offloaded entry in use must stay offloaded: no slow path after learning.
bage() {
    AGE=${AGE:-3}
    M=200
    g "ip link add $BR type bridge stp_state 0 forward_delay 0 ageing_time $((AGE * 100))
       ip link set $U master $BR; ip link set ${SFR[0]} up master $BR; ip link set ${SFR[1]} up master $BR
       ip link set $BR up" || true
    check_eq "ageing $AGE s bridge ports forwarding" "$(g "bridge link show master $BR" | grep -c 'state forwarding' || true)" 3
    gcap_start $U icmp up
    gcap_start ${SFR[0]} icmp r0
    T0=$(g "cat /proc/uptime" | cut -d' ' -f1)
    check "ageing $AGE s lp->sf0 $M pings" "$(ping_from lp sf0 $M)" " ($M|$((M - 1))|$((M - 2))) received"
    T1=$(g "cat /proc/uptime" | cut -d' ' -f1)
    gcap_stop up r0 > /dev/null
    echo "INFO ageing $AGE s: traffic for $(awk -v a=$T0 -v b=$T1 'BEGIN { printf "%.1f", b - a }') s guest time"
    LATE=0
    for D in up r0; do
        Y=$(gcap_lines $D | grep -oP 'echo (request|reply), id \d+, seq \d+' | sed 's/echo //; s/, id [0-9]*, seq /:/' | tr '\n' ' ' || true)
        echo "INFO ageing $AGE s slow path on $D: ${Y:-none}"
        LATE=$((LATE + $(tr ' ' '\n' <<< "$Y" | awk -F: '$2 > 3' | grep -c . || true)))
    done
    check_eq "ageing $AGE s slow path icmp after seq 3 (entries in use must not age out)" "$LATE" 0
    g "ip link del $BR" || true
}
if [[ " $CASES " == *" age "* ]]; then
    bage
fi

# Remove bridge, netns, SFs and the loopback now: their errors count in dmesg too.
lib_exit
check_dmesg "dmesg clean"
finish
