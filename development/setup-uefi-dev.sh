#!/bin/bash
set -eo pipefail
trap 'echo "ABORT. Error on line $LINENO (exit code $?)"' ERR

if [[ -z $1 ]]; then
    echo "Usage: $0 <ip>"
    exit 1
fi

HOST=root@$1
WORKSPACE=$(pwd)
DEV=/root/SimicsWorkspace/development/uefi-dev

ssh "$HOST" "mkdir -p $DEV"
# Driver is deployed by EXEC_CNIC_BUILD.sh; do not overwrite it
tar -czf - --exclude=./core/usb-drive/E4999X10.EFI -C "$WORKSPACE/uefi-dev" . | ssh "$HOST" "tar -xzf - --no-same-owner -C $DEV"
echo "uefi-dev copied to $HOST:$DEV"
