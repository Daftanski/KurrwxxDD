#!/bin/bash
# Usage: hii.sh [ports...]   HII main form per port (hii.efi): values match the device, fr-FR, set, then ping. Needs: driver loaded.
. "$(dirname "$0")/../../lib.sh"
PORTS=${*:-$ALL_PORTS}
PING_PORTS="0 7"

# Formset IDs change between boots: find them by MAC.
uefi_begin hii-list
uefi_cmd "hii.efi list"
uefi_end
LIST=$(uefi_log)
declare -A FS
for P in $PORTS; do
    FS[$P]=$(hii_formset "$LIST" $P)
    check "port $P formset" "id=${FS[$P]}" "^id=[0-9]+\$"
done
F0=${FS[${PORTS%% *}]}
[ -n "$F0" ] || finish

uefi_begin
uefi_cmd "drivers"
uefi_handles
uefi_part pci
uefi_each_ctrl 'dh -v $c'
for P in $PORTS; do
    [ -n "${FS[$P]}" ] || continue
    uefi_part $P
    uefi_cmd "hii.efi show ${FS[$P]} $HII_MAIN_FORM"
done
uefi_part lang
uefi_cmd "hii.efi show $F0 $HII_MAIN_FORM --lang fr-FR"
uefi_part set
uefi_cmd "hii.efi set $F0 0x100A 1"
uefi_part ping
for P in $PING_PORTS; do
    host_setup $P
    uefi_ifconfig $P
    uefi_ping $P 2
done
uefi_part END
uefi_end

OUT=$(uefi_log)
PCI=$(log_part "$OUT" pci)
pci() { grep -a -m1 "$1" <<< "$PCI" | awk '{ print $NF }'; }
# All our controllers (PFP: one PF per port). Port P must show one of them.
ADDRS=$(grep -a -E "(Segment|Bus|Device|Function) #" <<< "$PCI" | awk '{ print $NF }' | paste - - - - |
    while read S B D F; do printf "%04X:%s:%s:%s " $((16#$S)) $B $D $F; done)
DNAME=$(driver_name "$(driver_line "$OUT")")

for P in $PORTS; do
    [ -n "${FS[$P]}" ] || continue
    F=$(hii_fields "$(log_part "$OUT" $P)")
    check_eq "port $P MAC Address" "$(hii_value "$F" "MAC Address")" "$(mac $P)"
    check_eq "port $P UEFI Driver" "$(hii_value "$F" "UEFI Driver")" "$DNAME"
    check "port $P PCI Address" " $ADDRS" " $(hii_value "$F" "PCI Address") "
    check_eq "port $P PCI Device ID" "$(hii_value "$F" "PCI Device ID")" "$(pci "Device ID")"
    check "port $P Device Name" "$(hii_value "$F" "Device Name")" "^Intel\(R\) Ethernet Connection"
    check_eq "port $P Link Status" "$(hii_value "$F" "Link Status")" "Connected"
done

R=$(grep -a -m1 "^form_title:" <<< "$(log_part "$OUT" lang)" || true)
check "fr-FR title" "$R" "Page de configuration principale"
R=$(grep -a -m1 -E "^(Set question|RouteConfig failed)" <<< "$(log_part "$OUT" set)" || true)
check "set Blink LEDs" "$R" "^Set question 0x100A"
for P in $PING_PORTS; do
    check "port $P after HII" "$(ping_result "$OUT" $(host_ip $P))" " 2 received"
done
finish
