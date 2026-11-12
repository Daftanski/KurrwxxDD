#!/bin/bash
# Usage: fw-dead.sh   IMC cores stopped in Simics: data path keeps going (INFO), connect returns without hang, and after the cores run again everything works. Needs: driver loaded.
. "$(dirname "$0")/../../lib.sh"
N=$(wc -w <<< "$ALL_PORTS")
LIMIT=240

# fw <enable|disable>: both IMC cores.
fw() { $DEV/misc/helpers/execute-simics-cmd.sh "cnic.imc.core[0].$1" "cnic.imc.core[1].$1" > /dev/null; }
trap 'fw enable' EXIT

for P in $ALL_PORTS; do
    host_setup $P
done

# Data path with a dead FW (L5.3): HW queues do not need the IMC.
uefi_begin
uefi_ifconfig 0
uefi_end
fw disable
sleep 2
echo "INFO host ping port 0 with FW stopped: $(host_ping 0 $(uefi_ip 0) 5)"
fw enable

# Control path with a dead FW (L5.1): disconnect while the FW runs, connect while it is stopped.
uefi_begin
uefi_handles
uefi_each_ctrl 'disconnect $c'
uefi_end
fw disable
START=$(date +%s)
uefi_begin
SCRIPT+=" set timeout $LIMIT;"
uefi_part dead
uefi_driver_handle
uefi_cmd "connect -r" 'FS1:'
uefi_tcl 'dh -d $h'
uefi_end
T=$(($(date +%s) - START))
OUT=$(uefi_log)
check_le "connect with stopped FW returned (s)" "$T" $((LIMIT - 10))
echo "INFO children while FW stopped: $(child_handles "$(log_part "$OUT" dead)" | wc -l) of $N"
fw enable
sleep 5

# Recovery (L5.1): FW runs again, a new bind cycle works.
uefi_begin
uefi_handles
uefi_each_ctrl 'disconnect $c'
uefi_part back
uefi_cmd "connect -r" 'FS1:'
uefi_tcl 'dh -d $h'
for P in $ALL_PORTS; do
    uefi_ifconfig $P
    uefi_ping $P 2
done
uefi_end
OUT=$(uefi_log)
R=$(log_part "$OUT" back)
check_eq "children after FW is back" "$(child_handles "$R" | wc -l)" $N
for P in $ALL_PORTS; do
    check "port $P" "$(ping_result "$R" $(host_ip $P))" " 2 received"
done
finish
