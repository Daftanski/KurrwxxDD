#!/bin/bash
# Usage: build.sh <edk2 dir>   Runs on the dev machine. Builds core/usb-drive/pxeboot.efi.
# edk2 dir needs built BaseTools, e.g. networking.ipu.tools/boot/uefi/nic-core/edk2.
set -eo pipefail
trap 'echo "ABORT. Error on line $LINENO (exit code $?)"' ERR

if [[ -z $1 ]]; then
    echo "Usage: $0 <edk2 dir>"
    exit 1
fi

APP=$(dirname "$(readlink -f "$0")")
EDK2=$(readlink -f "$1")
OUT=$APP/../../../core/usb-drive/pxeboot.efi

export WORKSPACE=/tmp/pxeboot-build
export PACKAGES_PATH=$EDK2:$APP
export EDK_TOOLS_PATH=$EDK2/BaseTools
export PYTHON_COMMAND=python3
mkdir -p $WORKSPACE/Conf
cd $WORKSPACE
# edksetup.sh reads the script arguments.
set --
. $EDK2/edksetup.sh > /dev/null

build -a X64 -t GCC5 -b RELEASE -p PxeBootPkg/PxeBootPkg.dsc --silent
cp $WORKSPACE/Build/PxeBootPkg/RELEASE_GCC5/X64/PxeBoot.efi "$OUT"
echo "Built $(readlink -f "$OUT")"
