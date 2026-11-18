#!/bin/bash
# Usage: ixd.sh   ixd loaded, PF count fits PFD/PFP, 8 physical devlink ports, one netdev per port (by MAC), no ixd errors in dmesg. Needs: boot.sh done.
. "$(dirname "$0")/../lib.sh"
guest_need

check_eq "ixd loaded" "$(g "lsmod" | grep -c '^ixd ' || true)" 1

# PFD: 1 PF, 8 aux ports. PFP: 8 PFs, 1 aux port each.
WANT=1
[ "$PFP" = TRUE ] && WANT=8
check_eq "PFs on ixd (PFP=$PFP)" "$(g "ls /sys/bus/pci/drivers/ixd" | grep -c ':' || true)" $WANT

DL=$(g "devlink port show" || true)
check_eq "devlink physical ports" "$(grep -c 'flavour physical' <<< "$DL" || true)" 8

# Each port: netdev with the port MAC, and devlink says it is physical port P.
for P in $ALL_PORTS; do
    D=$(guest_dev $P)
    check "port $P netdev" "${D:-none} $(mac $P)" "^eth[0-9]+ "
    [ -n "$D" ] || continue
    check "port $P devlink" "$(grep -oE "netdev $D flavour physical port [0-9]+" <<< "$DL" || echo none)" "port $P\$"
done

ERR=$(g "dmesg" | grep -i ixd | grep -i -E "error|fail|timeout" | head -5 || true)
check_eq "dmesg ixd errors" "$(echo -n "$ERR" | grep -c . || true)" 0
[ -z "$ERR" ] || echo "$ERR"

finish
