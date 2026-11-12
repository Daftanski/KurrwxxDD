#!/bin/bash
# Usage: foreign-mac.sh [ports...]   Unicast to a foreign MAC must be dropped. Needs: ping.sh done.
. "$(dirname "$0")/../../lib.sh"
PORTS=${*:-2}

for P in $PORTS; do
    ip neigh replace $(uefi_ip $P) lladdr 02:00:00:00:00:99 dev $(tap $P) nud permanent
    check "port $P foreign MAC" "$(host_ping $P $(uefi_ip $P) 3)" " 0 received"

    ip neigh del $(uefi_ip $P) dev $(tap $P)
    check "port $P own MAC" "$(host_ping $P $(uefi_ip $P) 3)" " 3 received"
done
finish
