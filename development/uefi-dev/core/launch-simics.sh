#!/bin/bash
set -eo pipefail
trap 'echo "ABORT. Error on line $LINENO (exit code $?)"' ERR

DEV=/root/SimicsWorkspace/development/uefi-dev

# Standard launch script. Not modified.
ORIGINAL_LAUNCH=/root/SimicsWorkspace/startup_scripts/vpc_launch.simics

UEFI_DEV_LAUNCH=$DEV/core/vpc_launch_uefi_dev.simics
UEFI_DEV_PRE_WA=$DEV/core/pre-wa-uefi-dev.simics
UEFI_DEV_POST_WA=$DEV/core/post-wa-uefi-dev.simics

# --- Step 1: create the copy with the two changed lines -----------------------
# Replace the lines starting with   $pre_wa_script=   and   $post_wa_script=
# so they point to our scripts in development/uefi-dev/core/. All other lines are unchanged.
sed -e "s|^\$pre_wa_script=.*|\$pre_wa_script=\"$UEFI_DEV_PRE_WA\"|" \
    -e "s|^\$post_wa_script=.*|\$post_wa_script=\"$UEFI_DEV_POST_WA\"|" \
    -e "/^\$pfp=/d" \
    "$ORIGINAL_LAUNCH" > "$UEFI_DEV_LAUNCH"

# --- Step 2: start Simics (same as relaunch-simics.sh) ------------------------
mkdir -p $DEV/logs
# Tests read this to know the board mode (PFP ports have other MACs).
echo "${PFP:-FALSE}" > $DEV/logs/pfp
# USB port of our drive; the port order decides if it is fs1:. Host specific.
USB_PORT=$(cat $DEV/core/usb-port 2> /dev/null || echo 3)
cd /root/SimicsWorkspace
export DISPLAY=:1
# PFP=TRUE boots board 10002 (PFP mode), same as restart_simulation.sh TRUE.
exec ./simics -e "\$pfp = ${PFP:-FALSE}" -e "\$usb_port = $USB_PORT" "$UEFI_DEV_LAUNCH"
