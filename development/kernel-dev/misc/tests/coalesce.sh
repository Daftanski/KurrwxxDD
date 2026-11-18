#!/bin/bash
# Usage: coalesce.sh [A:B]   Loopback pair (default 0:1): on port A adaptive-rx/tx on and off, rx-usecs/tx-usecs 100 with adaptive off; each read back with ethtool -c; ping A->B / B->A after; original values restored. Needs: ixd.sh done, ports not in a bridge. Changes: ports (coalesce), host taps (restored). Time: ~20 s.
# From: BATS hsd1808310570 (adaptive rx/tx off, rx/tx-usecs settable) + traffic.
. "$(dirname "$0")/../lib.sh"
read -r A B <<< "$(pair_split $1)"
guest_need
dmesg_mark
loop_up $A $B || finish
D=$LOOP_DEV_A

# co <field>: value from ethtool -c (arx, atx = adaptive rx/tx on|off; rx-usecs, tx-usecs).
co() {
    g "ethtool -c $D" | awk -v f=$1 '
        /^Adaptive RX:/ { if (f == "arx") print $3; if (f == "atx") print $5 }
        $1 == f ":" { print $2 }'
}
setc() {
    check "port $A ethtool -C $*" "$(g "ethtool -C $D $* 2>&1; echo rc=\$?" | tr '\n' ' ')" "rc=0 $"
}
O_ARX=$(co arx); O_ATX=$(co atx); O_RXU=$(co rx-usecs); O_TXU=$(co tx-usecs)
echo "INFO port $A ($D): adaptive rx $O_ARX tx $O_ATX, rx-usecs $O_RXU, tx-usecs $O_TXU"
# Restore: fixed usecs only stick with adaptive off, so off -> usecs -> original adaptive.
RESTORE="ethtool -C $D adaptive-rx off adaptive-tx off; ethtool -C $D rx-usecs $O_RXU tx-usecs $O_TXU; ethtool -C $D adaptive-rx $O_ARX adaptive-tx $O_ATX"
at_exit "g \"$RESTORE\" 2> /dev/null"

for V in on off; do
    setc adaptive-rx $V
    check_eq "port $A adaptive-rx $V read back" "$(co arx)" $V
    setc adaptive-tx $V
    check_eq "port $A adaptive-tx $V read back" "$(co atx)" $V
done
# Adaptive is off now: fixed values must stick.
setc rx-usecs 100
check_eq "port $A rx-usecs read back" "$(co rx-usecs)" 100
setc tx-usecs 100
check_eq "port $A tx-usecs read back" "$(co tx-usecs)" 100

check "port $A -> port $B" "$(loop_ping_ab 10)" " (10|9) received"
check "port $B -> port $A" "$(loop_ping_ba 10)" " (10|9) received"

g "$RESTORE" 2> /dev/null || true
check_eq "port $A coalesce restored" "$(co arx) $(co atx) $(co rx-usecs) $(co tx-usecs)" "$O_ARX $O_ATX $O_RXU $O_TXU"
loop_down
check_dmesg "dmesg clean"
finish
