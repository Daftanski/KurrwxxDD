#!/bin/bash
# Usage: [KSFT_TARGETS="..."] [JOBS=<n>] build-kselftest.sh <ip>   run in a kernel tree (with its .config)
# Builds the driver selftests of this tree (kselftest-install), packs them with
# PyYAML (ynl needs it, the guest has none) and copies the archive to the host:
# image/kselftest_output.tar.gz. Run them through LAVA (kernel-dev test kselftest);
# install.sh also puts them in the image (/kselftest). Called by update-simics-kernel.sh.
set -eo pipefail
trap 'echo "ABORT. Error on line $LINENO (exit code $?)"' ERR

if [[ -z ${1:-} ]]; then
    echo "Usage: [KSFT_TARGETS=\"...\"] [JOBS=<n>] $0 <ip>"
    exit 1
fi

SIMICS_HOST=root@$1
KERNEL=$(pwd)
KSFT_INSTALL=$KERNEL/kselftest_install
KSFT_ARCHIVE=$KERNEL/kselftest_output.tar.gz
# HW-mode driver tests: drivers/net (shared with SW mode) and drivers/net/hw.
KSFT_TARGETS=${KSFT_TARGETS:-drivers/net drivers/net/hw}
DEV=/root/SimicsWorkspace/development/kernel-dev
LIBURING=$HOME/.cache/kdev/liburing

[ -f "$KERNEL/.config" ] || { echo "ERROR: no .config in $KERNEL" >&2; exit 1; }

# drivers/net/hw/iou-zcrx needs liburing; without it the whole hw target is
# skipped. Static copy in ~/.cache (built once, no root needed).
if [[ " $KSFT_TARGETS " == *" drivers/net/hw "* ]] && ! pkg-config --exists liburing 2> /dev/null; then
    if [ ! -f "$LIBURING/static/liburing.a" ]; then
        echo "Building liburing (static) in $LIBURING"
        rm -rf "$LIBURING"
        mkdir -p "$(dirname "$LIBURING")"
        git clone -q --depth 1 https://github.com/axboe/liburing.git "$LIBURING"
        (cd "$LIBURING" && ./configure > /dev/null && make -s -C src liburing.a -j"${JOBS:-$(nproc)}")
        mkdir -p "$LIBURING/static"
        cp "$LIBURING/src/liburing.a" "$LIBURING/static/"
    fi
    # Environment CFLAGS (not the command line: that would drop the selftest
    # Makefiles' own flags). -L in CFLAGS: the selftest link rule ignores LDFLAGS.
    export CFLAGS="-I$LIBURING/src/include -L$LIBURING/static"
fi

rm -rf "$KSFT_INSTALL"
make kselftest-install TARGETS="$KSFT_TARGETS" KSFT_INSTALL_PATH="$KSFT_INSTALL" -j"${JOBS:-$(nproc)}"

# kselftest-install skips a target whose build failed and still exits 0.
for T in $KSFT_TARGETS; do
    if [ ! -d "$KSFT_INSTALL/$T" ]; then
        echo "ERROR: selftest target $T was not built (see the make output above;" >&2
        echo "  ynl errors: a broken Documentation/netlink/specs/*.yaml in this tree)." >&2
        echo "  Other targets only: KSFT_TARGETS=\"drivers/net\" $0 $1" >&2
        exit 1
    fi
done

# The tests load the netlink specs at run time (ynl): a spec that does not
# parse breaks every test that uses that family (ping.py: ethtool.yaml).
BAD=$(python3 - "$KSFT_INSTALL/net/lib/specs" <<'PY'
import glob, sys, yaml
for f in sorted(glob.glob(sys.argv[1] + "/*.yaml")):
    try:
        yaml.safe_load(open(f))
    except yaml.YAMLError as e:
        print("%s: %s" % (f.split("/")[-1], str(e).splitlines()[0]))
PY
)
if [ -n "$BAD" ]; then
    echo "ERROR: netlink specs that do not parse (Documentation/netlink/specs in this tree):" >&2
    echo "$BAD" | sed 's/^/  /' >&2
    exit 1
fi

# Guest perl is minimal (no IO::Handle): kselftest/prefix.pl (prefixes test
# output with "# ") autoflushes with the built-in $| instead.
sed -i -e '/^use IO::Handle;/d' -e 's/^STDOUT->autoflush(1);/$| = 1;/' "$KSFT_INSTALL/kselftest/prefix.pl"
grep -q '^\$| = 1;' "$KSFT_INSTALL/kselftest/prefix.pl" || { echo "ERROR: prefix.pl not patched" >&2; exit 1; }

# PyYAML, pure Python part (no C extension: any guest python3 version).
YAML_DIR=$(python3 -c 'import os, yaml; print(os.path.dirname(yaml.__file__))')
mkdir -p "$KSFT_INSTALL/pylib/yaml"
cp "$YAML_DIR"/*.py "$KSFT_INSTALL/pylib/yaml/"

rm -f "$KSFT_ARCHIVE"
tar czf "$KSFT_ARCHIVE" -C "$KSFT_INSTALL" .
echo "Selftests: $(cut -d: -f1 "$KSFT_INSTALL/kselftest-list.txt" | sort | uniq -c | xargs), $(du -sh "$KSFT_ARCHIVE" | cut -f1)"

echo "Sending $KSFT_ARCHIVE to $SIMICS_HOST:$DEV/image"
ssh "$SIMICS_HOST" "mkdir -p $DEV/image"
scp "$KSFT_ARCHIVE" "$SIMICS_HOST:$DEV/image/"
