#!/bin/bash
# Usage: bridge.sh [A:B]   Bridge offload on port A's PF (switchdev): guest bridge = uplink A + representors of 2 SFs (SF netdevs in netns); LP = port B. Cases sf0->sf1, lp->sf0, sf0->lp (initiator first, fresh bridge + ARP each): ping both ways, initiator's ARP seen on the slow path (control), FDB entries of both MACs "offload", then a 2nd burst not seen on uplink/representors (slow path); sf<->sf not on the host tap, lp<->sf on it. Needs: ixd.sh done, eswitch switchdev, ports not in a bridge. Changes: driver (2 SFs added + removed), ports, host taps (restored). Time: ~1 min.
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

    # 1st burst: initiator ARPs (flooded), bridge learns on the slow path, driver offloads.
    # Control: that ARP is seen on the initiator's bridge port (the capture sees slow path).
    gcap_start $U arp up
    gcap_start ${SFR[0]} arp r0
    gcap_start ${SFR[1]} arp r1
    check "$L ping" "$(ping_from $F $T $N)" " ($N|$((N - 1))) received"
    read -r CU C0 C1 <<< "$(gcap_stop up r0 r1)"
    case $F in
        lp)  W=$CU ;;
        sf0) W=$C0 ;;
        sf1) W=$C1 ;;
    esac
    check_ge "$L slow path arp on $F's bridge port (control; uplink ${CU:-?}, repr0 ${C0:-?}, repr1 ${C1:-?})" "${W:-0}" 1
    check "$T->$F ping" "$(ping_from $T $F $N)" " ($N|$((N - 1))) received"
    for E in $F $T; do
        for S in $(seq 30); do
            [[ $(fdb ${MAC[$E]}) == *offload* ]] && break
            sleep 1
        done
        check "$L fdb $E ${MAC[$E]} offloaded" "$(fdb ${MAC[$E]} | sed 's/ *$//'; true)" " offload"
    done

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

bcase sf0 sf1
bcase lp sf0
bcase sf0 lp

# Remove bridge, netns, SFs and the loopback now: their errors count in dmesg too.
lib_exit
check_dmesg "dmesg clean"
finish
