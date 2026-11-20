#!/bin/bash
# Usage: large.sh [A:B]   Loopback pair (default 0:1): pings of 1472/4000/8000 bytes A->B and B->A (IP fragments at MTU 1500, 3 each, >= 2); no BUG/ixd error (e.g. "hw csum failure") in dmesg. Needs: ixd.sh done, ports not in a bridge. Changes: ports, host taps (restored). Time: ~10 s.
. "$(dirname "$0")/../lib.sh"
read -r A B <<< "$(pair_split $1)"
guest_need
dmesg_mark
loop_up $A $B || finish

for S in 1472 4000 8000; do
    check "port $A -> port $B $S" "$(loop_ping_ab 3 -s $S)" " [23] received"
    check "port $B -> port $A $S" "$(loop_ping_ba 3 -s $S)" " [23] received"
done

loop_down
check_dmesg "dmesg clean"
finish
