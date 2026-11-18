#!/bin/bash
# Usage: boot.sh [minutes]   Wait for guest ssh (default 20 min); uname == kernel install.sh put in the image; no BUG/Oops/WARNING in dmesg. Needs: Simics started (restart). Changes: none. Time: ~7 min after restart, seconds if up.
. "$(dirname "$0")/../lib.sh"
# Exit 2 = no guest (run-tests.sh stops), 1 = other FAIL.
MAX=${1:-20}
CONSOLE=$DEV/logs/simics_console.log

# --- Wait for ssh; stop early if Simics died ---------------------------------
END=$((SECONDS + MAX * 60))
until guest_find; do
    if ! pgrep -x simics > /dev/null; then
        echo "FAIL simics running (died, $CONSOLE:)"
        tail -20 $CONSOLE 2> /dev/null || true
        exit 2
    fi
    if [ $SECONDS -ge $END ]; then
        echo "FAIL guest ssh (no answer after $MAX min, MAC $(guest_mac || true))"
        exit 2
    fi
    sleep 15
done
echo "PASS guest ssh ($GUEST after $((SECONDS / 60)) min)"

# --- Kernel: the one install.sh put into the image ---------------------------
# The CI kernel also ends with "+": compare with image/kernel-version.
RELEASE=$(g "uname -r")
VERSION=$(g "uname -v")
if [ -f $DEV/image/kernel-version ]; then
    check_eq "kernel release" "$RELEASE" "$(sed -n 1p $DEV/image/kernel-version)"
    check_eq "kernel build" "$VERSION" "$(sed -n 2p $DEV/image/kernel-version)"
else
    echo "INFO no image/kernel-version (no install.sh yet): $RELEASE $VERSION"
fi

# --- dmesg: no oops / BUG / WARNING ------------------------------------------
check_dmesg "dmesg clean" "$DMESG_OOPS"

finish
