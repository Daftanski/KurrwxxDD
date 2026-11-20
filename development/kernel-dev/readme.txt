# Linux kernel development in Simics

## Folders

   core/   - image tools and Simics restart (runs on the Simics host)
   misc/   - tests (see misc/readme.txt), sf-toggle-trace.sh (guest)
   image/  - created at run time: dev disk image (.wic, .craff), kernel output
   logs/   - created at run time

## Deploy (from the dev machine)

       cd development
       ./setup-kernel-dev.sh <host ip>
   Installs the ssh key if needed, copies kernel-dev/ to
   /root/SimicsWorkspace/development/ on the host and runs
   core/setup.sh (first time: unpacks the CI image, ~15 GB).

## Build + install a kernel (from the dev machine)

       cd <kernel tree>
       <path>/development/update-simics-kernel.sh <host ip>
   Runs setup-kernel-dev.sh, takes .config from the image, builds,
   copies bzImage + modules to the host (image/kernel_output.tar.gz),
   then build-kselftest.sh (driver selftests, below; KSFT_TARGETS=""
   skips them).
   Install (into the image, repack .craff, restart) through LAVA:
       ~/lava/svl/lava-test.sh kernel <tag> install boot ixd
   Console: VNC display :1 (port 5901).

## Kernel selftests (drivers/net, drivers/net/hw)

       cd <kernel tree>
       <path>/development/build-kselftest.sh <host ip>
   Builds the selftests of the tree with its .config (kselftest-install),
   adds PyYAML (ynl needs it; guest has none) and a prefix.pl that works
   with the guest's minimal perl, copies image/kselftest_output.tar.gz
   (~0.7 MB) to the host. No kernel build, .config untouched: a new
   selftest build for the running kernel.
   Run: ~/lava/svl/lava-test.sh kernel <tag> kselftest[:A:B,coll:test,...]
   (misc/tests/kselftest.sh: loopback, port B = netns remote). Uses the
   image's /kselftest (install.sh) or pushes the host archive to /tmp.
   drivers/net/hw needs liburing (iou-zcrx): built static once in
   ~/.cache/kdev/liburing. A target that fails to build (e.g. ynl and a
   broken Documentation/netlink/specs/*.yaml) is an ERROR, not skipped.

## core/

   setup.sh                - make image/ from the CI .craff, link it into
                             /mnt/image_cache
                             (redo after every CI run; safe to re-run)
   config.sh               - print the image's kernel .config
   install.sh              - install image/kernel_output.tar.gz into the image,
                             image/kselftest_output.tar.gz to /kselftest
   mount-image.sh          - mount the .wic to image/image_mount
   umount-image.sh         - undo mount-image.sh
   restart.sh              - stop Simics, run launch-simics.sh in the background
   launch-simics.sh        - start Simics in the foreground with the dev image
                             (copy of startup_scripts/vpc_launch.simics with
                             $disk_image changed)

## Logs (development/kernel-dev/logs/)

   simics_console.log  - Simics output when started by restart.sh

## Stop Simics

       killall simics
