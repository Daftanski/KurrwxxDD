#!/bin/bash
# Usage: linux-boot.sh [plain|used|nostack|unloaded]   Boot the Linux on the NVMe disk (grub) after: plain = driver loaded; used = loaded and all ports pinged; nostack = load -nc (no children); unloaded = loaded and unloaded. The EFI stub must not fail in exit_boot(), Linux starts, idpf messages are listed. Needs: fresh boot, driver NOT loaded. Leaves Linux running: restart afterwards.
. "$(dirname "$0")/../../lib.sh"
MODE=${1:-plain}
WAIT=${WAIT:-150}
BOOTFS=${BOOTFS:-fs0}

for P in $ALL_PORTS; do
    host_setup $P
done

uefi_begin
case $MODE in
    nostack)  uefi_cmd "load -nc $DRIVER" 'Image.*FS1:' ;;
    unloaded) uefi_load
              uefi_unload ;;
    *)        uefi_load ;;
esac
if [ $MODE = used ]; then
    for P in $ALL_PORTS; do
        uefi_ifconfig $P
        uefi_ping $P 2
    done
fi
uefi_part boot
SCRIPT+=" send \"$BOOTFS:\\\\EFI\\\\BOOT\\\\BOOTX64.EFI\r\"; after $((WAIT * 1000)); send \"\035\"; expect \"telnet>\"; send \"quit\r\""
expect -c "$SCRIPT" > /dev/null 2>&1
sleep 10

OUT=$(tr -d '\r' < $LOG | sed 's/\x1b\[[0-9;]*[A-Za-z]//g' | sed -n "/^BEGIN-$MARK\$/,\$p")
R=$(log_part "$OUT" boot)
if [ $MODE = used ]; then
    for P in $ALL_PORTS; do
        check "port $P before boot" "$(ping_result "$OUT" $(host_ip $P))" " 2 received"
    done
fi
check_eq "EFI stub exit_boot failed" "$(grep -ac 'exit_boot() failed' <<< "$R" || true)" 0
check "Linux started" "$(grep -a -m1 'Linux version' <<< "$R" | cut -c1-60 || true)" "Linux version"
echo "INFO idpf lines: $(grep -ac 'idpf' <<< "$R" || true), error lines: $(grep -a 'idpf' <<< "$R" | grep -aci -E 'error|fail|timeout' || true)"
grep -a 'idpf' <<< "$R" | head -8 | cut -c1-150 | sed 's/^/INFO /'
finish
