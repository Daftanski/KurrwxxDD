# Shared code for tests/*.sh (runs on the Simics host). Usage: . "$(dirname "$0")/../lib.sh"
# Rules: see misc/readme.txt "Rules".
set -eo pipefail
trap 'echo "ABORT. Error on line $LINENO (exit code $?)"' ERR

DEV=/root/SimicsWorkspace/development/kernel-dev
ALL_PORTS="0 1 2 3 4 5 6 7"
NAME=$(basename "$0" .sh)
FAILS=0
# Written by core/launch-simics.sh: TRUE = PFP (8 PFs), FALSE = PFD (1 PF).
PFP=$(cat $DEV/logs/pfp 2> /dev/null || echo FALSE)

# --- Ports -------------------------------------------------------------------
# Port P: guest netdev with MAC mac P = 192.168.P.101 <-> host cnic_tap_0_P = 192.168.P.200
# Guest netdev names do not follow the port order (PFP: eth1 = port 2): find them by MAC.
tap()      { echo cnic_tap_0_$1; }
guest_ip() { echo 192.168.$1.101; }
host_ip()  { echo 192.168.$1.200; }
if [ "$PFP" = TRUE ]; then
    mac() { echo 0a:00:00:0$1:03:1$1; }
else
    mac() { echo 0a:0$1:00:08:03:18; }
fi

# --- Guest access ------------------------------------------------------------
# eth0 of the guest is bridged to the lab LAN (sim_tap1 -> sim_br0), IP by DHCP,
# no lease log. Find it by its MAC ($i210_mac of the launch script): ping the
# all-nodes multicast, then take the IPv4/IPv6 neighbours with that MAC.
# Guest disk is fresh each boot: host key changes, root needs no password.
SSH_OPTS="-o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=10"
# One shared connection (a guest ssh login takes seconds); dies 15 s after the guest.
SSH_OPTS+=" -o ControlMaster=auto -o ControlPath=/tmp/kdev-ssh-%C -o ControlPersist=60 -o ServerAliveInterval=5 -o ServerAliveCountMax=3"
BRIDGE=sim_br0

# Host's own launch script: core/launch-simics.sh copies it with the MAC unchanged.
# Not core/vpc_launch_kernel_dev.simics: the git copy has another host's MAC.
guest_mac() {
    grep -oiP '^\s*\$i210_mac\s*=\s*"\K[0-9a-f:]+' /root/SimicsWorkspace/startup_scripts/vpc_launch.simics
}

# guest_find: set GUEST (ssh address) if the guest answers ssh; return 1 if not.
guest_find() {
    local MAC A
    MAC=$(guest_mac) || return 1
    ping6 -c 2 -W 2 -I $BRIDGE ff02::1 > /dev/null 2>&1 || true
    for A in $(ip -4 neigh show dev $BRIDGE | grep -i "lladdr $MAC" | cut -d' ' -f1) \
             $(ip -6 neigh show dev $BRIDGE | grep -i "lladdr $MAC" | grep '^fe80' | cut -d' ' -f1 | sed "s/\$/%$BRIDGE/"); do
        if timeout 20 ssh $SSH_OPTS root@$A true 2> /dev/null; then
            GUEST=$A
            return 0
        fi
    done
    return 1
}

# g <cmd>: run a command on the guest. Call guest_need first: GUEST set
# inside $(...) is lost, every g would search again.
g() {
    [ -n "$GUEST" ] || guest_find || { echo "guest not reachable (MAC $(guest_mac || true))" >&2; return 1; }
    ssh $SSH_OPTS root@$GUEST "$@"
}

# guest_need: find the guest or FAIL the test.
guest_need() {
    if ! guest_find; then
        echo "FAIL guest reachable (MAC $(guest_mac || true))"
        exit 1
    fi
    echo "INFO guest $GUEST"
}

# guest_dev <port>: guest netdev of port P (by MAC), empty if none.
guest_dev() {
    g "ip -o link" | grep -i "link/ether $(mac $1) " | awk -F': ' '{print $2}' | cut -d@ -f1 | head -1 || true
}

# --- Port setup for traffic --------------------------------------------------
# port_up <port>: guest netdev up + guest_ip, host tap host_ip, wait for carrier,
# then for the first ping reply (up to 60 s: the first up after boot is slow).
# Saves state; port_down restores it.
# Return 1 (FAIL printed) if the port has no netdev or it is in a bridge
# (someone's setup, e.g. set-multi.sh: never touched).
declare -A PORT_DEV PORT_WAS_UP PORT_MTU PORT_HOST_MTU
# Any exit (finish, ABORT, Ctrl-C) restores the ports still set up.
ports_restore() {
    local P
    for P in "${!PORT_DEV[@]}"; do port_down $P; done
    loop_down
}
trap ports_restore EXIT
port_up() {
    local P=$1 D M
    D=$(guest_dev $P)
    if [ -z "$D" ]; then
        echo "FAIL port $P netdev (no netdev with MAC $(mac $P))"
        FAILS=$((FAILS + 1))
        return 1
    fi
    M=$(g "ip -o link show dev $D" | grep -oP ' master \K\S+' || true)
    if [ -n "$M" ]; then
        echo "FAIL port $P free ($D is in $M, not touched)"
        FAILS=$((FAILS + 1))
        return 1
    fi
    PORT_DEV[$P]=$D
    PORT_WAS_UP[$P]=$(g "ip -o link show dev $D" | grep -c '[<,]UP[,>]' || true)
    PORT_MTU[$P]=$(g "cat /sys/class/net/$D/mtu")
    PORT_HOST_MTU[$P]=$(cat /sys/class/net/$(tap $P)/mtu)
    ip addr replace $(host_ip $P)/24 dev $(tap $P)
    ip link set $(tap $P) up
    g "ip link set $D up && ip addr replace $(guest_ip $P)/24 dev $D" || true
    port_wait_carrier $P 1 30
    check_eq "port $P link ($D)" "$(port_carrier $P)" 1
    local T=$SECONDS
    until [[ $(guest_ping $P 1) == *" 1 received"* ]]; do
        [ $((SECONDS - T)) -lt 60 ] || break
    done
    check "port $P first traffic" "$((SECONDS - T)) s" "^([0-9]|[1-5][0-9]) s$"
}

# port_down <port>: undo port_up (address, MTU, link state; host tap too).
port_down() {
    local P=$1 D=${PORT_DEV[$1]}
    [ -n "$D" ] || return 0
    unset "PORT_DEV[$P]"
    g "ip addr del $(guest_ip $P)/24 dev $D 2> /dev/null; ip link set $D mtu ${PORT_MTU[$P]}" || true
    [ "${PORT_WAS_UP[$P]}" = 1 ] || g "ip link set $D down" || true
    ip addr del $(host_ip $P)/24 dev $(tap $P) 2> /dev/null || true
    ip link set $(tap $P) mtu ${PORT_HOST_MTU[$P]} || true
}

# port_carrier <port>: 1, 0, or none (link down: carrier unreadable).
port_carrier() {
    g "cat /sys/class/net/${PORT_DEV[$1]}/carrier 2> /dev/null" || echo none
}

# port_wait_carrier <port> <want> <seconds>
port_wait_carrier() {
    local I
    for I in $(seq $3); do
        [ "$(port_carrier $1)" = "$2" ] && return 0
        sleep 1
    done
    return 0
}

# guest_ping / host_ping <port> <count> [ping args]: the "packets transmitted" line.
# -n: no reverse DNS. Guest: Simics virtual time runs ~30x slower than wall time
# here, a 1 s ping interval costs ~30 s: short interval and wait on the guest.
guest_ping() {
    g "ping -n -c $2 -i 0.05 -W 1 -I ${PORT_DEV[$1]} ${*:3} $(host_ip $1)" 2>&1 | grep transmitted || true
}
host_ping() {
    ping -n -c $2 -W 3 -I $(tap $1) "${@:3}" $(guest_ip $1) 2>&1 | grep transmitted || true
}

# --- Loopback: two guest ports wired together on the host ---------------------
# Host: bridge LOOP_BR with cnic_tap_0_A + cnic_tap_0_B = a cable A <-> B.
# Guest: port B's netdev in netns LOOP_NS (else the kernel short-cuts traffic
# between two local addresses); A = LOOP_IP_A (init ns), B = LOOP_IP_B (LOOP_NS).
# Like kernel selftests: local side + remote side in a netns.
LOOP_BR=kdev-loop
LOOP_NS=kdev-peer
LOOP_IP_A=10.99.0.1
LOOP_IP_B=10.99.0.2
LOOP_A=""
LOOP_B=""
LOOP_DEV_A=""
LOOP_DEV_B=""

# gb <cmd>: run a command on the guest inside LOOP_NS (port B side).
gb() {
    g "ip netns exec $LOOP_NS sh -c '$*'"
}

# loop_up <portA> <portB>: set up the loopback; return 1 (FAIL printed) if not possible.
loop_up() {
    local P D M
    for P in $1 $2; do
        D=$(guest_dev $P)
        M=$( [ -n "$D" ] && g "ip -o link show dev $D" | grep -oP ' master \K\S+' || true)
        if [ -z "$D" ] || [ -n "$M" ]; then
            echo "FAIL loop port $P free (netdev '${D:-none}', master '${M:-none}')"
            FAILS=$((FAILS + 1))
            return 1
        fi
        M=$(ip -o link show dev $(tap $P) | grep -oP ' master \K\S+' || true)
        if [ -n "$M" ] && [ "$M" != $LOOP_BR ]; then
            echo "FAIL loop tap $(tap $P) free (in $M, not touched)"
            FAILS=$((FAILS + 1))
            return 1
        fi
    done
    LOOP_A=$1
    LOOP_B=$2
    LOOP_DEV_A=$(guest_dev $1)
    LOOP_DEV_B=$(guest_dev $2)

    # Host cable. No STP, no forward delay: forwards at once.
    ip link show $LOOP_BR > /dev/null 2>&1 || ip link add $LOOP_BR type bridge stp_state 0 forward_delay 0
    for P in $1 $2; do
        ip addr flush dev $(tap $P)
        ip link set $(tap $P) master $LOOP_BR
        ip link set $(tap $P) up
    done
    ip link set $LOOP_BR up

    # Guest: B into the netns.
    g "ip netns add $LOOP_NS 2> /dev/null; ip link set $LOOP_DEV_B netns $LOOP_NS
       ip addr replace $LOOP_IP_A/24 dev $LOOP_DEV_A; ip link set $LOOP_DEV_A up
       ip -n $LOOP_NS addr replace $LOOP_IP_B/24 dev $LOOP_DEV_B
       ip -n $LOOP_NS link set $LOOP_DEV_B up; ip -n $LOOP_NS link set lo up" || true

    local I
    for I in $(seq 30); do
        [ "$(g "cat /sys/class/net/$LOOP_DEV_A/carrier" 2> /dev/null)" = 1 ] &&
            [ "$(gb "cat /sys/class/net/$LOOP_DEV_B/carrier" 2> /dev/null)" = 1 ] && break
        sleep 1
    done
    check_eq "loop port $1 link ($LOOP_DEV_A)" "$(g "cat /sys/class/net/$LOOP_DEV_A/carrier" 2> /dev/null || echo none)" 1
    check_eq "loop port $2 link ($LOOP_DEV_B in $LOOP_NS)" "$(gb "cat /sys/class/net/$LOOP_DEV_B/carrier" 2> /dev/null || echo none)" 1
    # First traffic after link up can be slow (see port_up).
    local T=$SECONDS
    until [[ $(loop_ping_ab 1) == *" 1 received"* ]]; do
        [ $((SECONDS - T)) -lt 60 ] || break
    done
    check "loop first traffic" "$((SECONDS - T)) s" "^([0-9]|[1-5][0-9]) s$"
}

# loop_down: guest dev back to the init ns (addresses removed, down), netns gone,
# host taps out of the bridge, bridge gone.
loop_down() {
    [ -n "$LOOP_A" ] || return 0
    g "ip -n $LOOP_NS link set $LOOP_DEV_B netns 1 2> /dev/null; ip netns del $LOOP_NS 2> /dev/null
       ip addr del $LOOP_IP_A/24 dev $LOOP_DEV_A 2> /dev/null; ip addr flush dev $LOOP_DEV_B
       ip link set $LOOP_DEV_A down; ip link set $LOOP_DEV_B down" || true
    local P
    for P in $LOOP_A $LOOP_B; do ip link set $(tap $P) nomaster 2> /dev/null || true; done
    ip link del $LOOP_BR 2> /dev/null || true
    LOOP_A=""
}

# loop_ping_ab / loop_ping_ba <count> [ping args]: A -> B / B -> A, "transmitted" line.
loop_ping_ab() {
    g "ping -n -c $1 -i 0.05 -W 1 -I $LOOP_DEV_A ${*:2} $LOOP_IP_B" 2>&1 | grep transmitted || true
}
loop_ping_ba() {
    gb "ping -n -c $1 -i 0.05 -W 1 -I $LOOP_DEV_B ${*:2} $LOOP_IP_A" 2>&1 | grep transmitted || true
}

# tap_rx <port>: packets the guest sent out of port P (tap RX on the host).
tap_rx() {
    cat /sys/class/net/$(tap $1)/statistics/rx_packets
}

# --- dmesg -------------------------------------------------------------------
# Space before BUG/WARNING: not "EDAC DEBUG:".
DMESG_OOPS=' (BUG|WARNING): |Oops|Call Trace|general protection'
DMESG_IXD='ixd.*([Ee]rror|[Ff]ail|[Tt]imeout)'
# Inherited from a parent test (reload.sh runs ixd.sh): check from its mark.
DMESG_TAG=${DMESG_TAG:-}
# dmesg_mark: write a marker into the kernel log; check_dmesg looks only after it.
# (Not a line count: ixd fills the ring buffer, it wraps already at boot.)
dmesg_mark() {
    DMESG_TAG="kdev-mark-$NAME-$$-$RANDOM"
    g "echo $DMESG_TAG > /dev/kmsg"
}
# check_dmesg <label> [regex]: no line matches (default: oops or ixd error).
# Without dmesg_mark: whole dmesg. Marker wrapped out: whole buffer (all newer).
check_dmesg() {
    local BAD
    BAD=$(g "dmesg" | awk -v t="$DMESG_TAG" '
            t != "" && index($0, t) { n = 0; next }
            { a[++n] = $0 }
            END { for (i = 1; i <= n; i++) print a[i] }' |
          grep -E "${2:-$DMESG_OOPS|$DMESG_IXD}" | head -5 || true)
    check_eq "$1" "$(echo -n "$BAD" | grep -c . || true)" 0
    [ -z "$BAD" ] || echo "$BAD"
}

# --- Results -----------------------------------------------------------------
# check <label> <value> <regex>
check() {
    if [[ $2 =~ $3 ]]; then
        echo "PASS $1 ($2)"
    else
        echo "FAIL $1 ($2)"
        FAILS=$((FAILS + 1))
    fi
}

# check_eq <label> <got> <want>
check_eq() {
    if [ "$2" = "$3" ]; then
        echo "PASS $1 ($2)"
    else
        echo "FAIL $1 (got '$2', want '$3')"
        FAILS=$((FAILS + 1))
    fi
}

# check_ge <label> <number> <min>
check_ge() {
    if [ "${2:-x}" -ge "$3" ] 2> /dev/null; then
        echo "PASS $1 ($2 >= $3)"
    else
        echo "FAIL $1 (${2:-none} < $3)"
        FAILS=$((FAILS + 1))
    fi
}

finish() {
    exit $((FAILS > 0))
}
