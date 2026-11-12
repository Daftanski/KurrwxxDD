#!/bin/bash
# Usage: leak.sh [mode] [cycles] [max pages]   Cycles must not lose free memory (memmap).
#   full  load + unload             Needs: driver not loaded.
#   nc    load -nc + unload         entry point / Unload only. Needs: driver not loaded.
#   ncc   load -nc + connect -r + unload   like full, connect done by "connect". Needs: driver not loaded.
#   nccn  load -nc + connect (not -r) + unload   no network stack on children. Needs: driver not loaded.
#   bind  disconnect + connect -r   Start / Stop only. Needs: driver loaded.
#   bindh bind + "drivers" + "dh -d" each cycle (Shell handle commands). Needs: driver loaded.
#   stage load -nc, (connect -r, disconnect) x2, unload; memmap after each step. Needs: driver not loaded.
. "$(dirname "$0")/../../lib.sh"
MODE=${1:-full}
CYCLES=${2:-5}
MAX=${3:-16}

uefi_begin
# Control: same Shell commands without the driver, to see Shell's own use.
for C in $(seq 1 $CYCLES); do
    uefi_part ctl$C
    uefi_cmd "ver"
    uefi_cmd "ver"
    uefi_cmd "memmap"
done
uefi_part 0
uefi_cmd "memmap"
STEPS="load start1 stop1 start2 stop2"
[[ $MODE = bind* ]] && uefi_handles
for C in $(seq 1 $CYCLES); do
    if [ $MODE = stage ]; then
        uefi_part $C-load
        uefi_cmd "load -nc $DRIVER" 'Image.*FS1:'
        uefi_cmd "memmap"
        for N in 1 2; do
            uefi_part $C-start$N
            uefi_cmd "connect -r"
            uefi_cmd "memmap"
            [ $N = 1 ] && uefi_handles
            uefi_part $C-stop$N
            uefi_each_ctrl 'disconnect $c'
            uefi_cmd "memmap"
        done
    fi
    uefi_part $C
    case $MODE in
        full) uefi_load
              uefi_unload ;;
        nc)   uefi_cmd "load -nc $DRIVER" 'Image.*FS1:'
              uefi_unload ;;
        ncc)  uefi_cmd "load -nc $DRIVER" 'Image.*FS1:'
              uefi_cmd "connect -r"
              uefi_unload ;;
        nccn) uefi_cmd "load -nc $DRIVER" 'Image.*FS1:'
              uefi_cmd "connect"
              uefi_unload ;;
        stage) uefi_unload ;;
        bindh) uefi_each_ctrl 'disconnect $c'
              uefi_cmd "connect -r"
              uefi_handles ;;
        bind) uefi_each_ctrl 'disconnect $c'
              uefi_cmd "connect -r" ;;
    esac
    uefi_cmd "memmap"
done
uefi_part END
uefi_end

OUT=$(uefi_log)
free_pages() { grep -a -m1 "^ *Available *:" <<< "$(log_part "$OUT" $1)" | awk '{ print $3 }' | tr -d ',' || true; }
A0=$(free_pages 0)
A1=$(free_pages 1)
AN=$(free_pages $CYCLES)
CTL=$(( $(free_pages ctl1) - $(free_pages ctl$CYCLES) ))
for C in $(seq 1 $CYCLES); do
    R=$(grep -a -m1 -E "(Unload|Disconnect) - " <<< "$(log_part "$OUT" $C)" || true)
    check "cycle $C $MODE" "$R" "Success"
    echo "INFO cycle $C: $(( $(free_pages $((C - 1))) - $(free_pages $C) )) pages"
    if [ $MODE = stage ]; then
        P=$((C - 1))
        S=""
        for T in $STEPS; do
            S+=" $T $(( $(free_pages $P) - $(free_pages $C-$T) ))"
            P=$C-$T
        done
        echo "INFO cycle $C steps:$S unload $(( $(free_pages $P) - $(free_pages $C) ))"
    fi
done
echo "INFO first cycle: $((A0 - A1)) pages not freed"
echo "INFO control (no driver), cycles 2..$CYCLES: $CTL pages"
check_le "cycles 2..$CYCLES pages lost (minus control)" "$((A1 - AN - CTL))" $MAX
finish
