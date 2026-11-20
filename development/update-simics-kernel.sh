#!/bin/bash
set -eo pipefail
trap 'echo "ABORT. Error on line $LINENO (exit code $?)"' ERR

if [[ -z ${1:-} ]]; then
    echo "Usage: [JOBS=<n>] [KSFT_TARGETS=\"...\"] $0 <ip>   (KSFT_TARGETS=\"\": no selftests)"
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
make -j"${JOBS:-$(nproc)}"

rm -rf "$MODULES"
make modules_install INSTALL_MOD_PATH="$MODULES"

rm -f "$ARCHIVE"
tar czf "$ARCHIVE" arch/x86/boot/bzImage -C "$MODULES" lib/modules

echo "Sending $ARCHIVE to $SIMICS_HOST:$DEV/image"
scp "$ARCHIVE" "$SIMICS_HOST:$DEV/image/"

# Driver selftests from this same tree, so they match the kernel (KSFT_TARGETS="" skips them).
if [ -n "${KSFT_TARGETS-x}" ]; then
    "$SCRIPT/build-kselftest.sh" "$1"
else
    ssh "$SIMICS_HOST" "rm -f $DEV/image/kselftest_output.tar.gz"
fi

# Install + restart touch the running Simics: only inside a LAVA job (queued).
echo "Copied. Install and test through LAVA, e.g.:"
echo "  ~/lava/svl/lava-test.sh kernel <tag> install boot ixd"
