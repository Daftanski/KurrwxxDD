#!/bin/bash
# Usage: build.sh <edk2 dir>   Runs on the dev machine. Builds edk2 ShellPkg network tools into core/usb-drive/:
#   tftp.efi, http.efi   standalone apps, same args as the tftp/http shell commands
#   shell.efi            full shell with ping6/ifconfig6; run e.g. "shell.efi -nostartup -exit ifconfig6 -l"
set -eo pipefail
trap 'echo "ABORT. Error on line $LINENO (exit code $?)"' ERR

if [[ -z $1 ]]; then
    echo "Usage: $0 <edk2 dir>"
    exit 1
fi

EDK2=$(readlink -f "$1")
USB=$(dirname "$(readlink -f "$0")")/../../../core/usb-drive
OUT=/tmp/netcmds-build/Build/Shell/RELEASE_GCC5/X64

export WORKSPACE=/tmp/netcmds-build
export PACKAGES_PATH=$EDK2
export EDK_TOOLS_PATH=$EDK2/BaseTools
export PYTHON_COMMAND=python3
mkdir -p $WORKSPACE/Conf
cd $WORKSPACE
# edksetup.sh reads the script arguments.
set --
. $EDK2/edksetup.sh > /dev/null

build -a X64 -t GCC5 -b RELEASE -p ShellPkg/ShellPkg.dsc --silent
cp $OUT/tftp.efi $USB/tftp.efi
cp $OUT/http.efi $USB/http.efi
# Full shell variant (ShellPkg.dsc FILE_GUID override).
cp $OUT/Shell_EA4BB293-2D7F-4456-A681-1F22F42CD0BC.efi $USB/shell.efi
echo "Built tftp.efi http.efi shell.efi in $(readlink -f $USB)"
