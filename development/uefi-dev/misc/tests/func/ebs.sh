#!/bin/bash
# Usage: ebs.sh   ExitBootServices with the driver loaded (nictest ebs): the console stops, Simics and the IMC keep running without assert. Needs: driver loaded. Leaves the guest dead: run restart after it.
. "$(dirname "$0")/../../lib.sh"
IMC=/root/SimicsWorkspace/has-log/imc_serial_console_vm1.log
BEFORE=$(wc -l < $IMC)

uefi_begin
SCRIPT+=' send "nictest.efi ebs\r"; expect "NICTEST ebs go"; after 5000; send "\035"; expect "telnet>"; send "quit\r"'
expect -c "$SCRIPT" > /dev/null 2>&1
sleep 15

# Log lines are written late: look at the UEFI log for the app start.
check "ebs started" "$(tr -d '\r' < $LOG | grep -a -c 'NICTEST ebs go' || true)" "^[1-9]"
check "simics alive" "$($DEV/misc/helpers/execute-simics-cmd.sh 'echo SIMICS-OK' 2>&1 | grep -a -c '^SIMICS-OK' || true)" "^[1-9]"
NEW=$(tail -n +$((BEFORE + 1)) $IMC | grep -a -v 'MNG LOG' || true)
check_eq "IMC asserts after ebs" "$(grep -a -c -i -E 'assert|panic|exception' <<< "$NEW" || true)" 0
echo "INFO IMC lines after ebs: $(grep -a -c . <<< "$NEW" || true)"
finish
