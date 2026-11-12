#!/bin/bash
# Usage: diag.sh [ports...]   drvdiag standard / extended / manufacturing, then ping. Needs: driver loaded.
. "$(dirname "$0")/../../lib.sh"
PORTS=${*:-0 7}

uefi_begin
uefi_handles
for M in s e m; do
    uefi_part $M
    uefi_tcl "drvdiag -$M \$h \$c"
done
uefi_part ping
for P in $PORTS; do
    host_setup $P
    uefi_ifconfig $P
    uefi_ping $P 2
done
uefi_part END
uefi_end

OUT=$(uefi_log)
# Manufacturing mode is optional in the spec; the driver returns Unsupported (RunDiagnostics.c).
# Extended: loopback PCDs are 0 in CnicPkg.dsc until HW loopback works (known issue D7).
for M in s e m; do
    WANT=Success
    [ $M != s ] && WANT=Unsupported
    R=$(grep -a "DrvDiag - " <<< "$(log_part "$OUT" $M)" | tr '\n' ' ' || true)
    check "drvdiag -$M" "$R" "^(DrvDiag - [^ ]+ Result $WANT\. )+\$"
done
for P in $PORTS; do
    check "port $P after diag" "$(ping_result "$OUT" $(host_ip $P))" " 2 received"
done
finish
