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
# Port P: guest netdev with MAC mac P <-> host cnic_tap_0_P.
# Guest netdev names do not follow the port order (PFP: eth1 = port 2): find them by MAC.
# PFP: port P = PF P. Traffic always between two guest ports (loopback, below).
tap() { echo cnic_tap_0_$1; }
if [ "$PFP" = TRUE ]; then
    mac() { echo 0a:00:00:0$1:03:1$1; }
else
    mac() { echo 0a:0$1:00:08:03:18; }
fi
# All 8 ports as loopback pairs (A:B).
ALL_PAIRS="0:1 2:3 4:5 6:7"

# --- Guest access ------------------------------------------------------------
# eth0 of the guest is bridged to the lab LAN (sim_tap1 -> sim_br0), IP by DHCP,
# no lease log. Find it by its MAC ($i210_mac of the launch script): ping the
# all-nodes multicast, then take the IPv4/IPv6 neighbours with that MAC.
# Guest disk is fresh each boot: host key changes, root needs no password.
SSH_OPTS="-o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=10"
SSH_OPTS+=" -o ServerAliveInterval=5 -o ServerAliveCountMax=3"
# One shared connection (a guest ssh login takes seconds), started only by
# guest_find, outside $(...): a master made inside $(...) keeps its pipe open
# (ssh daemonizes with the fds), so the call would hang. Calls never become the
# master; without it they connect directly.
SSH_MUX="-o ControlPath=/tmp/kdev-ssh-%C"
SSH_OPTS+=" $SSH_MUX -o ControlMaster=no"
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
            ssh $SSH_MUX -O check root@$A > /dev/null 2>&1 ||
                ssh ${SSH_OPTS% -o ControlMaster=no} -o ControlMaster=yes -o ControlPersist=120 -fN root@$A \
                    < /dev/null > /dev/null 2>&1 || true
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

# gt <seconds> <cmd>: g with a wall-clock limit (exit 124 on timeout). Own
# connection: via the shared one the master keeps our stdout until the guest
# command ends (minutes on a hung guest). First -o value wins in ssh.
gt() {
    [ -n "$GUEST" ] || guest_find || return 1
    timeout $1 ssh -o ControlPath=none $SSH_OPTS root@$GUEST "${@:2}"
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

# --- Loopback: the traffic setup of all tests -------------------------------
# Two guest ports wired back to back, like kernel selftests (local + remote in a netns):
#   host:  bridge LOOP_BR with cnic_tap_0_A + cnic_tap_0_B = a cable A <-> B
#   guest: A = LOOP_DEV_A, LOOP_IP_A in the init ns  -> run with g  "<cmd>"
#          B = LOOP_DEV_B, LOOP_IP_B in netns LOOP_NS -> run with gb "<cmd>"
#          (B in a netns: else the kernel short-cuts traffic between two local addresses)
# loop_up A B ... loop_down. One loopback at a time; restored on any exit.
LOOP_BR=kdev-loop
LOOP_NS=kdev-peer
LOOP_IP_A=10.99.0.1
LOOP_IP_B=10.99.0.2
LOOP_A=""
LOOP_B=""
LOOP_DEV_A=""
LOOP_DEV_B=""
declare -A LOOP_SAVE

# at_exit "<cmd>": run <cmd> on any exit (newest first), before loop_down.
# Tests never set their own trap EXIT.
EXIT_HOOKS=()
at_exit() {
    EXIT_HOOKS=("$*" "${EXIT_HOOKS[@]}")
}
lib_exit() {
    local C
    for C in "${EXIT_HOOKS[@]}"; do eval "$C" || true; done
    EXIT_HOOKS=()
    loop_down
}
# Any exit (finish, ABORT, Ctrl-C) runs the hooks and restores the loopback.
trap lib_exit EXIT

# gb <cmd>: run a command on the guest inside LOOP_NS (port B side). No ' in <cmd>.
gb() {
    g "ip netns exec $LOOP_NS sh -c '$*'"
}

# pair_split <A:B> -> "A B" (default 0:1).
pair_split() {
    local P=${1:-0:1}
    echo "${P%%:*} ${P#*:}"
}

# loop_up <portA> <portB>: set up the loopback, wait for both links and the first
# reply (up to 60 s: the first up after boot is slow). Return 1 (FAIL printed) if
# a port or tap is in someone's bridge (e.g. set-multi.sh: never touched).
loop_up() {
    local P D M T
    loop_down
    for P in $1 $2; do
        D=$(guest_dev $P)
        M=$( [ -n "$D" ] && g "ip -o link show dev $D" | grep -oP ' master \K\S+' || true)
        if [ -z "$D" ] || [ -n "$M" ]; then
            echo "FAIL loop port $P free (netdev '${D:-none}', master '${M:-none}')"
            FAILS=$((FAILS + 1))
            return 1
        fi
        M=$(ip -o link show dev $(tap $P) | grep -oP ' master \K\S+' || true)
        if [ -n "$M" ]; then
            echo "FAIL loop tap $(tap $P) free (in $M, not touched)"
            FAILS=$((FAILS + 1))
            return 1
        fi
    done
    LOOP_A=$1
    LOOP_B=$2
    LOOP_DEV_A=$(guest_dev $1)
    LOOP_DEV_B=$(guest_dev $2)

    # Save what we change: guest MTU + up state, host tap MTU + IPv4 addresses.
    for P in A B; do
        D=LOOP_DEV_$P
        LOOP_SAVE[mtu$P]=$(g "cat /sys/class/net/${!D}/mtu")
        LOOP_SAVE[up$P]=$(g "ip -o link show dev ${!D}" | grep -c '[<,]UP[,>]' || true)
        T=$(tap $(eval echo \$LOOP_$P))
        LOOP_SAVE[tmtu$P]=$(cat /sys/class/net/$T/mtu)
        LOOP_SAVE[taddr$P]=$(ip -o -4 addr show dev $T | awk '{print $4}' | tr '\n' ' ')
    done

    # Host cable. No STP, no forward delay: forwards at once.
    ip link add $LOOP_BR type bridge stp_state 0 forward_delay 0
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

    loop_wait_carrier 1 30
    check_eq "loop port $1 link ($LOOP_DEV_A)" "$(loop_carrier a)" 1
    check_eq "loop port $2 link ($LOOP_DEV_B in $LOOP_NS)" "$(loop_carrier b)" 1
    loop_first_traffic
}

# loop_down: undo loop_up (guest dev B back to the init ns, addresses, MTU,
# link state; host taps out of the bridge, their MTU + addresses; bridge gone).
loop_down() {
    [ -n "$LOOP_A" ] || return 0
    local P T A
    g "ip -n $LOOP_NS link set $LOOP_DEV_B netns 1 2> /dev/null; ip netns del $LOOP_NS 2> /dev/null
       ip addr del $LOOP_IP_A/24 dev $LOOP_DEV_A 2> /dev/null; ip addr del $LOOP_IP_B/24 dev $LOOP_DEV_B 2> /dev/null
       ip link set $LOOP_DEV_A mtu ${LOOP_SAVE[mtuA]}; ip link set $LOOP_DEV_B mtu ${LOOP_SAVE[mtuB]}" || true
    [ "${LOOP_SAVE[upA]}" = 1 ] || g "ip link set $LOOP_DEV_A down" || true
    [ "${LOOP_SAVE[upB]}" = 1 ] || g "ip link set $LOOP_DEV_B down" || true
    for P in A B; do
        T=$(tap $(eval echo \$LOOP_$P))
        ip link set $T nomaster 2> /dev/null || true
        ip link set $T mtu ${LOOP_SAVE[tmtu$P]} 2> /dev/null || true
        for A in ${LOOP_SAVE[taddr$P]}; do ip addr add $A dev $T 2> /dev/null || true; done
    done
    ip link del $LOOP_BR 2> /dev/null || true
    LOOP_A=""
}

# loop_carrier <a|b>: 1, 0, or none (link down: carrier unreadable).
loop_carrier() {
    if [ $1 = a ]; then
        g "cat /sys/class/net/$LOOP_DEV_A/carrier 2> /dev/null" || echo none
    else
        gb "cat /sys/class/net/$LOOP_DEV_B/carrier 2> /dev/null" || echo none
    fi
}

# loop_wait_carrier <want> <seconds>: both sides.
loop_wait_carrier() {
    local I
    for I in $(seq $2); do
        [ "$(loop_carrier a)" = $1 ] && [ "$(loop_carrier b)" = $1 ] && return 0
        sleep 1
    done
    return 0
}

# loop_first_traffic: wait up to 60 s for one A -> B reply (also after a link or MTU change).
loop_first_traffic() {
    local T=$SECONDS
    # gt: a dead port must not stretch one try (slow guest time).
    until [[ $(gt 20 "ping -n -c 1 -W 1 -I $LOOP_DEV_A $LOOP_IP_B" 2>&1) == *" 1 received"* ]]; do
        [ $((SECONDS - T)) -lt 60 ] || break
    done
    check "loop first traffic" "$((SECONDS - T)) s" "^([0-9]|[1-5][0-9]) s$"
}

# loop_wait_dad [seconds]: wait until no IPv6 address on A or B is tentative
# (DAD ~1 s guest time = ~30 s wall; packets to a tentative address are dropped).
loop_wait_dad() {
    local I
    for I in $(seq ${1:-90}); do
        [ -z "$(g "ip -6 addr show dev $LOOP_DEV_A tentative")$(gb "ip -6 addr show dev $LOOP_DEV_B tentative")" ] && return 0
        sleep 1
    done
    return 0
}

# loop_mtu <mtu>: MTU on both guest netdevs and both host taps (the bridge follows).
# Prints the guest errors (if refused); loop_down restores.
loop_mtu() {
    ip link set $(tap $LOOP_A) mtu $1
    ip link set $(tap $LOOP_B) mtu $1
    g "ip link set $LOOP_DEV_A mtu $1; ip -n $LOOP_NS link set $LOOP_DEV_B mtu $1" 2>&1 || true
}

# loop_ping_ab / loop_ping_ba <count> [ping args]: A -> B / B -> A, "transmitted" line.
# -n: no reverse DNS. Simics guest time runs ~30x slower than wall time: a 1 s
# ping interval costs ~30 s, so short interval and wait.
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

# Guest packet capture on side A, no promiscuous mode (-p): counts what the
# device lets up to the stack. gcap_start <dev> <filter>; send; gcap_stop -> count.
# setsid + all fds redirected: the background tcpdump must not hold the ssh session.
gcap_start() {
    g "rm -f /tmp/kdev-cap.*
       setsid tcpdump -p -n -l -i $1 $2 < /dev/null > /tmp/kdev-cap.txt 2> /tmp/kdev-cap.err &
       echo \$! > /tmp/kdev-cap.pid
       for I in \$(seq 50); do grep -q listening /tmp/kdev-cap.err 2> /dev/null && break; sleep 0.1; done" || true
    at_exit 'g "kill \$(cat /tmp/kdev-cap.pid 2> /dev/null) 2> /dev/null"'
}
gcap_stop() {
    g "sleep 0.5; kill \$(cat /tmp/kdev-cap.pid); sleep 0.2; grep -c . /tmp/kdev-cap.txt || true" 2> /dev/null || true
}

# Host packet capture: hcap_start <tap> <filter>; send; hcap_stop -> count.
hcap_start() {
    tcpdump -l -n -i $1 $2 > /tmp/kdev-hcap.txt 2> /dev/null &
    HCAP_PID=$!
    at_exit "kill $HCAP_PID 2> /dev/null"
    sleep 2
}
hcap_stop() {
    sleep 1
    kill $HCAP_PID 2> /dev/null || true
    wait $HCAP_PID 2> /dev/null || true
    grep -c . /tmp/kdev-hcap.txt || true
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
