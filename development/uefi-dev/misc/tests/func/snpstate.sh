#!/bin/bash
# Usage: snpstate.sh   SNP state machine on every child (nictest snpstate): wrong-state calls fail, double Start/Stop fail, reinitialize cycles work, state restored and ports ping; then Stop left on every child and the driver reconnected: ports ping. Needs: driver loaded, nictest.efi.
. "$(dirname "$0")/../../lib.sh"
N=$(wc -w <<< "$ALL_PORTS")

for P in $ALL_PORTS; do
    host_setup $P
done

uefi_begin
uefi_handles
for P in $ALL_PORTS; do
    uefi_ifconfig $P
done
uefi_part st
uefi_cmd "nictest.efi snpstate" 'NICTEST done.*FS1:'
uefi_part ping
for P in $ALL_PORTS; do
    uefi_ping $P 2
done
uefi_part stop
uefi_cmd "nictest.efi snpstate stop" 'NICTEST done.*FS1:'
uefi_part back
uefi_each_ctrl 'disconnect $c'
uefi_cmd "connect -r"
uefi_tcl 'dh -d $h'
for P in $ALL_PORTS; do
    uefi_ifconfig $P
    uefi_ping $P 2
done
uefi_end

OUT=$(uefi_log)
S=$(log_part "$OUT" st)
# all <label> <op> <regex>: every child matches, at least one line.
all() {
    local L BAD
    L=$(grep -aE "^NICTEST snpst [0-9]+ $2 status" <<< "$S" || true)
    BAD=$(grep -avcE "$3" <<< "$L" || true)
    check "$1" "lines=$(grep -ac . <<< "$L" || true) bad=$BAD" "^lines=[1-9][0-9]* bad=0\$"
}
NOTOK="status=[^S]"
all "children start Initialized" initial "state=2"
all "Start when Initialized" init-start "status=Already started"
all "GetStatus" init-getstatus "status=Success"
all "Transmit too small fails" init-transmit-tiny "$NOTOK"
all "Transmit NULL buffer" init-transmit-null "status=Invalid Parameter"
all "Stop when Initialized fails" init-stop "$NOTOK"
all "Shutdown" shutdown "status=Success state=1"
all "Shutdown when Started fails" shutdown-again "$NOTOK"
all "Initialize from Started" started-initialize-bad "status=Success state=2"
all "Shutdown (2)" shutdown-2 "status=Success state=1"
all "Started: Transmit fails" started-transmit "$NOTOK"
all "Started: Receive fails" started-receive "$NOTOK"
all "Started: Start again" start-again "status=Already started"
all "Stop" stop "status=Success state=0"
for OP in initialize transmit receive getstatus filters station stats shutdown reset stop; do
    all "Stopped: $OP" "stopped-$OP" "status=Not started"
done
all "cycle Start" cycle-start "status=Success state=1"
all "cycle Initialize" cycle-initialize "status=Success state=2"
all "cycle Shutdown" cycle-shutdown "status=Success state=1"
all "cycle Stop" cycle-stop "status=Success state=0"
all "restore Start" restore-start "status=Success state=1"
all "restore Initialize" restore-initialize "status=Success state=2"
echo "INFO Initialize when Initialized: $(grep -a 'snpst [0-9]* init-initialize' <<< "$S" | grep -ao 'status=[A-Za-z ]*' | sort | uniq -c | tr '\n' ' ')"
echo "INFO GetStatus(NULL,NULL): $(grep -a 'snpst [0-9]* init-getstatus-null' <<< "$S" | grep -ao 'status=[A-Za-z ]*' | sort | uniq -c | tr '\n' ' ')"
echo "INFO Reset when Started: $(grep -a 'snpst [0-9]* started-reset' <<< "$S" | grep -ao 'status=[A-Za-z ]*' | sort | uniq -c | tr '\n' ' ')"

R=$(log_part "$OUT" ping)
for P in $ALL_PORTS; do
    check "port $P after restore" "$(ping_result "$R" $(host_ip $P))" " 2 received"
done
R=$(log_part "$OUT" back)
check_eq "children after Stop + reconnect" "$(child_handles "$R" | wc -l)" $N
for P in $ALL_PORTS; do
    check "port $P after Stop + reconnect" "$(ping_result "$R" $(host_ip $P))" " 2 received"
done
finish
