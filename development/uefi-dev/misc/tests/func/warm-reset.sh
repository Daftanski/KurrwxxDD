#!/bin/bash
# Usage: warm-reset.sh [cycles]   reset -w in the Shell: after each boot the driver loads and ports 0 and 7 ping. Needs: driver not loaded (fresh boot).
. "$(dirname "$0")/../../lib.sh"
CYCLES=${1:-10}
PORTS="0 7"

for P in $PORTS; do
    host_setup $P
done

uefi_begin
for C in $(seq 1 $CYCLES); do
    uefi_part $C
    uefi_load
    for P in $PORTS; do
        uefi_ifconfig $P
        uefi_ping $P 2
    done
    uefi_cmd "reset -w" 'Shell>'
    uefi_cmd "fs1:" 'FS1:'
done
uefi_part END
uefi_end

OUT=$(uefi_log)
for C in $(seq 1 $CYCLES); do
    R=$(log_part "$OUT" $C)
    check "cycle $C load" "$(grep -a -m1 "^Image " <<< "$R" || true)" "Success"
    for P in $PORTS; do
        check "cycle $C port $P" "$(ping_result "$R" $(host_ip $P))" " 2 received"
    done
done
finish
