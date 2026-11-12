#!/bin/bash
. "$(dirname "$0")/../lib.sh"
uefi_begin probe
uefi_cmd "hii.efi show 20 0x200 --all"
uefi_cmd "hii.efi detail 20 0x200"
uefi_cmd "hii.efi show 20 0x200 --lang fr-FR"
uefi_cmd "ping -n 2 -s 192.168.0.101 192.168.0.200" 'packets transmitted.*FS1:'
uefi_end
uefi_log > /tmp/probe.log
