#!/bin/bash
# -----------------------------------------------------------------------------
# reboot.sh - cold boot Simics to the UEFI Shell with the USB drive attached.
#
# Usage: put your files into development/usb-drive/, then run reboot.sh
#
# What it does:
#   1. Stops any running Simics (every boot is a fresh cold boot).
#   2. Builds the USB drive from development/usb-drive/ (make-usb-drive.sh).
#   3. Starts Simics in the background and waits until the UEFI Shell is up.
#   Then the files are on fs1: and Simics keeps running for manual work.
#
# UEFI serial console log: /root/SimicsWorkspace/development/logs/uefi_serial_vm1.log
# Exit code: 0 = UEFI Shell is up, 1 = Simics died or timeout.
# -----------------------------------------------------------------------------
set -e

DEVELOPMENT=/root/SimicsWorkspace/development
LOGS=$DEVELOPMENT/logs
TIMEOUT=1800    # seconds

# --- Step 1: stop old Simics; only one can run at a time (shared TAP devices)
killall -9 simics 2> /dev/null || true
while pgrep -x simics > /dev/null; do sleep 1; done

# --- Step 2: build the USB drive from usb-drive/ -----------------------------
$DEVELOPMENT/make-usb-drive.sh > /dev/null 2>&1

# --- Step 3: boot Simics in the background and wait for the UEFI Shell -------
# setsid: Simics keeps running after this script (and an ssh session) ends.
mkdir -p $LOGS
rm -f $LOGS/uefi_serial_vm1.log
setsid $DEVELOPMENT/start.sh < /dev/null > $LOGS/simics_console.log 2>&1 &
SIMICS_PID=$!

SECONDS=0
until grep -aq "Shell>" $LOGS/uefi_serial_vm1.log 2> /dev/null; do
    if ! kill -0 $SIMICS_PID 2> /dev/null || (( SECONDS >= TIMEOUT )); then
        echo "ERROR: UEFI Shell not reached (Simics died or timeout ${TIMEOUT}s). See $LOGS/" >&2
        exit 1
    fi
    sleep 5
done
echo "UEFI Shell is up, files are on fs1:. Connect: telnet localhost 33441"
