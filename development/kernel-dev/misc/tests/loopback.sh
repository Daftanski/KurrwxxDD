#!/bin/bash
# Usage: loopback.sh [portA] [portB]   Ports wired back to back (host bridge of their taps, default 0 1 = PF0 <-> PF1 on PFP); B in a guest netns; ping A->B and B->A, each through both taps. Needs: ixd.sh done, ports not in a bridge. Changes: ports, host taps (restored). Time: ~1 min.
. "$(dirname "$0")/../lib.sh"
A=${1:-0}
B=${2:-1}
N=10
guest_need
dmesg_mark
loop_up $A $B || finish

RXA=$(tap_rx $A)
RXB=$(tap_rx $B)
check "port $A -> port $B" "$(loop_ping_ab $N)" " ($N|$((N - 1))) received"
check "port $B -> port $A" "$(loop_ping_ba $N)" " ($N|$((N - 1))) received"
# Proof the packets left the guest: each side sent >= 2N-2 (requests + replies).
check_ge "tap $(tap $A) rx +" $(($(tap_rx $A) - RXA)) $((2 * N - 2))
check_ge "tap $(tap $B) rx +" $(($(tap_rx $B) - RXB)) $((2 * N - 2))

loop_down
check_eq "port $B back in init ns" "$(g "ls /sys/class/net" | grep -cx "$LOOP_DEV_B" || true)" 1
check_eq "host bridge removed" "$(ip link show $LOOP_BR 2> /dev/null | grep -c . || true)" 0
check_dmesg "dmesg clean"
finish
