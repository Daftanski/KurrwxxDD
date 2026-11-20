#!/bin/bash
# Usage: rss.sh [A:B]   Loopback pair (default 0:1): set a new RSS hash key on port A (ethtool -X hkey), read back; ethtool -L combined 1 keeps the key; ping A->B / B->A works; key + queues restored. Needs: ixd.sh done, ports not in a bridge. Changes: ports (RSS key, queue count), host taps (restored). Time: ~15 s.
# From: BATS hsd18010171427 (RSS key not restored to default after queue change) + traffic.
. "$(dirname "$0")/../lib.sh"
read -r A B <<< "$(pair_split $1)"
guest_need
dmesg_mark
loop_up $A $B || finish
D=$LOOP_DEV_A

key() {
    g "ethtool -x $D" 2> /dev/null | grep -iE '^[0-9a-f]{2}(:[0-9a-f]{2})+$' | head -1 || true
}
ORIG=$(key)
check "port $A rss key readable" "${ORIG:-none}" "^[0-9a-f]{2}(:[0-9a-f]{2})+$"
[ -n "$ORIG" ] || finish
NEW=$(tr 0-5 f <<< "$ORIG")
[ "$NEW" != "$ORIG" ] || NEW=$(tr 6-9a-e 0 <<< "$ORIG")
QORIG=$(g "ethtool -l $D" | awk '/^Current/ { c = 1 } c && /^Combined:/ { print $2 }')
at_exit "g \"ethtool -X $D hkey $ORIG; ethtool -L $D combined $QORIG\""

check "port $A set rss key" "$(g "ethtool -X $D hkey $NEW 2>&1; echo rc=\$?" | tr '\n' ' ')" "rc=0 $"
check_eq "port $A rss key read back" "$(key)" "$NEW"

check "port $A set combined 1" "$(g "ethtool -L $D combined 1 2>&1; echo rc=\$?" | tr '\n' ' ')" "rc=0 $"
check_eq "port $A rss key kept after queue change" "$(key)" "$NEW"
loop_wait_carrier 1 30
loop_first_traffic
check "port $A -> port $B" "$(loop_ping_ab 10)" " (10|9) received"
check "port $B -> port $A" "$(loop_ping_ba 10)" " (10|9) received"

g "ethtool -X $D hkey $ORIG; ethtool -L $D combined $QORIG" || true
check_eq "port $A rss key restored" "$(key)" "$ORIG"
loop_down
check_dmesg "dmesg clean"
finish
