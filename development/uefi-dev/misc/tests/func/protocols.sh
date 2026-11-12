#!/bin/bash
# Usage: protocols.sh   Protocols on the driver image and on each child ("dh -v"). Needs: driver loaded.
. "$(dirname "$0")/../../lib.sh"
IMAGE="DriverBinding ComponentName ComponentName2 DriverDiagnostics DriverDiagnostics2 DriverHealth SupportedEfiSpecVersion LoadedImage ImageDevicePath"
CHILD="NetworkInterfaceIdentifier31 HIIConfigAccess AdapterInfo DevicePath"

uefi_begin
uefi_handles
uefi_part image
uefi_tcl 'dh -v $h'
uefi_part children
uefi_each_child 'dh -v $k'
uefi_part END
uefi_end

OUT=$(uefi_log)
R=$(log_part "$OUT" image)
for X in $IMAGE; do
    check_eq "image $X" "$(grep -ac "^$X(" <<< "$R" || true)" 1
done
check "image Unload" "$(grep -a -m1 "Unload\.*:" <<< "$R" || true)" "Unload\.+: 0*[1-9A-F]"

K=$(child_handles "$OUT" | wc -l)
check_eq "children" "$K" "$(wc -w <<< "$ALL_PORTS")"
R=$(log_part "$OUT" children)
for X in $CHILD; do
    check_eq "children with $X" "$(grep -ac "^$X(" <<< "$R" || true)" $K
done
check_eq "children MediaState Success" "$(grep -ac "MediaState: .* - Success" <<< "$R" || true)" $K
check_eq "children UNDI IPv6" "$(grep -ac "UNDI IPv6 Supported: 1" <<< "$R" || true)" $K
# One FMP per adapter, on the first child.
check_eq "children with FirmwareManagement" "$(grep -ac "^FirmwareManagement(" <<< "$R" || true)" 1
finish
