#!/bin/bash
# Usage: unload.sh [cycles] [ports...]   Load, ping, unload; repeat. Needs: fresh boot.
. "$(dirname "$0")/../../lib.sh"
CYCLES=${1:-2}
shift || true
PORTS=${*:-$ALL_PORTS}

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
    uefi_unload
done
uefi_end

OUT=$(uefi_log)
for C in $(seq 1 $CYCLES); do
    R=$(log_part "$OUT" $C)
    for P in $PORTS; do
        check "cycle $C port $P" "$(ping_result "$R" $(host_ip $P))" " 2 received"
    done
    R=$(grep -a -m1 "Unload - Handle" <<< "$R" || true)
    check "cycle $C unload" "$R" "Success"
done

N=$(grep -a "SEM del" <<< "$OUT" | grep -vc Success || true)
check "SEM del" "failures=$N" "^failures=0\$"
finish
