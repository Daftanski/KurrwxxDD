#!/bin/bash
# Usage: queues.sh [A:B]   Loopback pair (default 0:1): ethtool -L combined on port A to 1, 2 and min(CPUs-1, 16, max); each time ethtool -l reads it back and ping A->B / B->A works; original count restored. Needs: ixd.sh done, ports not in a bridge. Changes: ports (queue count), host taps (restored). Time: ~20 s.
# From: BATS hsd1808797992 (minimal / new queue count), hsd2206551352 (less than CPUs) + traffic.
. "$(dirname "$0")/../lib.sh"
read -r A B <<< "$(pair_split $1)"
guest_need
dmesg_mark
loop_up $A $B || finish
D=$LOOP_DEV_A

# combined <max|cur>: from ethtool -l ("Pre-set maximums" first, "Current" second).
combined() {
    g "ethtool -l $D" | awk -v w=$1 '/^Pre-set/ { s = "max" } /^Current/ { s = "cur" } s == w && /^Combined:/ { print $2 }'
}
MAX=$(combined max)
ORIG=$(combined cur)
check "port $A combined max" "${MAX:-none}" "^[0-9]+$"
[ -n "$MAX" ] && [ -n "$ORIG" ] || finish
at_exit "g \"ethtool -L $D combined $ORIG\""
CPUS=$(g nproc)
LESS=$((CPUS - 1))
[ $LESS -gt 16 ] && LESS=16
[ $LESS -gt $MAX ] && LESS=$MAX
[ $LESS -lt 1 ] && LESS=1
echo "INFO port $A ($D): combined $ORIG of max $MAX, guest CPUs $CPUS"

for Q in 1 2 $LESS; do
    check "port $A set combined $Q" "$(g "ethtool -L $D combined $Q 2>&1; echo rc=\$?" | tr '\n' ' ')" "rc=0 $"
    check_eq "port $A combined $Q read back" "$(combined cur)" $Q
    # Queue change resets the queues: link + traffic back first.
    loop_wait_carrier 1 30
    loop_first_traffic
    check "port $A -> port $B (combined $Q)" "$(loop_ping_ab 10)" " (10|9) received"
    check "port $B -> port $A (combined $Q)" "$(loop_ping_ba 10)" " (10|9) received"
done

g "ethtool -L $D combined $ORIG" || true
check_eq "port $A combined restored" "$(combined cur)" $ORIG
loop_down
check_dmesg "dmesg clean"
finish
