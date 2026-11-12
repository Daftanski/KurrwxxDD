#!/bin/bash
# Usage: port-isolation.sh [ports...]   Traffic of port P must be seen only on tap P. Needs: ping.sh done.
. "$(dirname "$0")/../../lib.sh"
PORTS=${*:-$ALL_PORTS}
CAP=/tmp/port-isolation
rm -rf $CAP
mkdir -p $CAP

for T in $ALL_PORTS; do
    timeout 600 tcpdump -l -eni $(tap $T) > $CAP/tap$T.txt 2> /dev/null &
done
sleep 2

uefi_begin
for P in $PORTS; do
    # Flush ARP so the host sends an ARP broadcast first.
    ip neigh flush dev $(tap $P)
    check "port $P host->uefi" "$(host_ping $P $(uefi_ip $P) 2)" " 2 received"
    uefi_ping $P 2
done
uefi_end

OUT=$(uefi_log)
for P in $PORTS; do
    check "port $P uefi->host" "$(ping_result "$OUT" $(host_ip $P))" " 2 received"
done

sleep 2
pkill -f "tcpdump -l -eni cnic_tap_0_" || true
sleep 1

for P in $PORTS; do
    SEEN=""
    for T in $ALL_PORTS; do
        [ "$(grep -c "192\.168\.$P\." $CAP/tap$T.txt || true)" = 0 ] || SEEN+=" $T"
    done
    check "port $P" "seen on taps:$SEEN" "^seen on taps: $P\$"
done
echo "Raw captures: $CAP/tap<N>.txt"
finish
