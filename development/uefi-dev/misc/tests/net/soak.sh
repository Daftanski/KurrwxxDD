#!/bin/bash
# Usage: soak.sh [seconds] [ports]   Host pings every port once a second while UEFI pings port 0 the same time; loss must stay under 0.1 %. Needs: fresh boot, driver loaded.
. "$(dirname "$0")/../../lib.sh"
D=${1:-600}
shift || true
PORTS=${*:-$ALL_PORTS}
MAXLOST=$((D / 1000 + 2))

for P in $PORTS; do
    host_setup $P
done

uefi_begin
for P in $PORTS; do
    uefi_ifconfig $P
done
uefi_end

for P in $PORTS; do
    ping -c $D -i 1 -W 1 -I $(tap $P) $(uefi_ip $P) > /tmp/$NAME-$P.txt 2>&1 &
done

uefi_begin
SCRIPT+=" set timeout $((D + 120));"
uefi_cmd "ping -n $D -s $(uefi_ip 0) $(host_ip 0)" "packets transmitted.*FS1:"
uefi_end
OUT=$(uefi_log)
wait

# lost <ping summary line>: sent - received.
lost() {
    local TX RX
    TX=$(sed -n 's/^\([0-9]*\) packets transmitted.*/\1/p' <<< "$1")
    RX=$(sed -n 's/.* \([0-9]*\) received.*/\1/p' <<< "$1")
    echo $((${TX:-0} - ${RX:-0}))
}
for P in $PORTS; do
    check_le "port $P host->uefi lost of $D" "$(lost "$(grep -a transmitted /tmp/$NAME-$P.txt || true)")" $MAXLOST
done
check_le "port 0 uefi->host lost of $D" "$(lost "$(ping_result "$OUT" $(host_ip 0))")" $MAXLOST
finish
