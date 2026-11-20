#!/bin/bash
# Usage: speed.sh [A:B]   Loopback pair (default 0:1): ethtool -s speed 0 on port A is refused with a message; link stays up and ping A->B / B->A works. Needs: ixd.sh done, ports not in a bridge. Changes: none (refused setting), host taps (restored). Time: ~10 s.
# From: BATS hsd16026008225 (invalid parameter for ethtool -s speed fails) + link/traffic after.
. "$(dirname "$0")/../lib.sh"
read -r A B <<< "$(pair_split $1)"
guest_need
dmesg_mark
loop_up $A $B || finish
D=$LOOP_DEV_A

OUT=$(g "ethtool -s $D speed 0 2>&1; echo rc=\$?" | tr '\n' ' ')
check "port $A speed 0 refused" "$OUT" "rc=[1-9][0-9]* $"
check "port $A speed 0 message" "${OUT% rc=*}" "[a-zA-Z]"
echo "INFO ethtool $D: $(g "ethtool $D" | grep -E 'Speed|Duplex|Link detected' | tr -s ' \t' ' ' | tr '\n' ';')"

check_eq "port $A link after" "$(loop_carrier a)" 1
check "port $A -> port $B" "$(loop_ping_ab 10)" " (10|9) received"
check "port $B -> port $A" "$(loop_ping_ba 10)" " (10|9) received"
loop_down
check_dmesg "dmesg clean"
finish
