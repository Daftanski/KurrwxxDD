#!/bin/bash
set -eo pipefail
trap 'echo "ABORT. Error on line $LINENO (exit code $?)"' ERR

DEV=/root/SimicsWorkspace/development/kernel-dev
CRAFF_TOOL=/root/SimicsWorkspace/bin/craff
WIC=$DEV/image/development_disk_image.wic
CRAFF=$DEV/image/development_disk_image.craff
MOUNT=$DEV/image/image_mount
OUT=$DEV/image/kernel_output

# --- Step 1: unpack image/kernel_output.tar.gz -------------------------------
rm -rf $OUT
mkdir -p $OUT
tar xzf $DEV/image/kernel_output.tar.gz -C $OUT
# Read from bzImage; lib/modules may hold stale dirs from earlier builds.
# "6.18.1+ (user@host) #3 SMP PREEMPT_DYNAMIC <date>"
FULL=$(file $OUT/arch/x86/boot/bzImage | grep -oP 'version \K[^,]+')
RELEASE=${FULL%% *}

# --- Step 2: copy kernel + modules into the image ----------------------------
$DEV/core/mount-image.sh
cp $OUT/arch/x86/boot/bzImage $MOUNT/boot/bzImage
cp -a $OUT/lib/modules/$RELEASE $MOUNT/root/lib/modules/
depmod -b $MOUNT/root $RELEASE
$DEV/core/umount-image.sh

# --- Step 3: repack the .craff Simics boots from -----------------------------
rm -f $CRAFF
$CRAFF_TOOL -o $CRAFF $WIC
# misc/tests/boot.sh compares this with uname -r / uname -v of the guest.
printf '%s\n%s\n' "$RELEASE" "#${FULL#*#}" > $DEV/image/kernel-version
echo "Installed kernel $RELEASE"
