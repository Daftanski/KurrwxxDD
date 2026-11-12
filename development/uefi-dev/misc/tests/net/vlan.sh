#!/bin/bash
# Usage: vlan.sh [child] [vlan id]   Add a VLAN on one child (nictest vlan), ping over it both ways, remove it, untagged ping still works. Needs: driver loaded, nictest.efi.
. "$(dirname "$0")/../../lib.sh"
P=${1:-0}
ID=${2:-10}
VDEV=$(tap $P).$ID
VNET=192.168.100

host_setup $P
ip link del $VDEV 2> /dev/null || true
ip link add link $(tap $P) name $VDEV type vlan id $ID
ip addr replace $VNET.200/24 dev $VDEV
ip link set $VDEV up
trap 'ip link del $VDEV 2> /dev/null || true' EXIT

# names <text>: interface names of "ifconfig -l".
names() { grep -aoE '^name +: eth[0-9]+' <<< "$1" | sed 's/.*: //' | sort; }

uefi_begin
uefi_part before
uefi_cmd "ifconfig -l"
uefi_part add
uefi_cmd "nictest.efi vlan $P $ID" 'NICTEST done.*FS1:'
uefi_cmd "connect -r" 'FS1:'
uefi_part after
uefi_cmd "ifconfig -l"
uefi_end
OUT=$(uefi_log)
check "vlan add" "$(log_part "$OUT" add | grep -a "NICTEST vlan $P set" || true)" "status=Success"
# EDK2 VlanConfigDxe replaces the untagged interface: same name, listed again last.
NEW=$(eth $P)
check_eq "interface $NEW rebuilt as VLAN" "$(names "$(log_part "$OUT" after)" | grep -c "^$NEW\$" || true)" 1

uefi_begin
uefi_cmd "ifconfig -s $NEW static $VNET.101 255.255.255.0 $VNET.1"
uefi_cmd "ping -n 3 -s $VNET.101 $VNET.200" '(packets transmitted|No configured interfaces).*FS1:'
uefi_end
OUT=$(uefi_log)
check "vlan $ID uefi->host" "$(ping_result "$OUT" $VNET.200)" " 3 received"
check "vlan $ID host->uefi" "$(ping -c 3 -W 2 -I $VDEV $VNET.101 2>&1 | grep transmitted || true)" " 3 received"

uefi_begin
uefi_part rm
uefi_cmd "nictest.efi vlan $P remove $ID" 'NICTEST done.*FS1:'
uefi_cmd "connect -r" 'FS1:'
uefi_cmd "ifconfig -l"
uefi_ifconfig $P
uefi_ping $P 2
uefi_end
OUT=$(uefi_log)
R=$(log_part "$OUT" rm)
check "vlan remove" "$(grep -a "NICTEST vlan $P remove" <<< "$R" || true)" "status=Success"
check "untagged ping after remove" "$(ping_result "$R" $(host_ip $P))" " 2 received"
finish
