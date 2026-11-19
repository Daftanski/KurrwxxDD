#!/bin/bash
# Usage: memmap.sh   Count memory map entries before and after driver load and over time (D16 check). Needs: fresh boot, driver NOT loaded.
. "$(dirname "$0")/../../lib.sh"
uefi_begin
for N in 0 1 2; do uefi_part m$N; uefi_cmd "memmap -b" 'FS1:'; uefi_cmd "stall 2000000"; done
uefi_load
for N in 3 4 5 6; do uefi_part m$N; uefi_cmd "memmap -b" 'FS1:'; uefi_cmd "stall 2000000"; done
uefi_part end
uefi_end
OUT=$(uefi_log)
for N in 0 1 2 3 4 5 6; do
  P=$(log_part "$OUT" m$N)
  echo "m$N desc=$(grep -acE '^ *[A-Za-z]+ +[0-9A-F]{16}-' <<< "$P") BSData=$(grep -acE '^ *BS_Data' <<< "$P") BSCode=$(grep -acE '^ *BS_Code' <<< "$P")"
done
