#!/bin/bash
set -eo pipefail
trap 'echo "ABORT. Error on line $LINENO (exit code $?)"' ERR

DEV=/root/SimicsWorkspace/development/uefi-dev
SIMICS_CMD=$DEV/misc/helpers/execute-simics-cmd.sh
PORT="\"summitville.xhci_generic.usb3_port[$(cat $DEV/core/usb-port 2> /dev/null || echo 3)]\""

if ! pgrep -x simics > /dev/null; then
    echo "ERROR: Simics is not running. Use restart.sh." >&2
    exit 1
fi

# --- Step 1: unplug the old drive; delete fails while still connected --------
$SIMICS_CMD "disconnect cnt0 = usb_drive_id00.connector_usb_host cnt1 = $PORT" \
            "usb_drive_id00.delete" > /dev/null

# --- Step 2: build the USB drive from usb-drive/ -----------------------------
$DEV/core/make-usb-drive.sh

# --- Step 3: plug in the new drive and remap it in the UEFI Shell ------------
$SIMICS_CMD "new-usb3-disk file = $DEV/core/usb-drive.img name = usb_drive_id00" \
            "connect usb_drive_id00.connector_usb_host $PORT" > /dev/null

expect -c 'set timeout 120; spawn telnet localhost 33441; send "\r"; expect -re {Shell>|:\\>};
           send "map -r\r"; expect -re {Shell>|:\\>};
           send "fs1:\r"; expect -re {FS1:\\>};
           send "\035"; expect "telnet>"; send "quit\r"' > /dev/null

echo "USB drive replaced, files are on fs1:."
