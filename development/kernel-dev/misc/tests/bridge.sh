#!/bin/bash
# Usage: bridge.sh [A:B] [case ...]   Bridge offload on port A's PF (switchdev): guest bridge = uplink A + representors of 2 SFs (SF netdevs in netns); LP = port B. Cases (default sf0-sf1 lp-sf0 sf0-lp lp-sf0@1 host-sf0 sf0-host static; age = F7 check): from-to[@ping interval], host = Simics host as LP, fresh bridge + ARP each: initiator's 1st burst per device/seq (no ICMP on uplink or representors after seq 3, ARP control), FDB entry of each MAC on its own port (LP on the uplink) + offload right after the burst and after a wait, 2nd burst 0 slow path, sf<->sf not on the host tap; static = entries added by hand (bridge fdb add ... static) offloaded before traffic, 0 slow path from seq 1, survive ageing, deleted cleanly; age = learned entries in use must not age out. Needs: ixd.sh done, eswitch switchdev, ports not in a bridge. Changes: driver (2 SFs added + removed), ports, host taps (restored). Time: ~2 min (+1 min age).
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
declare -A NS IP MAC DEV
NS[lp]=$LOOP_NS
IP[lp]=$LOOP_IP_B
MAC[lp]=$(gb "cat /sys/class/net/$LOOP_DEV_B/address")
DEV[lp]=$U
g "ip addr flush dev $U" || true
for I in 0 1; do
    E=sf$I
    sf_add $PCI $((70 + I)) || finish
    DEV[$E]=$SF_REPR
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
    local AG=""
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
        g "bridge fdb add ${MAC[$E]} dev ${DEV[$E]} master static" || true
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
    check "$L lp->sf0 ping after delete" "$(ping_from lp sf0 $N)" " ($N|$((N - 1))) received"
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
CASES=${CASES:-sf0-sf1 lp-sf0 sf0-lp lp-sf0@1 host-sf0 sf0-host static}
for C in $CASES; do
    case $C in
        age)    bage ;;
        static) scase ;;
        *@*)    P=${C%@*}; bcase ${P%-*} ${P#*-} ${C#*@} ;;
        *)      bcase ${C%-*} ${C#*-} ;;
    esac
done

# Remove bridge, netns, SFs and the loopback now: their errors count in dmesg too.
lib_exit
check_dmesg "dmesg clean"
finish
