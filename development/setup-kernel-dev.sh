#!/bin/bash
set -eo pipefail
trap 'echo "ABORT. Error on line $LINENO (exit code $?)"' ERR

if [[ -z ${1:-} ]]; then
    echo "Usage: $0 <ip>"
    exit 1
fi

HOST=root@$1
WORKSPACE=$(pwd)
DEV=/root/SimicsWorkspace/development/kernel-dev
SSH_KEY=$HOME/.ssh/id_rsa

[ -f "$SSH_KEY" ] || ssh-keygen -t rsa -b 4096 -N '' -f "$SSH_KEY"

if ! ssh -o BatchMode=yes -o ConnectTimeout=5 "$HOST" true 2> /dev/null; then
    ssh-keygen -R "$1" > /dev/null 2>&1 || true
    echo "Installing ssh key on $HOST, this asks for the password once"
    ssh-copy-id -o StrictHostKeyChecking=accept-new -i "$SSH_KEY.pub" "$HOST"
fi

ssh "$HOST" "mkdir -p $DEV"
tar -czf - -C "$WORKSPACE/kernel-dev" . | ssh "$HOST" "tar -xzf - --no-same-owner -C $DEV"
echo "kernel-dev copied to $HOST:$DEV"

ssh "$HOST" "$DEV/core/setup.sh"
