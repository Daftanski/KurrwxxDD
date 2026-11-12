#!/bin/bash
# Usage: load2.sh   Load the driver a 2nd time: the new image must not take the controller; unload it. Needs: driver loaded.
. "$(dirname "$0")/../../lib.sh"
P=0

host_setup $P

uefi_begin
uefi_handles
uefi_part load
uefi_load
# Tcl var h2 = the other handle with our driver file name.
# 2nd image is not bound: "?" in the type column.
SCRIPT+=' set h2 ""; send "drivers\r";'
SCRIPT+=' expect -re {([0-9A-Fa-f]+)\x1b\[0m[^\n]* \? [^\n]*'$DRIVER'} { set h2 $expect_out(1,string) }; expect "FS1:";'
uefi_part h2
uefi_tcl 'dh -d $h2'
uefi_part unload
uefi_tcl 'unload -n $h2'
uefi_part h1
uefi_tcl 'dh -d $h'
uefi_ifconfig $P
uefi_ping $P 2
uefi_part END
uefi_end

OUT=$(uefi_log)
check "2nd load" "$(grep -a -m1 "^Image " <<< "$(log_part "$OUT" load)" || true)" "Success"
check_eq "drivers lines" "$(grep -ac "$DRIVER" <<< "$(cmd_out "$(log_part "$OUT" load)" drivers)" || true)" 2
check_eq "2nd image controllers" "$(grep -ac "Ctrl\[" <<< "$(log_part "$OUT" h2)" || true)" 0
check "2nd unload" "$(grep -a -m1 "Unload" <<< "$(log_part "$OUT" unload)" || true)" "Success"
R=$(log_part "$OUT" h1)
check_eq "1st image children" "$(child_handles "$R" | wc -l)" "$(wc -w <<< "$ALL_PORTS")"
check "port $P" "$(ping_result "$R" $(host_ip $P))" " 2 received"
finish
