#!/bin/bash
# Usage: ping.sh [A:B ...]   Loopback pairs (default all 8 ports: 0:1 2:3 4:5 6:7; PFP: port = PF): ping A->B and B->A (10 each, >= 9), both host taps carried them. Needs: ixd.sh done, ports not in a bridge. Changes: ports, host taps (restored). Time: ~40 s/pair.
. "$(dirname "$0")/../lib.sh"
PAIRS=${*:-$ALL_PAIRS}
N=10
guest_need
dmesg_mark

for PAIR in $PAIRS; do
    read -r A B <<< "$(pair_split $PAIR)"
    loop_up $A $B || continue
    RXA=$(tap_rx $A)
    RXB=$(tap_rx $B)
    check "port $A -> port $B" "$(loop_ping_ab $N)" " ($N|$((N - 1))) received"
    check "port $B -> port $A" "$(loop_ping_ba $N)" " ($N|$((N - 1))) received"
    # Proof the packets left the guest: each side sent >= 2N-2 (requests + replies).
    check_ge "tap $(tap $A) rx +" $(($(tap_rx $A) - RXA)) $((2 * N - 2))
    check_ge "tap $(tap $B) rx +" $(($(tap_rx $B) - RXB)) $((2 * N - 2))
    loop_down
done

check_dmesg "dmesg clean"
finish
