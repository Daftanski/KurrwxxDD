#!/bin/bash
# Usage: watchdog.sh <pid>   (run-tests.sh starts it next to each test step)
# Watches the guest while test process group <pid> runs. Fatal kernel messages
# newer than the start (Oops, BUG:, general protection, panic, hung task, soft
# lockup) or a guest that does not answer 3 times in a row: prints FAIL lines,
# creates $WD_FLAG and kills the test (TERM, then KILL). A WARNING is not fatal:
# check_dmesg of the test reports it.
. "$(dirname "$0")/lib.sh"
set +e
trap - ERR
PID=$1
INTERVAL=${WD_INTERVAL:-15}
WD_FLAG=${WD_FLAG:-/tmp/kdev-guest-dead}
FATAL=' BUG: |Oops|general protection|Kernel panic|blocked for more than|soft lockup|hard LOCKUP'

guest_find || exit 0
# Start = guest uptime now: dmesg lines with a newer [timestamp] are ours (no
# marker: the ring buffer is full and wraps).
T0=$(gt 30 "cut -d' ' -f1 /proc/uptime")
[ -n "$T0" ] || exit 0

dead() {
    echo "FAIL watchdog: $1 (stopping the run: guest needs restart)"
    [ -z "$2" ] || sed 's/^/  wd| /' <<< "$2"
    touch $WD_FLAG
    kill -TERM -- -$PID 2> /dev/null
    for I in $(seq 30); do
        kill -0 -- -$PID 2> /dev/null || exit 0
        sleep 1
    done
    kill -KILL -- -$PID 2> /dev/null
    exit 0
}

MISS=0
while kill -0 $PID 2> /dev/null; do
    sleep $INTERVAL
    kill -0 $PID 2> /dev/null || break
    # Own connection with a time limit (gt): a hung guest must not hang us.
    OUT=$(gt 30 "dmesg | awk -v t0=$T0 'match(\$0, /^\\[ *[0-9]+\\.[0-9]+\\]/) { ts = substr(\$0, 2, RLENGTH - 2) + 0 } ts > t0' | grep -E '$FATAL' | head -20; echo wd-ok" 2> /dev/null)
    if [[ $OUT != *wd-ok* ]]; then
        MISS=$((MISS + 1))
        [ $MISS -ge 3 ] && dead "guest does not answer ($MISS checks, ${INTERVAL}s apart)"
        continue
    fi
    MISS=0
    OUT=${OUT%wd-ok}
    if [ -n "${OUT//[$'\n ']/}" ]; then
        # The whole oops: 40 lines from the first fatal line.
        FIRST=$(head -1 <<< "$OUT" | grep -oE '^\[ *[0-9]+\.[0-9]+\]')
        FULL=$(gt 30 "dmesg | grep -F -A40 -m1 '$FIRST'" 2> /dev/null | head -40)
        dead "kernel: $(head -1 <<< "$OUT" | cut -c1-150)" "${FULL:-$OUT}"
    fi
done
