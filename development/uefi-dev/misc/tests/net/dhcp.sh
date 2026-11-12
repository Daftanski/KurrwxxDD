#!/bin/bash
# Usage: dhcp.sh [ports...]   UEFI gets an IP from dnsmasq, host pings it, then back to static. Needs: ping.sh done.
. "$(dirname "$0")/../../lib.sh"
PORTS=${*:-$ALL_PORTS}
DNSMASQ_LOG=/tmp/dhcp-dnsmasq.log
DNSMASQ_PID=/tmp/dhcp-dnsmasq.pid
LEASES=/tmp/dhcp-dnsmasq.leases

rm -f $DNSMASQ_LOG $LEASES
ARGS=""
for P in $PORTS; do
    host_setup $P
    ARGS+=" --interface=$(tap $P) --dhcp-range=192.168.$P.150,192.168.$P.199"
done
[ -f $DNSMASQ_PID ] && kill $(cat $DNSMASQ_PID) 2> /dev/null || true
dnsmasq -C /dev/null --port=0 --bind-interfaces $ARGS --dhcp-leasefile=$LEASES \
    --log-dhcp --log-facility=$DNSMASQ_LOG --pid-file=$DNSMASQ_PID

uefi_begin
for P in $PORTS; do
    uefi_cmd "ifconfig -s $(eth $P) dhcp"
done
uefi_cmd "stall 30000000"
for P in $PORTS; do
    uefi_part $P
    uefi_cmd "ifconfig -l $(eth $P)"
done
uefi_part END
uefi_end

OUT=$(uefi_log)
for P in $PORTS; do
    IP=$(grep -i " $(mac $P) " $LEASES | awk '{print $3}' || true)
    IP=${IP:-none}
    check "port $P lease" "ip=$IP" "^ip=192\.168\.$P\.1[5-9][0-9]\$"
    R=$(log_part "$OUT" $P | grep -a -A1 "ipv4 address" | tr -d '\n' || true)
    check "port $P ifconfig" "$R" "$IP"
    check "port $P host->uefi" "$(host_ping $P $IP 2)" " 2 received"
done
kill $(cat $DNSMASQ_PID)

# Back to static for the next tests.
uefi_begin dhcp-restore
for P in $PORTS; do
    uefi_ifconfig $P
done
uefi_end
for P in $PORTS; do
    check "port $P static again" "$(host_ping $P $(uefi_ip $P) 2)" " 2 received"
done
echo "dnsmasq log: $DNSMASQ_LOG"
finish
