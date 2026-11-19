#!/bin/bash
set -eo pipefail
trap 'echo "ABORT. Error on line $LINENO (exit code $?)"' ERR

DEV=/root/SimicsWorkspace/development/kernel-dev

# stdout is the .config, so everything else goes to stderr
$DEV/core/mount-image.sh >&2
cat $DEV/image/image_mount/root/boot/config-*
$DEV/core/umount-image.sh >&2
