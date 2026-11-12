#!/bin/bash
# Usage: child.sh [port]   Disconnect one child only: the other ports keep working, connect -r gives it back. Needs: driver loaded.
. "$(dirname "$0")/../../lib.sh"
P=${1:-3}
OTHERS=$(sed "s/\b$P\b//" <<< "$ALL_PORTS")

for Q in $ALL_PORTS; do
    host_setup $Q
done

uefi_begin
uefi_handles
# Tcl vars k = child handle of port P (its dh -d line has the MAC), c = its controller (PFP: one per port).
SCRIPT+=' set pc $c; foreach l [split $out "\n"] { regexp {Ctrl\[(?:\x1b\[[0-9;]*m)*([0-9A-Fa-f]+)} $l -> pc; if {[regexp {Child\[(?:\x1b\[[0-9;]*m)*([0-9A-Fa-f]+).*'$(mac_hex $P)'} $l -> k]} { set c $pc; break } };'
uefi_part off
uefi_tcl 'disconnect $c $h $k'
uefi_tcl 'dh -d $h'
for Q in $OTHERS; do
    uefi_ifconfig $Q
    uefi_ping $Q 2
done
uefi_part on
uefi_cmd "connect -r"
uefi_tcl 'dh -d $h'
for Q in $ALL_PORTS; do
    uefi_ifconfig $Q
    uefi_ping $Q 2
done
uefi_part END
uefi_end

OUT=$(uefi_log)
R=$(log_part "$OUT" off)
check "disconnect child" "$(grep -a -m1 "Disconnect" <<< "$R" || true)" "Success"
check_eq "children after disconnect" "$(child_handles "$R" | wc -l)" "$(($(wc -w <<< "$ALL_PORTS") - 1))"
check_eq "port $P gone" "$(grep -ac "Child\[.*$(mac_hex $P)" <<< "$R" || true)" 0
for Q in $OTHERS; do
    check "off: port $Q" "$(ping_result "$R" $(host_ip $Q))" " 2 received"
done
R=$(log_part "$OUT" on)
check_eq "children after connect" "$(child_handles "$R" | wc -l)" "$(wc -w <<< "$ALL_PORTS")"
check_eq "port $P back" "$(grep -ac "Child\[.*$(mac_hex $P)" <<< "$R" || true)" 1
for Q in $ALL_PORTS; do
    check "on: port $Q" "$(ping_result "$R" $(host_ip $Q))" " 2 received"
done
finish
