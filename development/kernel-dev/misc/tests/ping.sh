#!/bin/bash
# Usage: ping.sh [ports...]   Guest <-> host ping both ways per port (default all 8), >= 3 of 5. Needs: ixd.sh done, ports not in a bridge. Changes: ports (restored). Time: ~10 s/port.
. "$(dirname "$0")/../lib.sh"
PORTS=${*:-$ALL_PORTS}
guest_need
dmesg_mark

for P in $PORTS; do
    port_up $P || continue
    check "port $P guest->host" "$(guest_ping $P 5)" " [345] received"
    check "port $P host->guest" "$(host_ping $P 5)" " [345] received"
    port_down $P
done

check_dmesg "dmesg clean"
finish
