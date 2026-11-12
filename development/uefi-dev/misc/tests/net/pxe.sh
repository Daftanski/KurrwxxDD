#!/bin/bash
# Usage: pxe.sh [ports...]   PXE boot pxeboot.efi from the host (dnsmasq DHCP + TFTP). Needs: fresh boot.
# pxeboot.efi (misc/tools/pxeboot/) boots the PXEv4 device of a port; the NBP is pxeboot.efi again.
. "$(dirname "$0")/../../lib.sh"
PORTS=${*:-$ALL_PORTS}
TFTP=/tmp/pxe-tftp
DNSMASQ_LOG=/tmp/pxe-dnsmasq.log
DNSMASQ_PID=/tmp/pxe-dnsmasq.pid

rm -rf $TFTP $DNSMASQ_LOG
mkdir -p $TFTP
cp $DEV/core/usb-drive/pxeboot.efi $TFTP/
chmod -R a+rX $TFTP

ARGS=""
for P in $PORTS; do
    host_setup $P
    ARGS+=" --interface=$(tap $P) --dhcp-range=192.168.$P.150,192.168.$P.199"
done
[ -f $DNSMASQ_PID ] && kill $(cat $DNSMASQ_PID) 2> /dev/null || true
dnsmasq -C /dev/null --port=0 --bind-interfaces $ARGS --dhcp-boot=pxeboot.efi \
    --enable-tftp --tftp-root=$TFTP --dhcp-leasefile=/tmp/pxe-dnsmasq.leases \
    --log-dhcp --log-facility=$DNSMASQ_LOG --pid-file=$DNSMASQ_PID

uefi_begin
uefi_load
for P in $PORTS; do
    # PXE eats keys typed while it runs: wait for the app's last line.
    uefi_cmd "pxeboot.efi $(mac_hex $P)" 'PXEBOOT: (StartImage|LoadImage [^S]|no ).*FS1:'
    uefi_cmd "echo PXE-DONE-$P"
done
uefi_end
kill $(cat $DNSMASQ_PID)

OUT=$(uefi_log)
for P in $PORTS; do
    R=$(sed -n "/pxeboot.efi $(mac_hex $P)/,/^PXE-DONE-$P\$/p" <<< "$OUT" | grep -a "PXEBOOT:" | tr '\n' ' ' || true)
    check "port $P" "$R" "NBP running.*StartImage Success"
    N=$(grep -c "sent $TFTP/pxeboot.efi to 192\.168\.$P\." $DNSMASQ_LOG || true)
    check "port $P tftp" "sent=$N" "^sent=[1-9]"
done
echo "dnsmasq log: $DNSMASQ_LOG"
finish
