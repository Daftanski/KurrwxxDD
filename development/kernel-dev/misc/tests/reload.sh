#!/bin/bash
# Usage: reload.sh [n]   rmmod ixd + modprobe ixd n times (default 1); after each: 8 physical ports back within 5 min, ixd.sh checks pass, no BUG/ixd error in dmesg. Needs: ixd.sh done, no SFs/bridges on ixd (refuses, FORCE=1 overrides). Changes: driver (all ixd netdevs re-created). Time: ~3 min/cycle (estimate, not run yet).
. "$(dirname "$0")/../lib.sh"
N=${1:-1}
guest_need

# Do not destroy someone's setup (set-multi.sh: SFs + bridges).
SFS=$(g "devlink port show" | grep -c 'flavour pcisf' || true)
if [ "$SFS" != 0 ] && [ "$FORCE" != 1 ]; then
    echo "FAIL ixd free ($SFS SF ports exist; restart first or FORCE=1)"
    exit 1
fi
dmesg_mark

for I in $(seq $N); do
    check "cycle $I rmmod" "$(g "rmmod ixd 2>&1; echo rc=\$?" | tr '\n' ' ')" "rc=0 $"
    check_eq "cycle $I ixd gone" "$(g "lsmod" | grep -c '^ixd ' || true)" 0
    check "cycle $I modprobe" "$(g "modprobe ixd 2>&1; echo rc=\$?" | tr '\n' ' ')" "rc=0 $"

    for S in $(seq 60); do
        PORTS=$(g "devlink port show" | grep -c 'flavour physical' || true)
        [ "$PORTS" = 8 ] && break
        sleep 5
    done
    check_eq "cycle $I physical ports" "$PORTS" 8

    if "$(dirname "$0")/ixd.sh" > /tmp/reload-ixd.log; then :; else FAILS=$((FAILS + 1)); fi
    sed -n "s/^\(PASS\|FAIL\) /\1 cycle $I ixd: /p" /tmp/reload-ixd.log
done

check_dmesg "dmesg clean"
finish
