#!/bin/bash
# Usage: flood.sh [port] [count]   Host flood-pings one port (RX ring overflow), then normal pings both ways. Needs: ping.sh done.
. "$(dirname "$0")/../../lib.sh"
P=${1:-0}
COUNT=${2:-5000}

F=$(ping -f -q -c $COUNT -W 1 -I $(tap $P) $(uefi_ip $P) 2>&1 | grep transmitted || true)
echo "INFO flood: $F"
check "flood got replies" "$F" " [1-9][0-9]* received"

uefi_begin
check "port $P host->uefi after" "$(host_ping $P $(uefi_ip $P) 3)" " 3 received"
uefi_ping $P 3
uefi_end

OUT=$(uefi_log)
check "port $P uefi->host after" "$(ping_result "$OUT" $(host_ip $P))" " 3 received"
finish
