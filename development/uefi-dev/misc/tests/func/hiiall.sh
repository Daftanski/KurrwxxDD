#!/bin/bash
# Usage: hiiall.sh [ports...]   HII every form and question per port (hii.efi forms/detail/get/set): values, bad QID, bad value, ping. Needs: driver loaded.
. "$(dirname "$0")/../../lib.sh"
PORTS=${*:-$ALL_PORTS}
FORMS="0x0200 0x0205 0x0202 0x0203 0x0204"
QIDS="0x100A 0x1005 0x1007 0x0004 0x0005"

uefi_begin hii-list
uefi_cmd "hii.efi list"
uefi_end
LIST=$(uefi_log)
declare -A FS
for P in $PORTS; do
    FS[$P]=$(hii_formset "$LIST" $P)
    check "port $P formset" "id=${FS[$P]}" "^id=[0-9]+\$"
done

for P in $PORTS; do
    host_setup $P
done

uefi_begin
for P in $PORTS; do
    [ -n "${FS[$P]}" ] || continue
    uefi_part $P
    uefi_cmd "hii.efi forms ${FS[$P]}"
    for F in $FORMS; do
        uefi_cmd "hii.efi detail ${FS[$P]} $F"
    done
    for Q in $QIDS 0x9999; do
        uefi_cmd "hii.efi get ${FS[$P]} $Q"
    done
    uefi_cmd "hii.efi set ${FS[$P]} 0x100A 16"
    uefi_cmd "hii.efi set ${FS[$P]} 0x9999 1"
done
uefi_part ping
for P in $PORTS; do
    uefi_ifconfig $P
    uefi_ping $P 2
done
uefi_part END
uefi_end

OUT=$(uefi_log)
# v <part> <qid>: "Value:" line printed after "QID: <qid>".
v() { log_part "$OUT" $1 | grep -a -A2 "^QID: *$2" | grep -a -m1 "^Value:" | sed 's/^Value: *//'; }
for P in $PORTS; do
    [ -n "${FS[$P]}" ] || continue
    R=$(log_part "$OUT" $P)
    for F in $FORMS; do
        check_eq "port $P form $F listed" "$(grep -ac "^$F  *[A-Z]" <<< "$R" || true)" 1
    done
    check_eq "port $P forms with fields" "$(grep -ac '^Fields in formset' <<< "$R" || true)" 5
    check_eq "port $P Blink LEDs" "$(v $P 0x100A)" "0 (0x0)"
    check_eq "port $P Link Status" "$(v $P 0x1005)" "1 (0x1)"
    check "port $P Virtual MAC" "$(v $P 0x1007)" "^([0-9A-F]{2}:){5}[0-9A-F]{2}\$"
    check "port $P port option 4" "$(v $P 0x0004)" "^[0-9]+ \(0x"
    check "port $P port option 5" "$(v $P 0x0005)" "^[0-9]+ \(0x"
    check_eq "port $P get bad QID" "$(grep -ac 'Question 0x9999 not found' <<< "$R" || true)" 2
    check_eq "port $P set out of range" "$(grep -ac 'value 16 out of range' <<< "$R" || true)" 1
    check_eq "port $P set bad QID" "$(grep -ac 'Set question 0x9999' <<< "$R" || true)" 0
    check "port $P ping" "$(ping_result "$OUT" $(host_ip $P))" " 2 received"
done
finish
