#!/bin/bash
set -eo pipefail
trap 'echo "ABORT. Error on line $LINENO (exit code $?)"' ERR

DEV=/root/SimicsWorkspace/development/kernel-dev
WIC=$DEV/image/development_disk_image.wic
MOUNT=$DEV/image/image_mount

for D in boot root; do
    while mountpoint -q $MOUNT/$D; do
        umount $MOUNT/$D
    done
done

for LOOP in $(losetup --associated $WIC --output NAME --noheadings); do
    kpartx -d $LOOP
    losetup -d $LOOP
done
