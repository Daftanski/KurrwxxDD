#!/bin/bash
# Usage: linkflap.sh [port] [cycles]   Host tap down / up: traffic stops while down and comes back after up, 3 cycles. INFO: media state seen by UEFI while down (D4). Needs: driver loaded.
. "$(dirname "$0")/../../lib.sh"
P=${1:-0}
CYCLES=${2:-3}
T=$(tap $P)

host_setup $P
trap 'ip link set $T up 2> /dev/null || true' EXIT
uefi_begin
uefi_ifconfig $P
uefi_end

for C in $(seq 1 $CYCLES); do
    ip link set $T down
    sleep 3
    uefi_begin
    uefi_part down
    uefi_cmd "ifconfig -l"
    uefi_ping $P 2
    uefi_end
    OUT=$(uefi_log)
    R=$(log_part "$OUT" down)
    echo "INFO cycle $C media while down: $(grep -a -A1 "^name *: $(eth $P)\$" <<< "$R" | grep -a -o 'Media State.*' | head -1)"
    check "cycle $C uefi->host while down" "$(ping_result "$R" $(host_ip $P))" " 0 received"
    ip link set $T up
    ip addr replace $(host_ip $P)/24 dev $T
    sleep 5
    check "cycle $C host->uefi after up" "$(host_ping $P $(uefi_ip $P) 3)" " 3 received"
    uefi_begin
    uefi_part first
    uefi_ping $P 3
    uefi_part second
    uefi_ping $P 3
    uefi_end
    OUT=$(uefi_log)
    echo "INFO cycle $C first uefi->host ping after up: $(ping_result "$(log_part "$OUT" first)" $(host_ip $P))"
    check "cycle $C uefi->host after up (2nd try)" "$(ping_result "$(log_part "$OUT" second)" $(host_ip $P))" " 3 received"
done
finish
