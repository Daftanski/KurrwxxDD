#!/bin/bash
# Usage: bridge.sh [A:B] [case ...]   Bridge offload on port A's PF (switchdev): guest bridge = uplink A + representors of 2 SFs (SF netdevs in netns); LP = port B. Cases (default: all but the bug checks age (F7), lp-sf0-warm (F8), static-replace (F9), uplink-down (F10)): from-to[@ping interval], host = Simics host as LP, fresh bridge + ARP each: initiator's 1st burst per device/seq (no ICMP on uplink or representors after seq 3, ARP control), FDB entry of each MAC on its own port (LP on the uplink) + offload right after the burst and after a wait, 2nd burst 0 slow path, sf<->sf not on the host tap; static = entries added by hand (bridge fdb add ... static) offloaded before traffic, 0 slow path from seq 1, survive ageing, deleted from hw too (relearned); static-wrong = sf0's MAC on the uplink (plain static: moved by the bridge; sticky: sf1->sf0 goes to the wire, no hairpin, recovers); static-teardown = port out of the bridge / bridge deleted (no stale hw flows); mac-move = sf0's MAC moves repr0 -> uplink -> back (flow follows); sf-del = SF deleted while bridged; uplink = uplink nomaster and back; uplink-down (F10 check, not default) = uplink down/up, SF traffic and representor carrier must survive; repr-updown = representor down / up (SF carrier follows); lp-sf0-warm (F8 check, not default) = sf0 known, LP's ARP warm: LP must be learned; static-replace (F9 check, not default) = static over a learned entry (one entry, not aged); age = learned entries in use must not age out. Needs: ixd.sh done, eswitch switchdev, ports not in a bridge. Changes: driver (2 SFs added + removed), ports, host taps (restored). Time: ~4 min.
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

# Endpoints: netns, IP, MAC, bridge port (DEV). LP = port B (loopback side B),
# reached through the uplink A. Uplink A is a bridge port: no IP.
declare -A NS IP MAC DEV NDEV
NS[lp]=$LOOP_NS
IP[lp]=$LOOP_IP_B
MAC[lp]=$(gb "cat /sys/class/net/$LOOP_DEV_B/address")
DEV[lp]=$U
g "ip addr flush dev $U" || true
for I in 0 1; do
    E=sf$I
    sf_add $PCI $((70 + I)) || finish
    DEV[$E]=$SF_REPR
    NDEV[$E]=$SF_DEV
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
# host = the Simics host as LP (like a manual setup with an IP on cnic_tap_0_P):
# IP on the host side of the cable (bridge LOOP_BR of the taps). Its Linux stack
# also sends its own frames (IPv6 RS / MLD ...) on the wire.
NS[host]=""
IP[host]=10.99.0.3
MAC[host]=$(cat /sys/class/net/$LOOP_BR/address)
DEV[host]=$U
ip addr add ${IP[host]}/24 dev $LOOP_BR
at_exit "ip addr del ${IP[host]}/24 dev $LOOP_BR 2> /dev/null"
echo "INFO host: $LOOP_BR (${IP[host]}, ${MAC[host]})"
at_exit "g \"ip link del $BR 2> /dev/null\""

# --- Helpers ------------------------------------------------------------------
# br_create [ageing s]: new bridge (nothing learned), ports in the order of
# set-switchdev-pfp.sh (uplink first), empty ARP caches.
br_create() {
    local AG="" E
    [ -n "$1" ] && AG="ageing_time $(($1 * 100))"
    g "ip link add $BR type bridge stp_state 0 forward_delay 0 $AG
       ip link set $U master $BR; ip link set ${DEV[sf0]} up master $BR; ip link set ${DEV[sf1]} up master $BR
       ip link set $BR up" || true
    for E in sf0 sf1 lp; do gn ${NS[$E]} "ip neigh flush all" || true; done
    ip neigh flush dev $LOOP_BR || true
}

# on <endpoint> <cmd>: run on the endpoint (host: locally, else in its guest netns).
on() {
    if [ $1 = host ]; then
        bash -c "${*:2}"
    else
        gn ${NS[$1]} "${*:2}"
    fi
}

# ping_from <from> <to> <count> [interval]: "transmitted" line.
ping_from() {
    on $1 "ping -n -c $3 -i ${4:-0.05} -W 1 ${IP[$2]}" 2>&1 | grep transmitted || true
}

# fdb <endpoint>: all bridge FDB lines of its MAC, ";" separated (empty: not in the FDB).
fdb() {
    g "bridge fdb show br $BR" | grep -i "^${MAC[$1]} " | sed 's/ *$//' | paste -sd';' || true
}
# fdb_ok <endpoint>: 1 if its MAC is on its own bridge port and marked offload.
fdb_ok() {
    [[ ";$(fdb $1);" == *"dev ${DEV[$1]} "*offload* ]] && echo 1 || echo 0
}
# check_fdb <label> <endpoint> <max wait s>: on its port + offload, report the wait.
check_fdb() {
    local S=0
    while [ "$(fdb_ok $2)" = 0 ] && [ $S -lt $3 ]; do
        sleep 1
        S=$((S + 1))
    done
    check "$1 fdb $2 on ${DEV[$2]} offload (after $S s)" "$(fdb $2)" "dev ${DEV[$2]} .*offload"
}

# Slow path capture: ARP + ICMP on the uplink and both representors.
SLOWDEV=(up r0 r1)
slow_start() {
    gcap_start $U "arp or icmp" up
    gcap_start ${DEV[sf0]} "arp or icmp" r0
    gcap_start ${DEV[sf1]} "arp or icmp" r1
}
# slow_stop <label> <after seq>: INFO per device (request/reply:seq), sets
# SLOW_<dev> = ICMP after <after seq>, ARP_<dev> = ARP count.
slow_stop() {
    local D X Y
    gcap_stop up r0 r1 > /dev/null
    for D in "${SLOWDEV[@]}"; do
        X=$(gcap_lines $D)
        # "... ICMP echo request, id 7, seq 3, length 64" -> "request:3"
        Y=$(grep -oP 'echo \K(request|reply), id \d+, seq \d+' <<< "$X" | sed 's/, id [0-9]*, seq /:/' | tr '\n' ' ' || true)
        echo "INFO $1 slow path on $D: ${Y:-none}"
        printf -v SLOW_$D '%s' "$(tr ' ' '\n' <<< "$Y" | awk -F: -v k=$2 '$2 > k' | grep -c . || true)"
        printf -v ARP_$D '%s' "$(grep -c ARP <<< "$X" || true)"
    done
}
port_id() {
    case $1 in lp|host) echo up ;; sf0) echo r0 ;; sf1) echo r1 ;; esac
}

# --- bcase <from> <to> [interval]: learned entries --------------------------------
bcase() {
    local F=$1 T=$2 IV=${3:-0.05} L="$1->$2" E V W N1=$N
    [ $IV = 0.05 ] || { L="$L@$IV"; N1=10; }
    br_create
    check_eq "$L bridge ports forwarding" "$(g "bridge link show master $BR" | grep -c 'state forwarding' || true)" 3

    # 1st burst, initiator only: ARP (flooded) + learning on the slow path, then offload.
    slow_start
    check "$L ping (1st)" "$(ping_from $F $T $N1 $IV)" " ($N1|$((N1 - 1))) received"
    slow_stop "$L 1st burst" 3
    V=ARP_$(port_id $F)
    check_ge "$L slow path arp on $F's port (control)" "${!V}" 1
    # Learning may take the first packets; after seq 3 all must be offloaded.
    check_eq "$L 1st burst icmp on uplink after seq 3" "$SLOW_up" 0
    check_eq "$L 1st burst icmp on representors after seq 3" "$((SLOW_r0 + SLOW_r1))" 0

    # FDB right after the burst (no wait), then with a wait.
    for E in $F $T; do
        echo "INFO $L fdb $E right after the burst: $(fdb $E)"
        check_eq "$L fdb $E on ${DEV[$E]} offload right after the burst" "$(fdb_ok $E)" 1
        [ "$(fdb_ok $E)" = 1 ] || check_fdb "$L" $E 30
    done

    # 2nd burst, both ways: must be switched by the card.
    check "$T->$F ping" "$(ping_from $T $F $N)" " ($N|$((N - 1))) received"
    slow_start
    hcap_start $(tap $A) icmp
    check "$L ping (2nd)" "$(ping_from $F $T $N)" " ($N|$((N - 1))) received"
    W=$(hcap_stop)
    slow_stop "$L 2nd burst" 0
    check_eq "$L 2nd burst icmp on uplink" "$SLOW_up" 0
    check_eq "$L 2nd burst icmp on representors" "$((SLOW_r0 + SLOW_r1))" 0
    if [[ $F$T == *lp* || $F$T == *host* ]]; then
        check_ge "$L icmp on host tap $(tap $A) (on the wire)" "$W" $((2 * N - 2))
    else
        check_eq "$L icmp on host tap $(tap $A) (switched in the card)" "$W" 0
    fi

    g "ip link del $BR" || true
    for E in $F $T; do
        check_eq "$L fdb $E gone with the bridge" "$(g "bridge fdb show" | grep -ci "^${MAC[$E]} .*offload" || true)" 0
    done
}

# --- scase: entries added by hand (static) ----------------------------------------
# Offloaded before any traffic; ICMP never on the slow path (from seq 1); user
# entries are skipped by the driver's ageing (AGE s bridge, traffic > 2 periods);
# deleted entries leave the FDB and traffic still works (learning).
scase() {
    local E L=static AGE=3 M=200
    br_create $AGE
    for E in lp sf0 sf1; do
        static_add $E ${DEV[$E]}
        check_fdb "$L" $E 10
        check "$L fdb $E is static" "$(fdb $E)" "static"
    done
    slow_start
    check "$L lp->sf0 ping" "$(ping_from lp sf0 $N)" " ($N|$((N - 1))) received"
    check "$L sf0->sf1 ping" "$(ping_from sf0 sf1 $N)" " ($N|$((N - 1))) received"
    check "$L sf0->lp ping" "$(ping_from sf0 lp $N)" " ($N|$((N - 1))) received"
    slow_stop "$L" 0
    check_eq "$L icmp on uplink (from seq 1)" "$SLOW_up" 0
    check_eq "$L icmp on representors (from seq 1)" "$((SLOW_r0 + SLOW_r1))" 0

    # Ageing does not touch user entries.
    slow_start
    check "$L lp->sf0 $M pings (> 2x ageing $AGE s)" "$(ping_from lp sf0 $M)" " ($M|$((M - 1))|$((M - 2))) received"
    slow_stop "$L ageing" 0
    check_eq "$L ageing icmp on slow path" "$((SLOW_up + SLOW_r0 + SLOW_r1))" 0
    for E in lp sf0 sf1; do
        check_eq "$L fdb $E still offloaded after ageing" "$(fdb_ok $E)" 1
    done

    # Delete by hand: gone (no stale offload), traffic still works (learned again).
    for E in lp sf0 sf1; do
        g "bridge fdb del ${MAC[$E]} dev ${DEV[$E]} master" || true
        check_eq "$L fdb $E static entry deleted ($(fdb $E))" "$(fdb $E | grep -c static || true)" 0
    done
    # Gone from the hardware too: a stale flow would still switch lp->sf0 in the
    # card. Without it the first packets take the slow path and the bridge learns
    # the MACs again (new extern_learn entries, offloaded).
    slow_start
    check "$L lp->sf0 ping after delete" "$(ping_from lp sf0 $N)" " ($N|$((N - 1))) received"
    slow_stop "$L after delete" 0
    check_ge "$L after delete icmp on slow path (hw flows removed)" "$((SLOW_up + SLOW_r0 + SLOW_r1))" 1
    for E in lp sf0; do
        check_fdb "$L after delete, learned again" $E 30
        check "$L fdb $E learned, not static" "$(fdb $E)" "extern_learn"
    done
    g "ip link del $BR" || true
}

# static_add <endpoint> <port dev> [add|replace]
static_add() {
    g "bridge fdb ${3:-add} ${MAC[$1]} dev $2 master static" || true
}

# --- static-replace: static entry over a learned (offloaded) one -----------------
# Learn with the default ageing (F7 would delete learned entries during the
# replace), bridge fdb replace ... static: one entry per MAC, static + offload;
# then ageing AGE s and traffic > 2 periods: user entries are not aged (0 slow path).
srcase() {
    local E L=static-replace AGE=3 M=200
    br_create
    check "$L lp->sf0 ping (learn)" "$(ping_from lp sf0 $N)" " ($N|$((N - 1))) received"
    for E in lp sf0; do
        check_fdb "$L learned" $E 10
        check "$L fdb $E learned" "$(fdb $E)" "extern_learn"
    done
    for E in lp sf0; do
        check "$L bridge fdb replace $E static" "$(g "bridge fdb replace ${MAC[$E]} dev ${DEV[$E]} master static 2>&1; echo rc=\$?" | tr '\n' ' ')" "rc=0 $"
    done
    for E in lp sf0; do
        check_fdb "$L replaced" $E 10
        check "$L fdb $E now static" "$(fdb $E)" "static"
        check_eq "$L fdb $E one entry" "$(fdb $E | tr ';' '\n' | grep -c . || true)" 1
    done
    g "ip link set $BR type bridge ageing_time $((AGE * 100))" || true
    slow_start
    check "$L lp->sf0 $M pings (> 2x ageing $AGE s)" "$(ping_from lp sf0 $M)" " ($M|$((M - 1))|$((M - 2))) received"
    slow_stop "$L ageing" 0
    check_eq "$L icmp on slow path (replaced entries not aged)" "$((SLOW_up + SLOW_r0 + SLOW_r1))" 0
    for E in lp sf0; do
        echo "INFO $L fdb $E at the end: $(fdb $E)"
        check_eq "$L fdb $E still static + offloaded" "$(fdb_ok $E)$(fdb $E | grep -c static || true)" 11
    done
    g "ip link del $BR" || true
}

# --- static-wrong: sf0's MAC put on the uplink by hand -----------------------------
# Plain static: the bridge moves it to the port the MAC is seen on (sf0 talks
# through repr0): entry ends on repr0, still static + offloaded, traffic works.
# static sticky: stays on the uplink, traffic follows it: sf1->sf0 frames leave
# through port A to the wire (frames the guest sends on tap A: tcpdump -Q in),
# sf0 gets nothing; lp->sf0 is not sent back out of the port it came in on
# (no hairpin): fails too. Deleted: lp->sf0 works again.
swcase() {
    local L=static-wrong W
    br_create
    static_add sf0 $U
    check "$L fdb sf0 on the uplink $U" "$(fdb sf0)" "dev $U .*static"
    check "$L sf0->lp ping (sf0 talks on repr0)" "$(ping_from sf0 lp $N)" " ($N|$((N - 1))) received"
    check_fdb "$L moved by the bridge" sf0 10
    check "$L fdb sf0 still static" "$(fdb sf0)" "static"
    check "$L lp->sf0 ping" "$(ping_from lp sf0 $N)" " ($N|$((N - 1))) received"
    g "ip link del $BR" || true

    L=static-wrong-sticky
    br_create
    g "bridge fdb add ${MAC[sf0]} dev $U master static sticky" || true
    check "$L fdb sf0 on the uplink $U" "$(fdb sf0)" "dev $U .*sticky"
    gn ${NS[lp]} "ip neigh replace ${IP[sf0]} lladdr ${MAC[sf0]} dev $LOOP_DEV_B nud permanent" || true
    gn ${NS[sf1]} "ip neigh replace ${IP[sf0]} lladdr ${MAC[sf0]} dev \$(ls /sys/class/net | grep -v lo) nud permanent" || true
    hcap_start $(tap $A) "-Q in icmp and ether dst ${MAC[sf0]}"
    check "$L sf1->sf0 ping fails (sf0 pinned behind the uplink)" "$(ping_from sf1 sf0 10)" " 0 received"
    W=$(hcap_stop)
    check_ge "$L sf1->sf0 frames sent out of port $A to the wire (tap $(tap $A) in)" "$W" 9
    check "$L lp->sf0 ping fails (no hairpin to the uplink)" "$(ping_from lp sf0 10)" " 0 received"
    gn ${NS[sf1]} "ip neigh flush all" || true
    check "$L fdb sf0 still on the uplink" "$(fdb sf0)" "dev $U .*sticky"
    g "bridge fdb del ${MAC[sf0]} dev $U master" || true
    check_eq "$L sticky entry deleted" "$(fdb sf0 | grep -c sticky || true)" 0
    gn ${NS[lp]} "ip neigh del ${IP[sf0]} dev $LOOP_DEV_B" || true
    check "$L lp->sf0 ping after delete" "$(ping_from lp sf0 $N)" " ($N|$((N - 1))) received"
    # sf0 relearned only via the slow path; lp's offloaded entry hides sf0's replies (F8).
    echo "INFO $L after delete, fdb sf0: $(fdb sf0)"
    g "ip link del $BR" || true
}

# --- static-teardown: port leaves the bridge, bridge deleted ------------------------
# repr0 nomaster: sf0's static entry leaves the FDB and its hw flow goes (lp->sf0
# fails: no bridge path to sf0); back in the bridge: works. Bridge deleted with
# static entries: no FDB entries left, a new bridge starts clean (first packets
# on the slow path: no stale flows).
stcase() {
    local E L=static-teardown
    br_create
    for E in lp sf0 sf1; do static_add $E ${DEV[$E]}; check_fdb "$L" $E 10; done
    check "$L lp->sf0 ping" "$(ping_from lp sf0 $N)" " ($N|$((N - 1))) received"

    g "ip link set ${DEV[sf0]} nomaster" || true
    check_eq "$L fdb sf0 gone with its port" "$(fdb sf0 | grep -c . || true)" 0
    check "$L lp->sf0 ping fails (port out of the bridge, hw flow removed)" "$(ping_from lp sf0 10)" " 0 received"
    g "ip link set ${DEV[sf0]} master $BR" || true
    check "$L lp->sf0 ping, port back" "$(ping_from lp sf0 $N)" " ($N|$((N - 1))) received"
    # sf0 relearned only via the slow path; lp's offloaded entry hides sf0's replies (F8).
    echo "INFO $L port back, fdb sf0: $(fdb sf0)"

    g "ip link del $BR" || true
    check_eq "$L no offloaded fdb left after bridge delete" "$(g "bridge fdb show" | grep -ciE "^(${MAC[lp]}|${MAC[sf0]}|${MAC[sf1]}) .*offload" || true)" 0
    br_create
    slow_start
    check "$L new bridge lp->sf0 ping" "$(ping_from lp sf0 $N)" " ($N|$((N - 1))) received"
    slow_stop "$L new bridge" 0
    check_ge "$L new bridge icmp on slow path (no stale flows)" "$((SLOW_up + SLOW_r0 + SLOW_r1))" 1
    g "ip link del $BR" || true
}

# --- lp-sf0-warm: LP starts with a warm ARP cache, sf0 already known (F8) ----------
# sf0 is learned first (its ARP broadcast), LP already knows sf0's MAC (ARP cache),
# then LP pings sf0: its requests match sf0's offloaded flow and never reach the
# bridge, so LP must still be learned on the uplink (offload) and sf0's replies
# must not take the slow path.
wcase() {
    local L=lp-sf0-warm
    br_create
    gn ${NS[sf0]} "ping -n -c 1 -W 1 10.99.0.99" > /dev/null 2>&1 || true
    check_fdb "$L sf0 known first" sf0 10
    # LP may have sent something of its own (e.g. IPv6) already: forget it.
    if [ -n "$(fdb lp)" ]; then
        echo "INFO $L lp already learned ($(fdb lp)), deleted"
        g "bridge fdb del ${MAC[lp]} dev $U master" || true
    fi
    check_eq "$L lp not known yet" "$(fdb lp | grep -c . || true)" 0
    gn ${NS[lp]} "ip neigh replace ${IP[sf0]} lladdr ${MAC[sf0]} dev $LOOP_DEV_B nud reachable" || true
    slow_start
    check "$L ping" "$(ping_from lp sf0 $N)" " ($N|$((N - 1))) received"
    slow_stop "$L" 3
    echo "INFO $L fdb lp after the burst: $(fdb lp)"
    check_fdb "$L" lp 10
    check_eq "$L icmp on uplink after seq 3" "$SLOW_up" 0
    check_eq "$L icmp on representors after seq 3" "$((SLOW_r0 + SLOW_r1))" 0
    g "ip link del $BR" || true
}

# states <label>: INFO bridge port states + carrier of uplink, representors, SF netdevs.
states() {
    echo "INFO $1 ports: $(g "bridge link show master $BR" 2> /dev/null | grep -oE '^[0-9]+: \S+|state \S+' | paste -sd' ' | sed 's/[0-9]*: //g')"
    echo "INFO $1 carrier: uplink $(g "cat /sys/class/net/$U/carrier" 2> /dev/null || echo -) repr0 $(g "cat /sys/class/net/${DEV[sf0]}/carrier" 2> /dev/null || echo -) repr1 $(g "cat /sys/class/net/${DEV[sf1]}/carrier" 2> /dev/null || echo -) sf0 $(gn ${NS[sf0]} "cat /sys/class/net/${NDEV[sf0]}/carrier" 2> /dev/null || echo -) sf1 $(gn ${NS[sf1]} "cat /sys/class/net/${NDEV[sf1]}/carrier" 2> /dev/null || echo -)"
}

# learn <from> <to>: fresh ARP caches, from pings to: both learned + offloaded.
learn() {
    gn ${NS[$1]} "ip neigh flush all" || true
    on $2 "ip neigh flush all" || true
    check "$L $1->$2 ping (learn)" "$(ping_from $1 $2 $N)" " ($N|$((N - 1))) received"
    check_fdb "$L learned" $1 10
    check_fdb "$L learned" $2 10
}
# offloaded <from> <to>: a burst with 0 ICMP on the slow path.
offloaded() {
    slow_start
    check "$L $1->$2 ping" "$(ping_from $1 $2 $N)" " ($N|$((N - 1))) received"
    slow_stop "$L $1->$2" 0
    check_eq "$L $1->$2 icmp on slow path" "$((SLOW_up + SLOW_r0 + SLOW_r1))" 0
}

# --- mac-move: sf0's MAC moves from repr0 to the uplink and back ----------------
# The host takes sf0's MAC (its port on the cable = behind the uplink), sf0 is
# down. The bridge moves the entry on the host's first frame (ARP broadcast),
# the driver must move the flow: sf1's replies to that MAC reach the host, the
# entry is on the uplink, one entry, offloaded. Back: sf0 up, host MAC restored,
# sf0 talks: entry on repr0 again, offloaded.
mcase() {
    local L=mac-move HMAC=${MAC[host]} M0=${MAC[sf0]}
    br_create
    learn sf0 sf1
    gn ${NS[sf0]} "ip link set ${NDEV[sf0]} down" || true
    ip link set $LOOP_BR address $M0
    at_exit "ip link set $LOOP_BR address $HMAC 2> /dev/null; g \"ip -n ${NS[sf0]} link set ${NDEV[sf0]} up\" 2> /dev/null"
    MAC[host]=$M0
    ip neigh flush dev $LOOP_BR || true
    gn ${NS[sf1]} "ip neigh flush all" || true
    check "$L host (sf0's MAC) -> sf1 ping" "$(ping_from host sf1 $N)" " ($N|$((N - 1))) received"
    DEV[host]=$U
    check_fdb "$L moved to the uplink" host 10
    check_eq "$L one entry for the MAC" "$(fdb host | tr ';' '\n' | grep -c . || true)" 1
    offloaded host sf1

    ip link set $LOOP_BR address $HMAC
    MAC[host]=$HMAC
    gn ${NS[sf0]} "ip link set ${NDEV[sf0]} up" || true
    for S in $(seq 30); do
        [ "$(gn ${NS[sf0]} "cat /sys/class/net/${NDEV[sf0]}/carrier" 2> /dev/null)" = 1 ] && break
        sleep 1
    done
    gn ${NS[sf0]} "ip neigh flush all" || true
    gn ${NS[sf1]} "ip neigh flush all" || true
    check "$L sf0->sf1 ping (back)" "$(ping_from sf0 sf1 $N)" " ($N|$((N - 1))) received"
    check_fdb "$L back on repr0" sf0 10
    check_eq "$L one entry for the MAC (back)" "$(fdb sf0 | tr ';' '\n' | grep -c . || true)" 1
    offloaded sf0 sf1
    g "ip link del $BR" || true
}

# --- sf-del: an SF deleted while its representor is bridged ----------------------
# sf2 learned + offloaded, then devlink port del: its entry leaves the FDB, the
# bridge keeps the other ports, lp<->sf0 still offloaded.
sdcase() {
    local L=sf-del E=sf2 P R
    br_create
    sf_add $PCI 72 || return 0
    P=$SF_PORT
    R=$SF_REPR
    DEV[$E]=$R
    NDEV[$E]=$SF_DEV
    NS[$E]=kdev-$E
    IP[$E]=10.99.0.13
    g "ip netns add ${NS[$E]}; ip link set $SF_DEV netns ${NS[$E]}
       ip -n ${NS[$E]} addr add ${IP[$E]}/24 dev $SF_DEV
       ip -n ${NS[$E]} link set $SF_DEV up; ip -n ${NS[$E]} link set lo up
       ip link set $R up master $BR" || true
    at_exit "g \"ip netns del ${NS[$E]} 2> /dev/null\""
    MAC[$E]=$(gn ${NS[$E]} "cat /sys/class/net/$SF_DEV/address")
    learn $E lp
    g "devlink port function set $P state inactive; devlink port del $P" || true
    check_eq "$L $R gone" "$(g "ls /sys/class/net" | grep -cx "$R" || true)" 0
    check_eq "$L fdb $E gone" "$(g "bridge fdb show" | grep -ci "^${MAC[$E]} " || true)" 0
    check_eq "$L bridge ports left" "$(g "bridge link show master $BR" | grep -c 'state forwarding' || true)" 3
    learn lp sf0
    offloaded lp sf0
    g "ip netns del ${NS[$E]}" 2> /dev/null || true
    g "ip link del $BR" || true
}

# --- uplink <nomaster|down>: uplink leaves the bridge / goes down ----------------
# lp, sf0, sf1 learned. Uplink nomaster or down: lp's entry leaves the FDB,
# sf0<->sf1 still offloaded and not on the wire, lp->sf0 fails. Back: lp->sf0
# works, lp learned on the uplink + offloaded.
ucase() {
    local L=uplink W HOW=$1 E S
    br_create
    learn lp sf0
    learn sf1 sf0
    for HOW in $HOW; do
        L="uplink $HOW"
        if [ $HOW = nomaster ]; then
            g "ip link set $U nomaster" || true
        else
            g "ip link set $U down" || true
        fi
        states "$L"
        check_eq "$L fdb lp gone" "$(fdb lp | grep -c . || true)" 0
        hcap_start $(tap $A) icmp
        offloaded sf0 sf1
        W=$(hcap_stop)
        check_eq "$L sf0->sf1 icmp on host tap (switched in the card)" "$W" 0
        check "$L lp->sf0 ping fails" "$(ping_from lp sf0 10)" " 0 received"
        if [ $HOW = nomaster ]; then
            g "ip link set $U master $BR" || true
        else
            g "ip link set $U up" || true
            loop_wait_carrier 1 30
        fi
        states "$L back"
        check_eq "$L back, bridge ports forwarding" "$(g "bridge link show master $BR" | grep -c 'state forwarding' || true)" 3
        # F10: representors stay without carrier. Recovery try: bounce the SF
        # netdevs (re-enables the SF vports -> representor link up).
        if [ "$(g "cat /sys/class/net/${DEV[sf0]}/carrier" 2> /dev/null)" != 1 ]; then
            for E in sf0 sf1; do
                gn ${NS[$E]} "ip link set ${NDEV[$E]} down; ip link set ${NDEV[$E]} up" || true
            done
            for S in $(seq 30); do
                [ "$(g "bridge link show master $BR" | grep -c 'state forwarding' || true)" = 3 ] && break
                sleep 1
            done
            states "$L after SF netdev down/up"
            echo "INFO $L recovery by SF netdev down/up: $(g "bridge link show master $BR" | grep -c 'state forwarding' || true) of 3 ports forwarding"
        fi
        learn lp sf0
        offloaded lp sf0
    done
    g "ip link del $BR" || true
}

# --- repr-updown: representor down / up -------------------------------------------
# sf0 learned. repr0 down: sf0's entry leaves the FDB, the SF netdev loses carrier
# (link follows the representor), lp->sf0 fails. repr0 up: carrier back, works,
# sf0 learned on repr0 + offloaded.
rcase() {
    local L=repr-updown S
    br_create
    learn sf0 lp
    g "ip link set ${DEV[sf0]} down" || true
    states "$L down"
    check_eq "$L fdb sf0 gone" "$(fdb sf0 | grep -c . || true)" 0
    check_eq "$L sf0 carrier with repr0 down" "$(gn ${NS[sf0]} "cat /sys/class/net/${NDEV[sf0]}/carrier" 2> /dev/null || echo none)" 0
    check "$L lp->sf0 ping fails" "$(ping_from lp sf0 10)" " 0 received"
    g "ip link set ${DEV[sf0]} up" || true
    for S in $(seq 30); do
        [ "$(gn ${NS[sf0]} "cat /sys/class/net/${NDEV[sf0]}/carrier" 2> /dev/null)" = 1 ] && break
        sleep 1
    done
    states "$L up"
    check_eq "$L sf0 carrier with repr0 up" "$(gn ${NS[sf0]} "cat /sys/class/net/${NDEV[sf0]}/carrier" 2> /dev/null || echo none)" 1
    check_eq "$L back, bridge ports forwarding" "$(g "bridge link show master $BR" | grep -c 'state forwarding' || true)" 3
    learn sf0 lp
    offloaded sf0 lp
    g "ip link del $BR" || true
}

# --- bage: learned entries in use must not age out (F7) ---------------------------
# Continuous lp->sf0 traffic, bridge ageing time AGE s (guest time).
bage() {
    local AGE=${AGE:-3} M=200 T0 T1
    br_create $AGE
    slow_start
    T0=$(g "cat /proc/uptime" | cut -d' ' -f1)
    check "ageing $AGE s lp->sf0 $M pings" "$(ping_from lp sf0 $M)" " ($M|$((M - 1))|$((M - 2))) received"
    T1=$(g "cat /proc/uptime" | cut -d' ' -f1)
    slow_stop "ageing $AGE s" 3
    echo "INFO ageing $AGE s: traffic for $(awk -v a=$T0 -v b=$T1 'BEGIN { printf "%.1f", b - a }') s guest time"
    check_eq "ageing $AGE s icmp on slow path after seq 3 (entries in use must not age out)" "$((SLOW_up + SLOW_r0 + SLOW_r1))" 0
    g "ip link del $BR" || true
}

CASES=${*:2}
CASES=${CASES:-sf0-sf1 lp-sf0 sf0-lp lp-sf0@1 host-sf0 sf0-host static static-wrong static-teardown mac-move sf-del uplink repr-updown}
for C in $CASES; do
    case $C in
        age)    bage ;;
        static) scase ;;
        static-replace)  srcase ;;
        static-wrong)    swcase ;;
        static-teardown) stcase ;;
        lp-sf0-warm)     wcase ;;
        mac-move)        mcase ;;
        sf-del)          sdcase ;;
        uplink)          ucase nomaster ;;
        uplink-down)     ucase down ;;
        repr-updown)     rcase ;;
        *@*)    P=${C%@*}; bcase ${P%-*} ${P#*-} ${C#*@} ;;
        *)      bcase ${C%-*} ${C#*-} ;;
    esac
done

# Remove bridge, netns, SFs and the loopback now: their errors count in dmesg too.
lib_exit
check_dmesg "dmesg clean"
finish
