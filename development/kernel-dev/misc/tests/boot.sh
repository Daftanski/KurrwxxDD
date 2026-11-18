#!/bin/bash
# Usage: boot.sh [minutes]   Wait for the guest (ssh), check it runs our kernel, no oops in dmesg. Needs: Simics started (restart).
. "$(dirname "$0")/../lib.sh"
MAX=${1:-20}
CONSOLE=$DEV/logs/simics_console.log

# --- Wait for ssh; stop early if Simics died ---------------------------------
END=$((SECONDS + MAX * 60))
until guest_find; do
    if ! pgrep -x simics > /dev/null; then
        echo "FAIL simics running (died, $CONSOLE:)"
        tail -20 $CONSOLE 2> /dev/null || true
        exit 1
    fi
    if [ $SECONDS -ge $END ]; then
        echo "FAIL guest ssh (no answer after $MAX min, MAC $(guest_mac || true))"
        exit 1
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
BAD=$(g "dmesg" | grep -E "BUG:|Oops|WARNING:|Call Trace|general protection" | head -5 || true)
check_eq "dmesg clean" "$(echo -n "$BAD" | grep -c . || true)" 0
[ -z "$BAD" ] || echo "$BAD"

finish
