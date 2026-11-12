#!/bin/bash
# Usage: txfill.sh   Fill the Tx ring (nictest txfill: transmit without recycling): Transmit refuses cleanly, recycling works, ports ping. Also: child 1 takes the MAC of child 0 and back (nictest samemac). Needs: driver loaded, nictest.efi.
. "$(dirname "$0")/../../lib.sh"

for P in $ALL_PORTS; do
    host_setup $P
done

uefi_begin
for P in $ALL_PORTS; do
    uefi_ifconfig $P
done
uefi_part fill
uefi_cmd "nictest.efi txfill" 'NICTEST done.*FS1:'
uefi_part mac
uefi_cmd "nictest.efi samemac" 'NICTEST done.*FS1:'
uefi_part ping
for P in $ALL_PORTS; do
    uefi_ping $P 2
done
uefi_end

OUT=$(uefi_log)
R=$(log_part "$OUT" fill)
echo "INFO $(grep -a 'NICTEST txfill' <<< "$R" | tr '\n' ' ')"
check "frames sent before refusal" "$(grep -a 'NICTEST txfill sent' <<< "$R" || true)" "sent=[1-9][0-9]* refused status=[^S]"
check "Tx recycled" "$(grep -a 'NICTEST txfill recycled' <<< "$R" || true)" "recycled=[1-9]"
check "Transmit works again" "$(grep -a 'NICTEST txfill again' <<< "$R" || true)" "status=Success"
R=$(log_part "$OUT" mac)
echo "INFO $(grep -a 'NICTEST samemac' <<< "$R" | tr '\n' ' ')"
check "samemac returned" "$(grep -a 'NICTEST samemac set' <<< "$R" || true)" "status="
check "MAC restored" "$(grep -a 'NICTEST samemac reset' <<< "$R" || true)" "status=Success restored=1"
R=$(log_part "$OUT" ping)
for P in $ALL_PORTS; do
    check "port $P" "$(ping_result "$R" $(host_ip $P))" " 2 received"
done
finish
