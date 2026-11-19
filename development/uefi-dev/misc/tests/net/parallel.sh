#!/bin/bash
# Usage: parallel.sh [count] [ports...]   Host pings all ports at the same time. Needs: ping.sh done.
. "$(dirname "$0")/../../lib.sh"
COUNT=${1:-20}
shift || true
PORTS=${*:-$ALL_PORTS}
OUT=/tmp/parallel
rm -rf $OUT
mkdir -p $OUT

for P in $PORTS; do
    ping -c $COUNT -i 0.2 -W 3 -I $(tap $P) $(uefi_ip $P) > $OUT/port$P.txt 2>&1 &
done
wait || true

for P in $PORTS; do
    R=$(grep transmitted $OUT/port$P.txt || true)
    check "port $P" "$R" " $COUNT received"
done
finish
