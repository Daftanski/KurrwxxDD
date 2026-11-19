#!/bin/bash
# Usage: mcast.sh [ports...]   Host pings UEFI IPv6 link-local. Needs: driver loaded.
# NS goes to solicited-node mcast 33:33:ff:<last 3 MAC bytes>; UEFI gets it only if the mcast filter works.
# Link-local address is EUI-64 of mac() (lib.sh).
. "$(dirname "$0")/../../lib.sh"
PORTS=${*:-$ALL_PORTS}

for P in $PORTS; do
    TAP=$(tap $P)
    IFS=: read -r M0 M1 M2 M3 M4 M5 <<< "$(mac $P | tr A-F a-f)"
    LL=$(printf "fe80::%x:%x:%x:%x" $(( (0x$M0 ^ 2) << 8 | 0x$M1 )) $(( 0x$M2 << 8 | 0xff )) $(( 0xfe00 | 0x$M3 )) $(( 0x$M4 << 8 | 0x$M5 )))
    ip -6 addr replace fe80::c8:$P/64 dev $TAP nodad
    ip -6 neigh flush dev $TAP
    timeout 15 tcpdump -l -eni $TAP icmp6 > /tmp/mcast-$P.txt 2> /dev/null &
    sleep 1
    R=$(ping -6 -c 3 -W 3 $LL%$TAP 2>&1 | grep "packets transmitted" || true)
    sleep 1
    pkill -f "tcpdump -l -eni $TAP" || true
    NS=$(grep -c "33:33:ff:$M3:$M4:$M5.*neighbor solicitation" /tmp/mcast-$P.txt || true)
    NA=$(grep -c "neighbor advertisement" /tmp/mcast-$P.txt || true)
    check "port $P" "$R; NS to mcast: $NS, NA from UEFI: $NA" " 3 received"
done
finish
