#!/bin/bash
# Usage: connect1.sh   Disconnect all controllers, connect ONLY the first one to our driver, check its children; then connect -r and ping. Needs: driver loaded.
. "$(dirname "$0")/../../lib.sh"

for P in $ALL_PORTS; do
    host_setup $P
done

uefi_begin
uefi_handles
uefi_part before
uefi_tcl 'dh -d $h'
uefi_part off
uefi_each_ctrl 'disconnect $c'
uefi_tcl 'dh -d $h'
uefi_part one
# uefi_each_ctrl leaves $c = last ctrl; PF K first breaks Rx on PF<K-1 (CP FW, known issue B5).
uefi_tcl 'connect [lindex $ctrls 0] $h'
uefi_tcl 'dh -d $h'
uefi_part all
uefi_cmd "connect -r"
uefi_tcl 'dh -d $h'
for P in $ALL_PORTS; do
    uefi_ifconfig $P
    uefi_ping $P 2
done
uefi_part END
uefi_end

OUT=$(uefi_log)
R=$(log_part "$OUT" before)
NCTRL=$(grep -ac "Ctrl\[" <<< "$R" || true)
NPORT=$(wc -w <<< "$ALL_PORTS")
check "controllers before" "$NCTRL" "^[1-9]"
check_eq "children off" "$(child_handles "$(log_part "$OUT" off)" | wc -l)" 0
R=$(log_part "$OUT" one)
check_eq "controllers after connect one" "$(grep -ac "Ctrl\[" <<< "$R" || true)" 1
check_eq "children after connect one" "$(child_handles "$R" | wc -l)" $((NPORT / NCTRL))
R=$(log_part "$OUT" all)
check_eq "controllers after connect -r" "$(grep -ac "Ctrl\[" <<< "$R" || true)" "$NCTRL"
check_eq "children after connect -r" "$(child_handles "$R" | wc -l)" "$NPORT"
for P in $ALL_PORTS; do
    check "port $P" "$(ping_result "$R" $(host_ip $P))" " 2 received"
done
finish
