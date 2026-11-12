# core/ - boot Simics to the UEFI Shell

## restart.sh

1. Put your files (e.g. app.efi) into:
       /root/SimicsWorkspace/development/uefi-dev/core/usb-drive/

2. Run:
       /root/SimicsWorkspace/development/uefi-dev/core/restart.sh

   It stops any running Simics, builds usb-drive.img from usb-drive/,
   cold boots Simics in the background and waits for the UEFI Shell
   (about 2 minutes). When ready it prints:
       UEFI Shell is up, files are on fs1:. Connect: telnet localhost 33441

   Exit code: 0 = UEFI Shell is up, 1 = Simics died or timeout (30 min).
   Simics keeps running after the script ends (also after ssh logout).
   Run restart.sh again after changing files in usb-drive/.

## Other scripts

   launch-simics.sh   - start Simics in the foreground (Simics CLI in the terminal);
                        does not rebuild usb-drive.img, run make-usb-drive.sh first
   make-usb-drive.sh  - only build usb-drive.img from usb-drive/
   usb-replug.sh      - rebuild usb-drive.img and swap it in running Simics
                        (no restart, a few seconds; runs map -r and fs1:)
   swap-driver.sh     - usb-replug.sh + unload old driver + load new one
                        (DRIVER=E4999X10.EFI by default)

## Config files

   uefi-dev.preset.yml      - BIOS knobs (SetShellFirst, EfiNetworkSupport)
   pre-wa-uefi-dev.simics   - adds uefi-dev.preset.yml to the Simics presets
   post-wa-uefi-dev.simics  - flash 0x5420 bit 5 workaround, USB drive,
                              serial log, telnet 33441
   usb-drive/               - files that show up on fs1:
