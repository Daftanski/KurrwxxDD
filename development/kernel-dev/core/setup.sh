#!/bin/bash
set -eo pipefail
trap 'echo "ABORT. Error on line $LINENO (exit code $?)"' ERR

DEV=/root/SimicsWorkspace/development/kernel-dev
SIMICS=/root/SimicsWorkspace
CRAFF_TOOL=$SIMICS/bin/craff
CRAFF_SRC=$SIMICS/CRAFF
IMAGE_CACHE=/mnt/image_cache
WIC=$DEV/image/development_disk_image.wic
CRAFF=$DEV/image/development_disk_image.craff

# --- Step 1: make the dev image from the CI image (once, ~15 GB) -------------
mkdir -p $DEV/image
if [ ! -f $WIC ]; then
    CI_CRAFF=$CRAFF_SRC/$(grep -oE '[^ /]+\.craff' $SIMICS/vm1.sh)
    $CRAFF_TOOL -d -o $WIC $CI_CRAFF
fi
[ -f $CRAFF ] || $CRAFF_TOOL -o $CRAFF $WIC

# --- Step 2: link all images into /mnt/image_cache ---------------------------
# It ships as a symlink to the read-only CRAFF dir and every CI run restores it.
rm -rf $IMAGE_CACHE
mkdir -p $IMAGE_CACHE
ln -sf $CRAFF_SRC/*.craff $IMAGE_CACHE/
ln -sf $CRAFF $IMAGE_CACHE/
