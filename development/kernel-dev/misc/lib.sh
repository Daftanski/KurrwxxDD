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

finish() {
    exit $((FAILS > 0))
}
