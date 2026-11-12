development - shared Simics development and test setups
=======================================================
For everyone who develops or tests drivers/firmware on Simics.

doc/simics/      Simics platform how-to (start: 01-overview.txt)
doc/lava/        LAVA test scheduler how-to (start: 01-overview.txt)
kernel-dev/      Linux setup: our kernel on the Simics guest
uefi-dev/        UEFI setup: EFI driver in the UEFI shell + tests
                 (uefi-dev/doc: test guide, plans, results)
lava/            LAVA server config (linked into ~/lava)

First steps on a new workstation:
  1. cp ../config.example ../config.txt, fill in your hosts.
  2. LAVA server: doc/lava/03-maintenance.txt 3.
  3. Per host: ssh key, then ./setup-uefi-dev.sh <ip> (UEFI) or
     ./setup-kernel-dev.sh <ip> (Linux), then lava/add-device.sh <n>.
  4. Run tests: doc/lava/02-usage.txt 1.

setup-uefi-dev.sh <ip>        deploy uefi-dev to a host
setup-kernel-dev.sh <ip>      deploy kernel-dev to a host
update-simics-kernel.sh <ip>  build kernel + deploy (run in kernel tree)
lava/add-device.sh <n>        add/update LAVA device for host n of config.txt
uefi-dev/misc/dev/ut-nic-core.sh   nic-core unit tests (dev machine)

Hosts and IPs: ../config.txt (not in git; copy ../config.example).
Never put IPs in docs or committed files.
