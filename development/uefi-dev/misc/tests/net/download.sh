#!/bin/bash
# Usage: download.sh [ports...]   UEFI downloads a blob over TFTP and HTTP (tftp.efi, http.efi), files must match. SIZE=bytes (default 1 MB). Needs: ping.sh done.
. "$(dirname "$0")/../../lib.sh"
PORTS=${*:-0 7}
SRV=/tmp/download-srv
SIZE=${SIZE:-1048576}
SIZE_TEXT=$(sed ':a;s/\B[0-9]\{3\}\>/,&/;ta' <<< $SIZE)
DNSMASQ_PID=/tmp/download-dnsmasq.pid
HTTP_LOG=/tmp/download-http.log

rm -rf $SRV
mkdir -p $SRV
head -c $SIZE /dev/urandom > $SRV/blob.bin
chmod -R a+rX $SRV

ARGS=""
HTTP_PIDS=""
rm -f $HTTP_LOG
for P in $PORTS; do
    host_setup $P
    ARGS+=" --interface=$(tap $P)"
    python3 -m http.server 8080 --bind $(host_ip $P) --directory $SRV >> $HTTP_LOG 2>&1 &
    HTTP_PIDS+=" $!"
done
[ -f $DNSMASQ_PID ] && kill $(cat $DNSMASQ_PID) 2> /dev/null || true
dnsmasq -C /dev/null --port=0 --bind-interfaces $ARGS --enable-tftp --tftp-root=$SRV --pid-file=$DNSMASQ_PID
sleep 1

uefi_begin
SCRIPT+=" set timeout $((300 + SIZE / 50000));"
for P in $PORTS; do
    uefi_part $P
    uefi_cmd "tftp.efi -i $(eth $P) $(host_ip $P) blob.bin t.bin"
    uefi_cmd "http.efi -i $(eth $P) http://$(host_ip $P):8080/blob.bin h.bin"
    uefi_cmd "ls *.bin"
    uefi_cmd "comp t.bin h.bin"
    uefi_cmd "rm t.bin h.bin"
done
uefi_part END
uefi_end
kill $HTTP_PIDS $(cat $DNSMASQ_PID)

OUT=$(uefi_log)
for P in $PORTS; do
    R=$(log_part "$OUT" $P)
    N=$(grep -ac " $SIZE_TEXT  [th]\.bin" <<< "$R" || true)
    check "port $P size" "full files=$N" "^full files=2\$"
    R=$(grep -a -m1 "differences" <<< "$R" || true)
    check "port $P tftp==http" "$R" "no differences"
done
echo "http log: $HTTP_LOG"
finish
