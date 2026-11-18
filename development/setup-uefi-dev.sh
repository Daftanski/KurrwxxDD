#!/bin/bash
set -eo pipefail
trap 'echo "ABORT. Error on line $LINENO (exit code $?)"' ERR

if [[ -z $1 ]]; then
    echo "Usage: $0 <ip>"
    exit 1
fi

HOST=root@$1
WORKSPACE=$(dirname "$(readlink -f "$0")")
DEV=/root/SimicsWorkspace/development/uefi-dev
SSH_KEY=$HOME/.ssh/id_rsa

[ -f "$SSH_KEY" ] || ssh-keygen -t rsa -b 4096 -N '' -f "$SSH_KEY"

if ! ssh -o BatchMode=yes -o ConnectTimeout=5 "$HOST" true 2> /dev/null; then
    ssh-keygen -R "$1" > /dev/null 2>&1 || true
    echo "Installing ssh key on $HOST, this asks for the password once"
    ssh-copy-id -o StrictHostKeyChecking=accept-new -i "$SSH_KEY.pub" "$HOST"
fi

ssh "$HOST" "mkdir -p $DEV"
# Driver is deployed by EXEC_CNIC_BUILD.sh; do not overwrite it
tar -czf - --exclude=./core/usb-drive/E4999X10.EFI -C "$WORKSPACE/uefi-dev" . | ssh "$HOST" "tar -xzf - --no-same-owner -C $DEV"
echo "uefi-dev copied to $HOST:$DEV"

bash "$(dirname "$0")/setup-artifactory-auth.sh" "$1"
