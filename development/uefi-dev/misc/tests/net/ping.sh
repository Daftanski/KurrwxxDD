#!/bin/bash
# Usage: ping.sh [ports...]   Load the driver; UEFI pings the host on each port. Needs: fresh boot.
. "$(dirname "$0")/../../lib.sh"
PORTS=${*:-$ALL_PORTS}

uefi_begin
uefi_load
for P in $PORTS; do
    host_setup $P
    uefi_ifconfig $P
    uefi_ping $P 4
done
uefi_end

OUT=$(uefi_log)
for P in $PORTS; do
    check "port $P" "$(ping_result "$OUT" $(host_ip $P))" " 4 received"
done
finish
