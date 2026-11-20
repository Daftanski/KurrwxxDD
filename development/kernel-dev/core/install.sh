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

# --- Step 2b: driver selftests (build-kselftest.sh) to /kselftest ------------
# $MOUNT/root is the guest's / (guest root's home is /home/root). Old ones are
# removed: selftests of another kernel must not stay in the image.
KSFT_ARCHIVE=$DEV/image/kselftest_output.tar.gz
KSFT_DST=$MOUNT/root/kselftest
rm -rf $KSFT_DST
if [ -f $KSFT_ARCHIVE ]; then
    NEED=$(gzip -l $KSFT_ARCHIVE | awk 'NR == 2 { print $2 }')
    FREE=$(df -B1 --output=avail $MOUNT/root | tail -1)
    if [ "$NEED" -gt "$FREE" ]; then
        $DEV/core/umount-image.sh
        echo "ERROR: selftests need $NEED bytes, image root has $FREE free" >&2
        exit 1
    fi
    mkdir -p $KSFT_DST
    tar xzf $KSFT_ARCHIVE --no-same-owner -C $KSFT_DST
    echo "Installed driver selftests in /kselftest"
fi
$DEV/core/umount-image.sh

# --- Step 3: repack the .craff Simics boots from -----------------------------
rm -f $CRAFF
$CRAFF_TOOL -o $CRAFF $WIC
# misc/tests/boot.sh compares this with uname -r / uname -v of the guest.
printf '%s\n%s\n' "$RELEASE" "#${FULL#*#}" > $DEV/image/kernel-version
echo "Installed kernel $RELEASE"
