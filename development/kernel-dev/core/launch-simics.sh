#!/bin/bash
set -eo pipefail
trap 'echo "ABORT. Error on line $LINENO (exit code $?)"' ERR

DEV=/root/SimicsWorkspace/development/kernel-dev

# Standard launch script. Not modified.
ORIGINAL_LAUNCH=/root/SimicsWorkspace/startup_scripts/vpc_launch.simics

KERNEL_DEV_LAUNCH=$DEV/core/vpc_launch_kernel_dev.simics
KERNEL_DEV_IMAGE=/mnt/image_cache/development_disk_image.craff

if [ ! -e $KERNEL_DEV_IMAGE ]; then
    echo "ERROR: $KERNEL_DEV_IMAGE missing, run core/setup.sh" >&2
    exit 1
fi

# --- Step 1: create the copy with the one changed line ------------------------
# Replace the line   $disk_image = ...   so it points to our dev image.
# All other lines are unchanged.
sed "s|^\( *\)\$disk_image = .*|\1\$disk_image = $KERNEL_DEV_IMAGE|" \
    "$ORIGINAL_LAUNCH" > "$KERNEL_DEV_LAUNCH"

# --- Step 2: start Simics (same as relaunch-simics.sh) ------------------------
mkdir -p $DEV/logs
cd /root/SimicsWorkspace
export DISPLAY=:1
exec ./simics "$KERNEL_DEV_LAUNCH"
