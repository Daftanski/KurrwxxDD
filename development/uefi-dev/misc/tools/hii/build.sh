#!/bin/bash
# Usage: build.sh <hii-test-tool dir>   Runs on the dev machine. Builds core/usb-drive/hii.efi.
# Source: https://github.com/intel-sandbox/hii-test-tool.git. Needs rustup in ~/.cargo (nightly, x86_64-unknown-uefi).
set -eo pipefail
trap 'echo "ABORT. Error on line $LINENO (exit code $?)"' ERR

if [[ -z $1 ]]; then
    echo "Usage: $0 <hii-test-tool dir>"
    exit 1
fi

SRC=$(readlink -f "$1")
OUT=$(dirname "$(readlink -f "$0")")/../../../core/usb-drive/hii.efi
PATCH=$(dirname "$(readlink -f "$0")")/no-exclusive-open.patch

# Upstream opens the port handle EXCLUSIVE: that disconnects SNP/MNP/IP from the port.
if git -C "$SRC" apply --check "$PATCH" 2>/dev/null; then
    git -C "$SRC" apply "$PATCH"
    echo "Applied $PATCH"
fi

. ~/.cargo/env
cd "$SRC"
cargo build --release
cp target/x86_64-unknown-uefi/release/uefi-hii-tool.efi "$OUT"
echo "Built $(readlink -f "$OUT")"
