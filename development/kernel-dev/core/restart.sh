#!/bin/bash
set -eo pipefail
trap 'echo "ABORT. Error on line $LINENO (exit code $?)"' ERR

DEV=/root/SimicsWorkspace/development/kernel-dev
LOGS=$DEV/logs

# --- Step 1: stop old Simics; only one can run at a time (shared TAP devices)
killall -9 simics 2> /dev/null || true
while pgrep -x simics > /dev/null; do sleep 1; done

# --- Step 2: boot Simics with the dev image in the background -----------------
# setsid: Simics keeps running after this script (and an ssh session) ends.
mkdir -p $LOGS
setsid $DEV/core/launch-simics.sh < /dev/null > $LOGS/simics_console.log 2>&1 &

echo "Simics started with the dev kernel. VNC :1, log: $LOGS/simics_console.log"
