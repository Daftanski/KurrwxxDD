#!/bin/bash
# Usage: unload-busy.sh [busy port]   Unload while the host pings another port, then load again: all ports ping. Needs: driver not loaded.
. "$(dirname "$0")/../../lib.sh"
B=${1:-1}

for X in $ALL_PORTS; do
    host_setup $X
done

uefi_begin
uefi_load
uefi_ifconfig $B
uefi_ping $B 2
uefi_end
OUT=$(uefi_log)
check "port $B ping before" "$(ping_result "$OUT" $(host_ip $B))" " 2 received"

# Host ping runs over the whole unload / load.
ping -c 90 -i 0.5 -W 1 -I $(tap $B) $(uefi_ip $B) > /tmp/$NAME-ping.txt 2>&1 &
BG=$!

uefi_begin
uefi_unload
uefi_part reload
uefi_load
for X in $ALL_PORTS; do
    uefi_ifconfig $X
    uefi_ping $X 2
done
uefi_end
OUT=$(uefi_log)

check "unload under traffic" "$(grep -a -m1 "Unload" <<< "$OUT" || true)" "Success"
R=$(log_part "$OUT" reload)
check "reload" "$(grep -a -m1 "^Image " <<< "$R" || true)" "Success"
for X in $ALL_PORTS; do
    check "port $X after reload" "$(ping_result "$R" $(host_ip $X))" " 2 received"
done
kill -INT $BG 2> /dev/null || true
wait $BG 2> /dev/null || true
echo "INFO host ping during unload: $(grep -a transmitted /tmp/$NAME-ping.txt || true)"
finish
