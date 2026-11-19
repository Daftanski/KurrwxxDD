#!/bin/bash
set -eo pipefail
trap 'echo "ABORT. Error on line $LINENO (exit code $?)"' ERR

export PATH=$PATH:/root/.local/bin

DEV=/root/SimicsWorkspace/development/uefi-dev
USB_DRIVE_IMG=$DEV/core/usb-drive.img
USB_DRIVE_SRC=$DEV/core/usb-drive

command -v mcopy > /dev/null || dnf install -y mtools
command -v mkfs.vfat > /dev/null || dnf install -y dosfstools

dd if=/dev/zero of=$USB_DRIVE_IMG bs=1M count=${USB_MB:-256}
mkfs.vfat $USB_DRIVE_IMG

mcopy -i $USB_DRIVE_IMG -s $USB_DRIVE_SRC/* ::/
