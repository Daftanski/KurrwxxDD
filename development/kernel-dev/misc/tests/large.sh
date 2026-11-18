#!/bin/bash
# Usage: large.sh [ports...]   Pings of 1472/4000/8000 bytes both ways per port (default 0): IP fragments at MTU 1500; no BUG/ixd error (e.g. "hw csum failure") in dmesg. Needs: ixd.sh done, ports not in a bridge. Changes: ports (restored). Time: ~30 s/port.
. "$(dirname "$0")/../lib.sh"
PORTS=${*:-0}
guest_need
dmesg_mark

for P in $PORTS; do
    port_up $P || continue
    for S in 1472 4000 8000; do
        check "port $P guest->host $S" "$(guest_ping $P 3 -s $S)" " [23] received"
        check "port $P host->guest $S" "$(host_ping $P 3 -s $S)" " [23] received"
    done
    port_down $P
done

check_dmesg "dmesg clean"
finish
