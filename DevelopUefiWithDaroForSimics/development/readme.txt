# UEFI development in Simics

## Boot to the UEFI Shell: reboot.sh

1. Put your files (e.g. app.efi) into:
       /root/SimicsWorkspace/development/usb-drive/

2. Run:
       /root/SimicsWorkspace/development/reboot.sh

   It stops any running Simics, builds usb-drive.img from usb-drive/,
   cold boots Simics in the background and waits for the UEFI Shell
   (about 2 minutes). When ready it prints:
       UEFI Shell is up, files are on fs1:. Connect: telnet localhost 33441

   Exit code: 0 = UEFI Shell is up, 1 = Simics died or timeout (30 min).
   Simics keeps running after the script ends (also after ssh logout).
   Run reboot.sh again after changing files in usb-drive/.

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
   fs1: our USB drive (usb-drive/ folder)
   fs2: simics_agent_binaries disk of the target

## Logs (development/logs/)

   uefi_serial_vm1.log  - everything printed on the UEFI console (BIOS + shell)
   simics_console.log   - Simics output when started by reboot.sh

## Other scripts

   start.sh            - start Simics in the foreground (Simics CLI in the terminal);
                         does not rebuild usb-drive.img, run make-usb-drive.sh first
   make-usb-drive.sh   - only build usb-drive.img from usb-drive/

## Stop Simics

       killall simics





