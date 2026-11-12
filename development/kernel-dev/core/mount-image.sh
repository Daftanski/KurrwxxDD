#!/bin/bash
set -eo pipefail
trap 'echo "ABORT. Error on line $LINENO (exit code $?)"' ERR

DEV=/root/SimicsWorkspace/development/kernel-dev
WIC=$DEV/image/development_disk_image.wic
MOUNT=$DEV/image/image_mount

# The platform has no udev, so loop nodes are never created for us.
modprobe loop || true
for I in 0 1 2 3 4 5 6 7; do
    [ -b /dev/loop$I ] || mknod /dev/loop$I b 7 $I
done

$DEV/core/umount-image.sh

mkdir -p $MOUNT/boot $MOUNT/root
LOOP=$(losetup --find --show $WIC)
kpartx -a $LOOP
PART=/dev/mapper/$(basename $LOOP)
mount ${PART}p1 $MOUNT/boot
mount ${PART}p2 $MOUNT/root
