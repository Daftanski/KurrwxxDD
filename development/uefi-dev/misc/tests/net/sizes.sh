#!/bin/bash
# Usage: sizes.sh [ports...]   Ping size sweep both ways (min, odd, Ethernet edges, fragments). Needs: ping.sh done.
. "$(dirname "$0")/../../lib.sh"
PORTS=${*:-0}
# Host side: payload 0 = 28 byte IP packet (padded frame), 1472 = full 1500 MTU, 1473 = first fragment case.
HOST_SIZES="0 1 18 46 1472 1473 8972 30000"
# UEFI Shell ping: -l is 16..32768 (EDK2 ShellNetwork1CommandsLib).
UEFI_SIZES="16 18 46 1472 1473 8972 30000"

uefi_begin
for P in $PORTS; do
    for S in $HOST_SIZES; do
        check "port $P host->uefi $S" "$(host_ping $P $(uefi_ip $P) 2 -s $S)" " 2 received"
    done
    for S in $UEFI_SIZES; do
        uefi_cmd "ping -n 2 -l $S -s $(uefi_ip $P) $(host_ip $P)" 'packets transmitted.*FS1:'
    done
done
uefi_end

OUT=$(uefi_log)
for P in $PORTS; do
    for S in $UEFI_SIZES; do
        check "port $P uefi->host $S" "$(ping_result "$OUT" "$(host_ip $P) $S data")" " 2 received"
    done
done
finish
