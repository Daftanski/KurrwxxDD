#!/bin/bash
# Build all NicCorePkg unit tests and run every binary. Exit 1 on any failure.
# NIC_CORE overrides the nic-core repo path.
set -eo pipefail
trap 'echo "ABORT. Error on line $LINENO (exit code $?)"' ERR

NIC_CORE=${NIC_CORE:-$(realpath "$(dirname "$0")/../../../../../networking.ipu.tools/boot/uefi/nic-core")}
LOG=$(mktemp -d)
FAILED=0

cd "$NIC_CORE"

restore_version() {
    git checkout -- NicCorePkg/Include/Version.h 2> /dev/null || true
}
trap restore_version EXIT

for f in $(git diff --name-only --relative HEAD) $(git ls-files --others --exclude-standard); do
    [[ -f $f ]] || continue
    [[ $f == *EXEC_CNIC_BUILD.sh ]] && continue
    case $f in
        *.c|*.h|*.cpp|*.inf)
            LINES=$(wc -l < "$f")
            CRS=$(grep -c $'\r$' "$f" || true)
            if [[ $LINES -ne $CRS ]]; then
                echo "CRLF mismatch $f lines=$LINES cr=$CRS"
                FAILED=1
            fi
            ;;
    esac
done

BUILD_RC=0
BUILD_TOOLS_PRECONFIGURED=1 BUILD_INCREMENTAL=1 bash ./Scripts/build_test.sh > "$LOG/build.log" 2>&1 || BUILD_RC=$?
echo "build rc=$BUILD_RC"
if [[ $BUILD_RC -ne 0 ]]; then
    grep -m5 -E ' error|error:' "$LOG/build.log" || true
    echo "full log: $LOG/build.log"
    exit 1
fi

BINS=(Build/NicCorePkg/Test/NOOPT_GCC5/X64/*Test)
if [[ ! -e ${BINS[0]} ]]; then
    echo "no test binaries found"
    exit 1
fi

TOTAL=0
for T in "${BINS[@]}"; do
    RC=0
    "$T" > "$LOG/one.log" 2>&1 || RC=$?
    N=$(grep -E '^\[  PASSED' "$LOG/one.log" | awk '{print $4}' || true)
    TOTAL=$((TOTAL + ${N:-0}))
    if [[ $RC -ne 0 ]]; then
        echo "FAIL $(basename "$T") rc=$RC"
        grep -E '^\[  FAILED' "$LOG/one.log" | head -5 || true
        FAILED=1
    fi
done
echo "binaries=${#BINS[@]} passed=$TOTAL"

[[ $FAILED -eq 0 ]]
