#!/bin/bash
# Usage: hold.sh   A foreign app holds the NII of child 0 EXCLUSIVE while the driver is disconnected: a status comes back (no hang, no crash), then all 8 children and ports work again. Needs: driver loaded, nictest.efi.
. "$(dirname "$0")/../../lib.sh"
N=$(wc -w <<< "$ALL_PORTS")

for P in $ALL_PORTS; do
    host_setup $P
done

uefi_begin
uefi_handles
uefi_part hold
uefi_cmd "nictest.efi hold" 'NICTEST done.*FS1:'
uefi_part back
uefi_each_ctrl 'disconnect $c'
uefi_cmd "connect -r"
uefi_tcl 'dh -d $h'
for P in $ALL_PORTS; do
    uefi_ifconfig $P
    uefi_ping $P 2
done
uefi_end

OUT=$(uefi_log)
R=$(log_part "$OUT" hold)
check "foreign open exclusive" "$(grep -a "NICTEST hold open" <<< "$R" || true)" "status="
echo "INFO $(grep -a "NICTEST hold" <<< "$R" | tr '\n' ' ')"
check "disconnect returned" "$(grep -a "NICTEST hold disconnect status" <<< "$R" || true)" "status="
check "reconnect returned" "$(grep -a "NICTEST hold reconnect" <<< "$R" || true)" "status="
R=$(log_part "$OUT" back)
check_eq "children after recovery" "$(child_handles "$R" | wc -l)" $N
for P in $ALL_PORTS; do
    check "port $P" "$(ping_result "$R" $(host_ip $P))" " 2 received"
done
finish
