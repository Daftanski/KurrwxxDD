#!/bin/bash
# Usage: bind.sh [cycles] [ports...]   Disconnect / connect the driver, then ping. Needs: driver loaded.
. "$(dirname "$0")/../../lib.sh"
CYCLES=${1:-2}
shift || true
PORTS=${*:-$ALL_PORTS}

for P in $PORTS; do
    host_setup $P
done

uefi_begin
uefi_handles
for C in $(seq 1 $CYCLES); do
    uefi_part $C
    uefi_each_ctrl 'disconnect $c'
    uefi_tcl 'dh -d $h'
    uefi_part $C-on
    uefi_cmd "connect -r"
    uefi_tcl 'dh -d $h'
    for P in $PORTS; do
        uefi_ifconfig $P
        uefi_ping $P 2
    done
done
uefi_part END
uefi_end

OUT=$(uefi_log)
for C in $(seq 1 $CYCLES); do
    R=$(log_part "$OUT" $C)
    check "cycle $C disconnect" "$(grep -a "Disconnect" <<< "$R" | grep -v Success || echo ok)" "^ok$"
    check_eq "cycle $C children off" "$(child_handles "$R" | wc -l)" 0
    R=$(log_part "$OUT" $C-on)
    check_eq "cycle $C children on" "$(child_handles "$R" | wc -l)" "$(wc -w <<< "$ALL_PORTS")"
    for P in $PORTS; do
        check "cycle $C port $P" "$(ping_result "$R" $(host_ip $P))" " 2 received"
    done
done
finish
