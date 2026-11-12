#!/bin/bash
# Usage: http-boot.sh [ports...]   HTTP boot pxeboot.efi from the host (dnsmasq DHCP + python http.server). Needs: fresh boot.
# "pxeboot.efi <MAC> http" boots the HTTPv4 device of a port; the NBP is pxeboot.efi again.
. "$(dirname "$0")/../../lib.sh"
PORTS=${*:-$ALL_PORTS}
SRV=/tmp/http-boot-srv
DNSMASQ_LOG=/tmp/http-boot-dnsmasq.log
DNSMASQ_PID=/tmp/http-boot-dnsmasq.pid
HTTP_LOG=/tmp/http-boot-http.log

rm -rf $SRV $DNSMASQ_LOG $HTTP_LOG
mkdir -p $SRV
cp $DEV/core/usb-drive/pxeboot.efi $SRV/
chmod -R a+rX $SRV

# HTTP boot takes only offers with vendor class HTTPClient; dnsmasq tags requests with the interface name.
ARGS="--dhcp-vendorclass=set:http,HTTPClient --dhcp-option-force=tag:http,60,HTTPClient"
HTTP_PIDS=""
for P in $PORTS; do
    host_setup $P
    ARGS+=" --interface=$(tap $P) --dhcp-range=192.168.$P.150,192.168.$P.199"
    ARGS+=" --dhcp-boot=tag:$(tap $P),tag:http,http://$(host_ip $P):8080/pxeboot.efi"
    python3 -m http.server 8080 --bind $(host_ip $P) --directory $SRV >> $HTTP_LOG 2>&1 &
    HTTP_PIDS+=" $!"
done
[ -f $DNSMASQ_PID ] && kill $(cat $DNSMASQ_PID) 2> /dev/null || true
dnsmasq -C /dev/null --port=0 --bind-interfaces $ARGS --dhcp-leasefile=/tmp/http-boot-dnsmasq.leases \
    --log-dhcp --log-facility=$DNSMASQ_LOG --pid-file=$DNSMASQ_PID
sleep 1

uefi_begin
uefi_load
for P in $PORTS; do
    # Boot eats keys typed while it runs: wait for the app's last line.
    uefi_cmd "pxeboot.efi $(mac_hex $P) http" 'PXEBOOT: (StartImage|LoadImage [^S]|no ).*FS1:'
    uefi_cmd "echo HTTP-DONE-$P"
done
uefi_end
kill $HTTP_PIDS $(cat $DNSMASQ_PID)

OUT=$(uefi_log)
for P in $PORTS; do
    R=$(sed -n "/pxeboot.efi $(mac_hex $P) http/,/^HTTP-DONE-$P\$/p" <<< "$OUT" | grep -a "PXEBOOT:" | tr '\n' ' ' || true)
    check "port $P" "$R" "NBP running.*StartImage Success"
    N=$(grep -c "^192\.168\.$P\.[0-9]* .*GET /pxeboot.efi" $HTTP_LOG || true)
    check "port $P http" "get=$N" "^get=[1-9]"
done
echo "dnsmasq log: $DNSMASQ_LOG, http log: $HTTP_LOG"
finish
