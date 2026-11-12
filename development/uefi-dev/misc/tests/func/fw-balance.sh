#!/bin/bash
# Usage: fw-balance.sh   Bind cycles: the IMC log shows the same virtchnl ops every cycle (no extra or missing messages) and every enable has its disable. Needs: driver loaded, on the Simics host (reads has-log).
. "$(dirname "$0")/../../lib.sh"
IMC=/root/SimicsWorkspace/has-log/imc_serial_console_vm1.log

for P in $ALL_PORTS; do
    host_setup $P
done

# cycle <n>: one disconnect / connect -r; FW ops of it in /tmp/<name>-<n>.txt.
cycle() {
    local BEFORE
    BEFORE=$(stat -c %s $IMC)
    uefi_begin
    uefi_handles
    uefi_each_ctrl 'disconnect $c'
    uefi_cmd "connect -r"
    uefi_end
    # The IMC log is written late.
    sleep 10
    tail -c +$((BEFORE + 1)) $IMC | grep -ao 'VIRTCHNL2_OP_[A-Z_0-9]*' | sort | uniq -c | sed 's/^ *//' > /tmp/$NAME-$1.txt
}

cycle 1
cycle 2
cycle 3
echo "INFO FW ops per cycle: $(tr '\n' ';' < /tmp/$NAME-3.txt)"
check "FW saw ops" "lines=$(grep -c . /tmp/$NAME-3.txt)" "^lines=[1-9]"
check_eq "cycle 2 and 3 same ops" "$(cat /tmp/$NAME-3.txt)" "$(cat /tmp/$NAME-2.txt)"
# count <op>: how often the op is in cycle 3.
count() { awk -v o="VIRTCHNL2_OP_$1" '$2 == o { print $1 }' /tmp/$NAME-3.txt | head -1; }
check_eq "ENABLE_VPORT = DISABLE_VPORT" "$(count ENABLE_VPORT)" "$(count DISABLE_VPORT)"
check_eq "ENABLE_QUEUES = DISABLE_QUEUES" "$(count ENABLE_QUEUES)" "$(count DISABLE_QUEUES)"
check_eq "CREATE_VPORT = DESTROY_VPORT" "$(count CREATE_VPORT)" "$(count DESTROY_VPORT)"

uefi_begin
for P in $ALL_PORTS; do
    uefi_ifconfig $P
    uefi_ping $P 2
done
uefi_end
OUT=$(uefi_log)
for P in $ALL_PORTS; do
    check "port $P" "$(ping_result "$OUT" $(host_ip $P))" " 2 received"
done
finish
