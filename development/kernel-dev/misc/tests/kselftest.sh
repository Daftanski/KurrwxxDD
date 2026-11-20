#!/bin/bash
# Usage: kselftest.sh [A:B] [collection:test ...]   Kernel driver selftests (HW mode) on loopback pair A:B (default 0:1): NETIF = port A, remote = port B in netns (REMOTE_TYPE=netns), IPv4 only (F4: no IPv6 ND). Default tests: drivers/net:ping.py drivers/net:stats.py drivers/net:queues.py. Each subtest = PASS/FAIL, SKIP = INFO. Selftests: guest /kselftest (install) or host image/kselftest_output.tar.gz (build-kselftest.sh). Needs: ixd.sh done, ports not in a bridge. Changes: ports, host taps (restored). Time: ~4 min (default tests).
# Selftest list: tar tzf image/kselftest_output.tar.gz ./kselftest-list.txt (on the host) or kselftest-list.txt in the build.
. "$(dirname "$0")/../lib.sh"
read -r A B <<< "$(pair_split $1)"
TESTS=${*:2}
TESTS=${TESTS:-drivers/net:ping.py drivers/net:stats.py drivers/net:queues.py}
HOST_ARCHIVE=$DEV/image/kselftest_output.tar.gz
TIMEOUT=${KSFT_TIMEOUT:-900}
guest_need
dmesg_mark

# --- Selftests on the guest -----------------------------------------------------
if g "test -x /kselftest/run_kselftest.sh"; then
    K=/kselftest
    echo "INFO selftests: /kselftest (installed in the image)"
elif [ -f $HOST_ARCHIVE ]; then
    K=/tmp/kselftest
    g "rm -rf $K; mkdir -p $K; tar xzf - -C $K" < $HOST_ARCHIVE
    at_exit "g \"rm -rf $K\""
    echo "INFO selftests: $HOST_ARCHIVE -> guest $K ($(du -h $HOST_ARCHIVE | cut -f1), built $(date -r $HOST_ARCHIVE '+%F %T'))"
else
    echo "FAIL selftests present (no /kselftest, no $HOST_ARCHIVE: run build-kselftest.sh)"
    exit 1
fi
check "selftests runner" "$(g "ls $K/run_kselftest.sh" 2>&1)" "run_kselftest.sh$"
echo "INFO guest kernel $(g "uname -r"), selftests from $(g "cat $K/VERSION 2> /dev/null" || echo ?)"

loop_up $A $B || finish

# --- net.config: HW mode, remote = side B of the loopback ----------------------------
for D in drivers/net drivers/net/hw; do
    g "[ -d $K/$D ] && printf '%s\n' NETIF=$LOOP_DEV_A LOCAL_V4=$LOOP_IP_A REMOTE_V4=$LOOP_IP_B REMOTE_TYPE=netns REMOTE_ARGS=$LOOP_NS > $K/$D/net.config" || true
done
at_exit "g \"rm -f $K/drivers/net/net.config $K/drivers/net/hw/net.config\""

# --- Run and report ---------------------------------------------------------------
# run_kselftest.sh TAP: nested "# ok 1 ping.test_default_v4 [# SKIP ...]",
# top "ok 1 selftests: drivers/net: ping.py [# SKIP]" / "not ok ... # exit=1".
ARGS=""
for T in $TESTS; do ARGS+=" -t $T"; done
OUT=/tmp/kdev-kselftest.log
g "cd $K && PYTHONPATH=$K/pylib ./run_kselftest.sh --override-timeout $TIMEOUT $ARGS" > $OUT 2>&1 || true
sed 's/^/  | /' $OUT
CUR=""
while IFS= read -r L; do
    if [[ $L =~ ^#\ selftests:\ (.+)$ ]]; then
        CUR=${BASH_REMATCH[1]// /}
    elif [[ $L =~ ^#\ (not\ )?ok\ [0-9]+\ ([^ #]+)(.*)$ ]]; then
        N="$CUR ${BASH_REMATCH[2]}"
        if [[ ${BASH_REMATCH[3]} == *"# SKIP"* ]]; then
            echo "INFO SKIP $N${BASH_REMATCH[3]#*# SKIP}"
        elif [[ ${BASH_REMATCH[3]} == *"# XFAIL"* ]]; then
            echo "INFO XFAIL $N${BASH_REMATCH[3]#*# XFAIL}"
        elif [ -z "${BASH_REMATCH[1]}" ]; then
            echo "PASS $N"
        else
            echo "FAIL $N"
            FAILS=$((FAILS + 1))
        fi
    elif [[ $L =~ ^(not\ )?ok\ [0-9]+\ selftests:\ ([^ ]+)\ ([^ ]+)(.*)$ ]]; then
        N="${BASH_REMATCH[2]}${BASH_REMATCH[3]}"
        if [[ ${BASH_REMATCH[4]} == *"# SKIP"* ]]; then
            echo "INFO SKIP $N (whole test)"
        else
            check "$N (exit)" "${BASH_REMATCH[1]:-ok}${BASH_REMATCH[4]}" "^ok"
        fi
    fi
done < $OUT
check_ge "selftests run (top-level results)" "$(grep -cE '^(not )?ok [0-9]+ selftests:' $OUT || true)" $(wc -w <<< "$TESTS")

loop_down
check_dmesg "dmesg clean"
finish
