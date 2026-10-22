#!/bin/bash

set -eo pipefail
trap 'echo "ABORT. Error on line $LINENO (exit code $?)"' ERR

WORKSPACE=/root/SimicsWorkspace/development
USB_DRIVE_IMG=$WORKSPACE/usb-drive.img
USB_DRIVE_SRC=$WORKSPACE/usb-drive

command -v mcopy > /dev/null || dnf install -y mtools
command -v mkfs.vfat > /dev/null || dnf install -y dosfstools

dd if=/dev/zero of=$USB_DRIVE_IMG bs=1M count=32
mkfs.vfat $USB_DRIVE_IMG

mcopy -i $USB_DRIVE_IMG -s $USB_DRIVE_SRC/* ::/
