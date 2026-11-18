#!/bin/bash
# Usage: ping.sh [ports...]   Guest and host ping each other on each port (guest netdev by MAC <-> host cnic_tap_0_P), then remove the addresses again. Needs: ixd.sh done, ports not in a bridge.
. "$(dirname "$0")/../lib.sh"
PORTS=${*:-$ALL_PORTS}
guest_need

for P in $PORTS; do
    D=$(guest_dev $P)
    if [ -z "$D" ]; then
        echo "FAIL port $P netdev (no netdev with MAC $(mac $P))"
        FAILS=$((FAILS + 1))
        continue
    fi
    MASTER=$(g "ip -o link show dev $D" | grep -oP ' master \K\S+' || true)
    if [ -n "$MASTER" ]; then
        echo "FAIL port $P free ($D is in $MASTER, not touched)"
        FAILS=$((FAILS + 1))
        continue
    fi
    WAS_UP=$(g "ip -o link show dev $D" | grep -c '[<,]UP[,>]' || true)

    ip addr replace $(host_ip $P)/24 dev $(tap $P)
    ip link set $(tap $P) up
    g "ip link set $D up && ip addr replace $(guest_ip $P)/24 dev $D" || true

    # Link up takes a few seconds in Simics.
    for I in $(seq 30); do
        [ "$(g "cat /sys/class/net/$D/carrier" 2> /dev/null || true)" = 1 ] && break
        sleep 1
    done
    check_eq "port $P link ($D)" "$(g "cat /sys/class/net/$D/carrier" 2> /dev/null || echo none)" 1

    # First packet may be lost to ARP: 5 sent, at least 3 back.
    OUT=$(g "ping -c 5 -W 3 -I $D $(host_ip $P)" 2>&1 | grep transmitted || true)
    check "port $P guest->host" "$OUT" " [345] received"
    OUT=$(ping -c 5 -W 3 -I $(tap $P) $(guest_ip $P) 2>&1 | grep transmitted || true)
    check "port $P host->guest" "$OUT" " [345] received"

    # Restore: rule 5 of readme.txt.
    g "ip addr del $(guest_ip $P)/24 dev $D" || true
    [ "$WAS_UP" = 1 ] || g "ip link set $D down" || true
    ip addr del $(host_ip $P)/24 dev $(tap $P) || true
done

finish
