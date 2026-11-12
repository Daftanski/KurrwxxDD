#!/bin/bash
# Usage: identity.sh   Driver version (hex vs name), controller name, name per language. Needs: driver loaded.
. "$(dirname "$0")/../../lib.sh"
LANGS="en-US fr-FR de-DE es-ES ja-JP zh-Hans"

uefi_begin
uefi_cmd "drivers"
uefi_handles
for L in $LANGS; do
    uefi_cmd "drivers -l $L"
done
uefi_end

OUT=$(uefi_log)
LINE=$(driver_line "$OUT")
DNAME=$(driver_name "$LINE")
check "name" "$DNAME" "^Intel\(R\) CNIC Driver [0-9]+\.[0-9]+\.[0-9]+\$"

# Hex = MAJOR<<24 | MINOR<<16 | BUILD/10<<12 | BUILD%10<<8 (DriverBindingInternal.h).
V=$(awk '{ print $2 }' <<< "$LINE")
D=$((16#${V:0:2})).$((16#${V:2:2})).$((16#${V:4:1} * 10 + 16#${V:5:1}))
check_eq "version $V" "$D" "$(grep -oE '[0-9]+\.[0-9]+\.[0-9]+$' <<< "$DNAME" || true)"

R=$(grep -a -m1 "Ctrl\[" <<< "$OUT" || true)
check "controller name" "$R" "Ctrl\[[0-9A-Fa-f]+\] +: Intel\(R\) Ethernet Connection"

for L in $LANGS; do
    check "name $L" "$(driver_name "$(driver_line "$OUT" "drivers -l $L")")" "CNIC"
done
finish
