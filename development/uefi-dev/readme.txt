# UEFI development in Simics

## Folders

   core/  - boot Simics to the UEFI Shell (see core/readme.txt)
   misc/  - tests and helpers (see misc/readme.txt)
   doc/   - learning material: UEFI driver model, test guide
            (see doc/README.txt)
   logs/  - created at run time

## Deploy (from the dev machine)

       cd development
       ./setup-uefi-dev.sh <host ip>
   Copies uefi-dev/ to /root/SimicsWorkspace/development/ on the host.

## Quick start

   1. Put files (e.g. app.efi) into core/usb-drive/
   2. Run core/restart.sh and wait for "UEFI Shell is up"
   3. telnet localhost 33441

## Connect to the UEFI Shell

       telnet localhost 33441
   (from another machine: telnet <host ip> 33441)

   Press Enter to get the Shell> prompt. Example:
       Shell> fs1:
       FS1:\> ls
       FS1:\> app.efi arg1 arg2

   Exit telnet: Ctrl+] then type quit. Simics keeps running; you can
   connect again any time.

   Other ways to reach the shell:
   - Graphics console on VNC display :1 (port 5901).
   - Simics CLI: telnet localhost 33341, then e.g.
       summitville.mb.s3m0.s3m[0].uart_console.con.input "ls fs1:\r"

## Drives in the UEFI Shell

   fs0: NVMe disk
   fs1: our USB drive (core/usb-drive/ folder)
   fs2: simics_agent_binaries disk of the target

## Logs (development/uefi-dev/logs/)

   uefi_serial.log     - everything printed on the UEFI console (BIOS + shell)
   simics_console.log  - Simics output when started by restart.sh

## Stop Simics

       killall simics





