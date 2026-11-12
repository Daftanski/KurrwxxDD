#!/bin/bash
# Usage: memfail.sh [pages left free]   Eat memory (nictest eatmem), connect the driver: no hang or crash, and after the memory is back everything works. Needs: driver loaded, nictest.efi.
. "$(dirname "$0")/../../lib.sh"
LEAVE=${1:-3000}
N=$(wc -w <<< "$ALL_PORTS")

for P in $ALL_PORTS; do
    host_setup $P
done

uefi_begin
uefi_handles
uefi_each_ctrl 'disconnect $c'
uefi_part eat
uefi_cmd "nictest.efi eatmem alloc $LEAVE" 'NICTEST done.*FS1:'
uefi_cmd "connect -r" 'FS1:'
uefi_tcl 'dh -d $h'
uefi_ifconfig 0
uefi_ping 0 2
uefi_cmd "nictest.efi eatmem free" 'NICTEST done.*FS1:'
uefi_part back
uefi_each_ctrl 'disconnect $c'
uefi_cmd "connect -r" 'FS1:'
uefi_tcl 'dh -d $h'
for P in $ALL_PORTS; do
    uefi_ifconfig $P
    uefi_ping $P 2
done
uefi_end

OUT=$(uefi_log)
R=$(log_part "$OUT" eat)
check "eatmem alloc" "$(grep -a -m1 "NICTEST eatmem alloc" <<< "$R" || true)" "status=Success"
echo "INFO children while starved: $(child_handles "$R" | wc -l) of $N"
echo "INFO port 0 while starved: $(ping_result "$R" $(host_ip 0))"
check "eatmem free" "$(grep -a -m1 "NICTEST eatmem free" <<< "$R" || true)" "failed=0"
R=$(log_part "$OUT" back)
check_eq "children after memory is back" "$(child_handles "$R" | wc -l)" $N
for P in $ALL_PORTS; do
    check "port $P" "$(ping_result "$R" $(host_ip $P))" " 2 received"
done
finish
