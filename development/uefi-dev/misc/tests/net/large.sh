#!/bin/bash
# Usage: large.sh [ports...]   Big pings (IP fragments) both ways. Needs: ping.sh done.
. "$(dirname "$0")/../../lib.sh"
PORTS=${*:-0 7}
SIZES="1472 4000 8000"

uefi_begin
for P in $PORTS; do
    for S in $SIZES; do
        check "port $P host->uefi $S" "$(host_ping $P $(uefi_ip $P) 2 -s $S)" " 2 received"
        uefi_cmd "ping -n 2 -l $S -s $(uefi_ip $P) $(host_ip $P)" 'packets transmitted.*FS1:'
    done
done
uefi_end

OUT=$(uefi_log)
for P in $PORTS; do
    for S in $SIZES; do
        check "port $P uefi->host $S" "$(ping_result "$OUT" "$(host_ip $P) $S data")" " 2 received"
    done
done
finish
