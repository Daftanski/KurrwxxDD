#!/usr/bin/bash
# Kernel development against the Simics CI disk image.
#
#   simics_dev.sh setup     prepare a bare platform, safe to re-run
#   simics_dev.sh config    print the image's kernel config to stdout
#   simics_dev.sh install   install kernel_output.tar.gz into the image
#
# Driven over ssh by update_simics_kernel.sh on the build machine.
set -euo pipefail

SIMICS_WORKSPACE_DIR=/root/SimicsWorkspace
CRAFF_TOOL=$SIMICS_WORKSPACE_DIR/bin/craff
CRAFF_SRC_DIR=$SIMICS_WORKSPACE_DIR/CRAFF
IMAGE_CACHE_DIR=/mnt/image_cache

WORKSPACE=$SIMICS_WORKSPACE_DIR/development
WIC_FILE=$WORKSPACE/development_disk_image.wic
CRAFF_FILE=$WORKSPACE/development_disk_image.craff
IMAGE_MOUNT_DIR=$WORKSPACE/image_mount
KERNEL_OUTPUT_DIR=$WORKSPACE/kernel_output

# the platform has no devtmpfs or udev, so loop nodes are never created for us
ensure_loop_nodes() {
    modprobe loop 2>/dev/null || true

    for i in $(seq 0 7); do
        [ -b "/dev/loop$i" ] || mknod "/dev/loop$i" b 7 "$i"
    done
}

mount_image() {
    mkdir -p "$IMAGE_MOUNT_DIR/boot" "$IMAGE_MOUNT_DIR/root"
    ensure_loop_nodes

    if [ -n "$(losetup --associated "$WIC_FILE" --output NAME --noheadings)" ]; then
        umount_image
    fi

    local loop_dev part_dev
    loop_dev=$(losetup --find --show "$WIC_FILE")
    kpartx -a "$loop_dev"
    part_dev=/dev/mapper/$(basename "$loop_dev")

    mount "${part_dev}p1" "$IMAGE_MOUNT_DIR/boot"
    mount "${part_dev}p2" "$IMAGE_MOUNT_DIR/root"
    echo "Mounted $WIC_FILE via $loop_dev" >&2
}

umount_image() {
    for dir in boot root; do
        while mountpoint -q "$IMAGE_MOUNT_DIR/$dir"; do
            umount "$IMAGE_MOUNT_DIR/$dir"
        done
    done

    for loop_dev in $(losetup --associated "$WIC_FILE" --output NAME --noheadings); do
        kpartx -d "$loop_dev"
        losetup -d "$loop_dev"
        echo "released $loop_dev" >&2
    done
}

unpack_craff() {
    local craff_src
    craff_src=$CRAFF_SRC_DIR/$(grep -oE '[^ /]+\.craff' "$SIMICS_WORKSPACE_DIR/vm1.sh")

    umount_image
    rm -f "$WIC_FILE"
    echo "Converting ${craff_src} to ${WIC_FILE}" >&2
    $CRAFF_TOOL -d -o "$WIC_FILE" "$craff_src"
}

pack_craff() {
    rm -f "$CRAFF_FILE"
    echo "Converting ${WIC_FILE} to ${CRAFF_FILE}" >&2
    $CRAFF_TOOL -o "$CRAFF_FILE" "$WIC_FILE"
}

cmd_setup() {
    if [ ! -x "$CRAFF_TOOL" ]; then
        echo "$CRAFF_TOOL not found, is the Simics workspace deployed?" >&2
        exit 1
    fi

    mkdir -p "$WORKSPACE"

    # the wic is 15 GB and takes a minute to build, so only do it once
    [ -f "$WIC_FILE" ] || unpack_craff
    [ -f "$CRAFF_FILE" ] || pack_craff

    # Simics resolves images through this dir, but it ships as a symlink to the
    # read-only CRAFF dir. extract_ci_build.py restores the symlink, so this has
    # to be redone after every CI run.
    rm -rf "$IMAGE_CACHE_DIR"
    mkdir -p "$IMAGE_CACHE_DIR"
    ln -sf "$CRAFF_SRC_DIR"/*.craff "$IMAGE_CACHE_DIR/"
    ln -sf "$CRAFF_FILE" "$IMAGE_CACHE_DIR/"

    # a copy, because editing vm1.sh in place would make it boot the image it is
    # supposed to be the source of
    sed 's|[^ ]*\.craff|development_disk_image.craff|' \
        "$SIMICS_WORKSPACE_DIR/vm1.sh" > "$SIMICS_WORKSPACE_DIR/custom_vm1.sh"
    chmod +x "$SIMICS_WORKSPACE_DIR/custom_vm1.sh"
    echo "Setup complete, boot with $SIMICS_WORKSPACE_DIR/custom_vm1.sh" >&2
}

# status goes to stderr so stdout stays a clean .config
cmd_config() {
    mount_image

    # a second config would silently be concatenated onto the first
    local configs=("$IMAGE_MOUNT_DIR"/root/boot/config-*)
    if [ ${#configs[@]} -ne 1 ]; then
        umount_image
        echo "expected one config in the image, found ${#configs[@]}" >&2
        exit 1
    fi

    cat "${configs[0]}"
    umount_image
}

cmd_install() {
    rm -rf "$KERNEL_OUTPUT_DIR"
    mkdir -p "$KERNEL_OUTPUT_DIR"
    tar xzf "$WORKSPACE/kernel_output.tar.gz" -C "$KERNEL_OUTPUT_DIR"

    # read from the image itself, lib/modules may hold stale dirs from earlier builds
    local kernel_release
    kernel_release=$(file "$KERNEL_OUTPUT_DIR/arch/x86/boot/bzImage" | grep -oP 'version \K\S+')
    echo "Installing kernel $kernel_release" >&2

    mount_image
    cp "$KERNEL_OUTPUT_DIR/arch/x86/boot/bzImage" "$IMAGE_MOUNT_DIR/boot/bzImage"
    cp -a "$KERNEL_OUTPUT_DIR/lib/modules/$kernel_release" "$IMAGE_MOUNT_DIR/root/lib/modules/"

    # modules.dep is built against the image, not the build machine
    depmod -b "$IMAGE_MOUNT_DIR/root" "$kernel_release"
    umount_image

    pack_craff
    echo "Installed $kernel_release, restart Simics to boot it" >&2
}

case "${1:-}" in
    setup)   cmd_setup ;;
    config)  cmd_config ;;
    install) cmd_install ;;
    *)       echo "usage: $(basename "$0") {setup|config|install}" >&2; exit 1 ;;
esac
