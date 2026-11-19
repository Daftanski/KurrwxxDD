#!/bin/bash
# Usage: snpdamage.sh   One SNP call pattern at a time on every child (init2, cycle, stopstart, reset) with the stack above: which one leaves the ports dead? Each pattern ends with a ping on all ports. Needs: driver loaded, nictest.efi. Restart afterwards if it fails.
. "$(dirname "$0")/../../lib.sh"

for P in $ALL_PORTS; do
    host_setup $P
done

uefi_begin
for P in $ALL_PORTS; do
    uefi_ifconfig $P
done
uefi_part base
for P in $ALL_PORTS; do
    uefi_ping $P 2
done
for M in reset cycle cyclefilter stopstart init2; do
    uefi_part $M
    uefi_cmd "nictest.efi snpdamage $M" 'NICTEST done.*FS1:'
    uefi_part $M-ping
    for P in $ALL_PORTS; do
        uefi_ping $P 2
    done
done
uefi_end

OUT=$(uefi_log)
for M in base reset cycle cyclefilter stopstart init2; do
    [ $M = base ] && R=$(log_part "$OUT" base) || R=$(log_part "$OUT" $M-ping)
    LOST=0
    for P in $ALL_PORTS; do
        grep -q " 2 received" <<< "$(ping_result "$R" $(host_ip $P))" || LOST=$((LOST + 1))
    done
    check_eq "$M: ports without ping" "$LOST" 0
    [ $M != base ] && echo "INFO $M: $(log_part "$OUT" $M | grep -ao 'snpdamage [0-9]* [a-z0-9]* status=[A-Za-z ]*' | sed 's/snpdamage [0-9]* //' | sort | uniq -c | tr '\n' ';')"
done
finish
