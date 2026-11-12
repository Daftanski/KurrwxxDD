#!/bin/bash
# Usage: connect-rdp.sh   ConnectController with a remaining device path (one MAC node): only that child starts; a 2nd one adds a 2nd child; connect -r brings the rest. Ports in ascending order (other orders: CP FW bug B5, Rx dead). PFD only (PFP has one child per controller). Needs: driver loaded, nictest.efi.
. "$(dirname "$0")/../../lib.sh"
if [ "$(cat $DEV/logs/pfp 2> /dev/null)" = TRUE ]; then
    echo "INFO skipped: PFP has one child per controller"
    exit 0
fi
A=0
B=1
N=$(wc -w <<< "$ALL_PORTS")

for P in $ALL_PORTS; do
    host_setup $P
done

uefi_begin
uefi_handles
uefi_tcl 'disconnect $c $h'
uefi_part a
uefi_tcl "nictest.efi connectrdp $(mac_hex $A)"
uefi_tcl 'dh -d $h'
uefi_part b
uefi_tcl "nictest.efi connectrdp $(mac_hex $B)"
uefi_tcl 'dh -d $h'
uefi_part again
uefi_tcl "nictest.efi connectrdp $(mac_hex $B)"
uefi_tcl 'dh -d $h'
uefi_part c
uefi_cmd "connect -r"
uefi_tcl 'dh -d $h'
for P in $ALL_PORTS; do
    uefi_ifconfig $P
    uefi_ping $P 2
done
uefi_end

OUT=$(uefi_log)
R=$(log_part "$OUT" a)
check "connect port $A only" "$(grep -a "NICTEST connectrdp" <<< "$R" || true)" "status=Success"
check_eq "children after 1st" "$(child_handles "$R" | wc -l)" 1
check_eq "port $A is the child" "$(grep -ac "Child\[.*$(mac_hex $A)" <<< "$R" || true)" 1
R=$(log_part "$OUT" b)
check "connect port $B" "$(grep -a "NICTEST connectrdp" <<< "$R" || true)" "status=Success"
check_eq "children after 2nd" "$(child_handles "$R" | wc -l)" 2
R=$(log_part "$OUT" again)
check_eq "same child again: still 2" "$(child_handles "$R" | wc -l)" 2
R=$(log_part "$OUT" c)
check_eq "children after connect -r" "$(child_handles "$R" | wc -l)" $N
for P in $ALL_PORTS; do
    check "port $P" "$(ping_result "$R" $(host_ip $P))" " 2 received"
done
finish
