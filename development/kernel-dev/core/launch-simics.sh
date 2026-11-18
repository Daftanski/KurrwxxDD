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

# --- Step 1: create the copy with the changed lines ---------------------------
# Replace the line   $disk_image = ...   so it points to our dev image.
# PFP=TRUE|FALSE set: delete the hard   $pfp=   line, Simics gets it with -e.
# All other lines are unchanged.
SED=(-e "s|^\( *\)\$disk_image = .*|\1\$disk_image = $KERNEL_DEV_IMAGE|")
ARGS=()
if [ -n "$PFP" ]; then
    SED+=(-e "/^\$pfp *=/d")
    ARGS=(-e "\$pfp = $PFP")
else
    # Not set: the host's own value (1/TRUE = PFP).
    PFP=$(grep -oP '^\$pfp *= *\K\S+' "$ORIGINAL_LAUNCH" || true)
    [[ $PFP == 1 || $PFP == TRUE ]] && PFP=TRUE || PFP=FALSE
fi
sed "${SED[@]}" "$ORIGINAL_LAUNCH" > "$KERNEL_DEV_LAUNCH"

# --- Step 2: start Simics (same as relaunch-simics.sh) ------------------------
mkdir -p $DEV/logs
# Tests read this to know the board mode (PF count, port MACs).
echo "$PFP" > $DEV/logs/pfp
cd /root/SimicsWorkspace
export DISPLAY=:1
exec ./simics "${ARGS[@]}" "$KERNEL_DEV_LAUNCH"
