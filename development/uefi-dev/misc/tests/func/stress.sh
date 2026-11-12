#!/bin/bash
# Usage: stress.sh [bind|load|reconnect] [cycles]   Repeat a lifecycle step; each must work, controller open info must not grow, ping at the end. Needs: driver loaded (bind, reconnect) | driver not loaded (load).
. "$(dirname "$0")/../../lib.sh"
MODE=${1:-bind}
CYCLES=${2:-20}
PORTS="0 7"
N=$(wc -w <<< "$ALL_PORTS")

for P in $PORTS; do
    host_setup $P
done

uefi_begin
[ $MODE = load ] && uefi_load
uefi_handles
[ $MODE = load ] && uefi_unload
for C in $(seq 1 $CYCLES); do
    uefi_part $C
    case $MODE in
        bind)      uefi_tcl 'disconnect $c'
                   uefi_cmd "connect -r" ;;
        load)      uefi_load
                   uefi_unload ;;
        # reconnect -r also reconnects the USB drive: map FS1 again.
        reconnect) uefi_cmd "reconnect -r" '(FS1:|Shell>)'
                   uefi_cmd "map -r" '(FS1:|Shell>)'
                   uefi_cmd "fs1:" ;;
    esac
    if [ $MODE != load ]; then
        uefi_tcl 'dh -d $h'
    fi
    uefi_part $C-open
    uefi_tcl 'openinfo $c'
done
uefi_part END
[ $MODE = load ] && uefi_load
for P in $PORTS; do
    uefi_ifconfig $P
    uefi_ping $P 2
done
uefi_end

OUT=$(uefi_log)
# EDK2 SnpDxe never closes its PciIo GET_PROTOCOL: stale entries (blank or dead child handle) per cycle. Not ours.
open_count() { grep -a "Drv\[" <<< "$(log_part "$OUT" $1-open)" | grep -avc 'GetProt .*Simple Network Protocol Driver' || true; }
for C in $(seq 1 $CYCLES); do
    R=$(log_part "$OUT" $C)
    case $MODE in
        bind) check "cycle $C disconnect" "$(grep -a -m1 "Disconnect" <<< "$R" || true)" "Success" ;;
        load) check "cycle $C load" "$(grep -a -m1 "^Image " <<< "$R" || true)" "Success"
              check "cycle $C unload" "$(grep -a -m1 "Unload" <<< "$R" || true)" "Success" ;;
    esac
    if [ $MODE != load ]; then
        check_eq "cycle $C children" "$(child_handles "$R" | wc -l)" $N
    fi
done
check_eq "open info cycle $CYCLES vs 1" "$(open_count $CYCLES)" "$(open_count 1)"
R=$(log_part "$OUT" END)
for P in $PORTS; do
    check "port $P" "$(ping_result "$R" $(host_ip $P))" " 2 received"
done
finish
