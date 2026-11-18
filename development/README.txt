development - shared Simics development and test setups
=======================================================
For everyone who develops or tests drivers/firmware on Simics.

doc/simics/      Simics platform how-to (start: 01-overview.txt)
doc/lava/        LAVA test scheduler how-to (start: 01-overview.txt)
kernel-dev/      Linux setup: our kernel on the Simics guest
uefi-dev/        UEFI setup: EFI driver in the UEFI shell + tests
                 (uefi-dev/doc: test guide, plans, results)
lava/            LAVA server config + lava-test.sh (linked into ~/lava)
skills/          AI agent skills (lava-test), linked into
                 ~/.config/opencode/skills/

First steps on a new workstation:
  1. cp ../config.example ../config.txt, fill in your hosts.
  2. LAVA server: doc/lava/03-maintenance.txt 3.
  3. Per host: ./setup-uefi-dev.sh <ip> (UEFI) or ./setup-kernel-dev.sh
     <ip> (Linux); both install your ssh key (password asked once).
     UEFI: also asks your Artifactory login once (BIOS knobs).
     Then lava/add-device.sh <n>.
  4. Run tests: ~/lava/svl/lava-test.sh (doc/lava/02-usage.txt 1.).

setup-uefi-dev.sh <ip>        deploy uefi-dev to a host (+ Artifactory login)
setup-kernel-dev.sh <ip> [copy]  deploy kernel-dev to a host (copy = files only)
setup-artifactory-auth.sh <ip> Artifactory login on host (BIOS knobs)
seed-bios-knob-tools.sh <ip>  BIOS knob tools to host cache, no login
update-simics-kernel.sh <ip>  build kernel + copy (run in kernel tree);
                              install = LAVA step "install"
lava/add-device.sh <n>        add/update LAVA device for host n of config.txt
uefi-dev/misc/dev/ut-nic-core.sh   nic-core unit tests (dev machine)

Hosts and IPs: ../config.txt (not in git; copy ../config.example).
Never put IPs in docs or committed files.
