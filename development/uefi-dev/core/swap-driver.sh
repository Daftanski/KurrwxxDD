#!/bin/bash
set -eo pipefail
trap 'echo "ABORT. Error on line $LINENO (exit code $?)"' ERR

DEV=/root/SimicsWorkspace/development/uefi-dev
DRIVER=${DRIVER:-E4999X10.EFI}

# --- Step 1: put the new usb-drive/ into running Simics ----------------------
$DEV/core/usb-replug.sh

# --- Step 2: unload the old driver (if loaded) and load the new one ----------
# The driver handle is the first column of its "drivers" line (in ANSI colors).
expect -c 'set timeout 120; spawn telnet localhost 33441; send "\r"; expect -re {FS1:\\>};
           send "drivers\r";
           expect {
               -re {([0-9A-Fa-f]+)\x1b\[0m[^\n]*'$DRIVER'} {
                   set h $expect_out(1,string); expect -re {FS1:\\>};
                   send "unload -n $h\r"; expect -re {FS1:\\>} }
               -re {FS1:\\>} {}
           }
           send "load '$DRIVER'\r"; expect -re {Image.*FS1:\\>};
           send "\035"; expect "telnet>"; send "quit\r"' |
    tr -d '\r' | sed 's/\x1b\[[0-9;]*[A-Za-z]//g' | grep -a -E "^Unload|^Image" || true
