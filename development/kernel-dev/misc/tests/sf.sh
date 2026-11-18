#!/bin/bash
# Usage: sf.sh [port] [sfnum]   On the PF of port P (default 0, sfnum 90+P): devlink port add pcisf -> representor; state active -> attached, aux ixd.sf.* + SF netdev appear, SF netdev up; delete -> all gone. Needs: ixd.sh done, eswitch switchdev. Changes: driver (one SF added and removed). Time: ~2 min (estimate, not run yet).
. "$(dirname "$0")/../lib.sh"
P=${1:-0}
SFN=${2:-$((90 + P))}
guest_need
dmesg_mark

D=$(guest_dev $P)
[ -n "$D" ] || { echo "FAIL port $P netdev (no netdev with MAC $(mac $P))"; exit 1; }
PCI=$(g "basename \$(readlink -f /sys/class/net/$D/device)")
PF=${PCI##*.}
check_eq "port $P eswitch (pci/$PCI)" "$(g "devlink dev eswitch show pci/$PCI" | grep -oP 'mode \K\S+' || true)" switchdev
[ $FAILS = 0 ] || finish

aux_count() { g "ls /sys/bus/auxiliary/devices" | grep -c '^ixd\.sf\.' || true; }
AUX0=$(aux_count)
NET0=$(g "ls /sys/class/net" | tr '\n' ' ')

# Remove the SF on any exit (a FAIL in the middle must not leave it behind).
PORT=""
cleanup() {
    [ -n "$PORT" ] || return 0
    g "devlink port function set $PORT state inactive 2> /dev/null; devlink port del $PORT 2> /dev/null" || true
    PORT=""
}
trap cleanup EXIT

# --- Add: "pci/<pf>/<idx>: type eth netdev <repr> flavour pcisf ..." -----------
OUT=$(g "devlink port add pci/$PCI flavour pcisf pfnum $PF sfnum $SFN 2>&1" || true)
PORT=$(head -1 <<< "$OUT" | grep -oP '^pci/\S+(?=:)' || true)
REPR=$(head -1 <<< "$OUT" | grep -oP ' netdev \K\S+' || true)
check "sf $SFN port added" "${PORT:-none: $OUT}" "^pci/"
[ -n "$PORT" ] || finish
check "sf $SFN representor" "${REPR:-none}" "^[a-z]"
check "sf $SFN inactive" "$(g "devlink port show $PORT" | grep -oE 'state \S+ opstate \S+' || true)" "state inactive"

# --- Activate: aux device + SF netdev appear ----------------------------------
g "devlink port function set $PORT state active" || true
for S in $(seq 60); do
    SFD=$(g "ls /sys/class/net" | grep -vxF -e "$REPR" $(printf -- '-e %s ' $NET0) || true)
    [ -n "$SFD" ] && break
    sleep 1
done
check "sf $SFN active" "$(g "devlink port show $PORT" | grep -oE 'state \S+ opstate \S+' || true)" "state active opstate attached"
check_eq "sf $SFN aux devices" "$(aux_count)" $((AUX0 + 1))
check "sf $SFN netdev" "${SFD:-none}" "^[a-z][^ ]*$"
if [ -n "$SFD" ]; then
    g "ip link set $SFD up" || true
    check "sf $SFN netdev up" "$(g "ip -o link show dev $SFD" | grep -oE '<[^>]*>' || true)" "[<,]UP[,>]"
fi

# --- Delete: everything gone --------------------------------------------------
g "devlink port function set $PORT state inactive" || true
check "sf $SFN deleted" "$(g "devlink port del $PORT 2>&1; echo rc=\$?" | tr '\n' ' ')" "rc=0 $"
PORT=""
for S in $(seq 60); do
    [ "$(aux_count)" = $AUX0 ] && break
    sleep 1
done
check_eq "sf $SFN aux devices after del" "$(aux_count)" $AUX0
check_eq "sf $SFN netdevs after del" "$(g "ls /sys/class/net" | tr '\n' ' ')" "$NET0"

check_dmesg "dmesg clean"
finish
