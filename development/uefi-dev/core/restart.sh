#!/bin/bash
set -eo pipefail
trap 'echo "ABORT. Error on line $LINENO (exit code $?)"' ERR

DEV=/root/SimicsWorkspace/development/uefi-dev
LOGS=$DEV/logs
TIMEOUT=1800 # seconds

# --- Step 1: stop old Simics; only one can run at a time (shared TAP devices)
killall -9 simics 2> /dev/null || true
while pgrep -x simics > /dev/null; do sleep 1; done

# --- Step 2: build the USB drive from usb-drive/ -----------------------------
$DEV/core/make-usb-drive.sh

# --- Step 3: boot Simics in the background and wait for the UEFI Shell -------
# setsid: Simics keeps running after this script (and an ssh session) ends.
mkdir -p $LOGS
rm -f $LOGS/uefi_serial.log
setsid $DEV/core/launch-simics.sh < /dev/null > $LOGS/simics_console.log 2>&1 &
SIMICS_PID=$!

SECONDS=0
until grep -aq "Shell>" $LOGS/uefi_serial.log 2> /dev/null; do
    if ! kill -0 $SIMICS_PID 2> /dev/null || (( SECONDS >= TIMEOUT )); then
        echo "ERROR: UEFI Shell not reached (Simics died or timeout ${TIMEOUT}s). See $LOGS/" >&2
        exit 1
    fi
    sleep 5
done

echo "UEFI Shell is up, files are on fs1:. Connect: telnet localhost 33441"
