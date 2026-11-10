#!/usr/bin/bash
# Build the kernel and install it into the Simics CI image. Run from the kernel tree root.
set -euo pipefail

KERNEL_DIR=$(pwd)
MODULES_DIR=$KERNEL_DIR/target_modules
ARCHIVE=$KERNEL_DIR/kernel_output.tar.gz

SCRIPT_SRC_FILE=$KERNEL_DIR/simics_dev.sh
SIMICS_HOST=root@${1:?usage: $(basename "$0") <simics_host>}
SIMICS_DIR=/root/SimicsWorkspace/development
SIMICS_SCRIPT=$SIMICS_DIR/simics_dev.sh

# a fresh platform has none of this, and setup is a no-op once it is there
echo "Deploying ${SCRIPT_SRC_FILE} to ${SIMICS_HOST}:${SIMICS_DIR}"
ssh "$SIMICS_HOST" "mkdir -p $SIMICS_DIR"
scp "$SCRIPT_SRC_FILE" "${SIMICS_HOST}:${SIMICS_DIR}/"
ssh "$SIMICS_HOST" "chmod +x $SIMICS_SCRIPT && $SIMICS_SCRIPT setup"

echo "Fetching kernel config from ${SIMICS_HOST}"
ssh "$SIMICS_HOST" "$SIMICS_SCRIPT config" > "$KERNEL_DIR/.config"

make olddefconfig
make -j"$(nproc)"

# stale module trees from earlier builds land in the archive otherwise
rm -rf "$MODULES_DIR"
make modules_install INSTALL_MOD_PATH="$MODULES_DIR"

rm -f "$ARCHIVE"
tar czf "$ARCHIVE" arch/x86/boot/bzImage -C "$MODULES_DIR" lib/modules

echo "Sending ${ARCHIVE} to ${SIMICS_HOST}:${SIMICS_DIR}"
scp "$ARCHIVE" "${SIMICS_HOST}:${SIMICS_DIR}/"

ssh "$SIMICS_HOST" "$SIMICS_SCRIPT install"

echo "Done. Restart Simics on ${SIMICS_HOST} to boot the new kernel."
