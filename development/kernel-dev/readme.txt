# Linux kernel development in Simics

## Folders

   core/   - image tools and Simics restart (runs on the Simics host)
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
   copies bzImage + modules into the image, repacks the .craff and
   runs core/restart.sh. Console: VNC display :1 (port 5901).

## core/

   setup.sh                - make image/ from the CI .craff, link it into
                             /mnt/image_cache
                             (redo after every CI run; safe to re-run)
   config.sh               - print the image's kernel .config
   install.sh              - install image/kernel_output.tar.gz into the image
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
