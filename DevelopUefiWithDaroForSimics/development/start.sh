#!/bin/bash
set -e

DEVELOPMENT=/root/SimicsWorkspace/development

# Standard launch script (the one relaunch-simics.sh uses). Not modified.
ORIGINAL_LAUNCH=/root/SimicsWorkspace/new_simics_scripts/vpc_launch.simics

UEFI_DEV_LAUNCH=$DEVELOPMENT/vpc_launch_uefi_dev.simics
UEFI_DEV_PRE_WA=$DEVELOPMENT/pre-wa-uefi-dev.simics
UEFI_DEV_POST_WA=$DEVELOPMENT/post-wa-uefi-dev.simics

# --- Step 1: make sure the standard launch script exists ----------------------
if [ ! -f "$ORIGINAL_LAUNCH" ]; then
    echo "ERROR: Launch script not found: $ORIGINAL_LAUNCH"
    exit 1
fi

# --- Step 2: create the copy with the two changed lines -----------------------
# Replace the lines starting with   $pre_wa_script=   and   $post_wa_script=
# so they point to our scripts in development/. All other lines are unchanged.
sed -e "s|^\$pre_wa_script=.*|\$pre_wa_script=\"$UEFI_DEV_PRE_WA\"|" \
    -e "s|^\$post_wa_script=.*|\$post_wa_script=\"$UEFI_DEV_POST_WA\"|" \
    "$ORIGINAL_LAUNCH" > "$UEFI_DEV_LAUNCH"
echo "Created $UEFI_DEV_LAUNCH"

# --- Step 3: start Simics (same as relaunch-simics.sh) ------------------------
cd /root/SimicsWorkspace
export DISPLAY=:1
exec ./simics "$UEFI_DEV_LAUNCH"
