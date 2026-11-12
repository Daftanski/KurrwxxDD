#!/bin/bash
# Usage: ipv6.sh [ports...]   Static IPv6 on UEFI (ifconfig6), ping6 both ways. Uses shell.efi. Needs: driver loaded.
. "$(dirname "$0")/../../lib.sh"
PORTS=${*:-$ALL_PORTS}

uefi6_ip() { echo 2001:db8:$1::101; }
host6_ip() { echo 2001:db8:$1::200; }
# ping6/ifconfig6 exist only in the full shell.efi.
shell6()   { uefi_cmd "shell.efi -nostartup -exit $1" "${2:-FS1:}"; }

uefi_begin
for P in $PORTS; do
    ip -6 addr replace $(host6_ip $P)/64 dev $(tap $P)
    shell6 "ifconfig6 -s $(eth $P) man host $(uefi6_ip $P)/64"
    shell6 "ping6 -n 2 -s $(uefi6_ip $P) $(host6_ip $P)" 'packets transmitted.*FS1:'
done
uefi_end

OUT=$(uefi_log)
for P in $PORTS; do
    check "port $P uefi->host" "$(ping_result "$OUT" $(host6_ip $P))" " 2 received"
    check "port $P host->uefi" "$(host_ping $P $(uefi6_ip $P) 2 -6)" " 2 received"
done

# Back to the default policy.
uefi_begin ipv6-restore
for P in $PORTS; do
    shell6 "ifconfig6 -s $(eth $P) auto"
done
uefi_end
finish
