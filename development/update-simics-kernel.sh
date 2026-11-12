#!/bin/bash
set -eo pipefail
trap 'echo "ABORT. Error on line $LINENO (exit code $?)"' ERR

if [[ -z ${1:-} ]]; then
    echo "Usage: $0 <ip>"
    exit 1
fi

SIMICS_HOST=root@$1
SCRIPT=$(dirname "$(readlink -f "$0")")
KERNEL=$(pwd)
MODULES=$KERNEL/target_modules
ARCHIVE=$KERNEL/kernel_output.tar.gz
DEV=/root/SimicsWorkspace/development/kernel-dev

(
    cd "$SCRIPT"
    ./setup-kernel-dev.sh "$1"
)

echo "Fetching kernel config from $SIMICS_HOST"
ssh "$SIMICS_HOST" "$DEV/core/config.sh" > "$KERNEL/.config"

make olddefconfig
make -j"$(nproc)"

rm -rf "$MODULES"
make modules_install INSTALL_MOD_PATH="$MODULES"

rm -f "$ARCHIVE"
tar czf "$ARCHIVE" arch/x86/boot/bzImage -C "$MODULES" lib/modules

echo "Sending $ARCHIVE to $SIMICS_HOST:$DEV/image"
scp "$ARCHIVE" "$SIMICS_HOST:$DEV/image/"

ssh "$SIMICS_HOST" "$DEV/core/install.sh"

ssh "$SIMICS_HOST" "$DEV/core/restart.sh"
