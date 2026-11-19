#!/bin/bash
# Usage: load.sh   Load the driver: Success, in "drivers", one child per port with its MAC. Needs: fresh boot.
. "$(dirname "$0")/../../lib.sh"

uefi_begin
uefi_load
uefi_cmd "drivers"
uefi_handles
uefi_end

OUT=$(uefi_log)
R=$(grep -a -m1 "^Image .*$DRIVER" <<< "$OUT" || true)
check "load" "$R" "Success"
check "drivers" "$(driver_line "$OUT")" "Intel\(R\) CNIC Driver"
check_eq "children" "$(child_handles "$OUT" | wc -l)" "$(wc -w <<< "$ALL_PORTS")"
for P in $ALL_PORTS; do
    N=$(grep -ac "Child\[.*/MAC($(mac_hex $P),0x1)" <<< "$OUT" || true)
    check_eq "port $P child MAC" "$N" 1
done
finish
