#!/bin/bash
# Usage: lava-run.sh [step ...]   same steps as run-tests.sh.
# Runs run-tests.sh and reports results as LAVA test cases:
#   <nn>-<step>          one per step (pass/fail)
#   <nn>-<step>.<check>  one per PASS/FAIL line
set -eo pipefail
trap 'echo "ABORT. Error on line $LINENO (exit code $?)"' ERR

DEV=/root/SimicsWorkspace/development/uefi-dev
# Outside LAVA: only print.
command -v lava-test-case > /dev/null || lava-test-case() { :; }

N=0
STEP=""
STEPS=()
FAILED=""

name() {
    tr -c 'A-Za-z0-9._-' '_' <<< "$1" | sed 's/_*$//; s/__*/_/g'
}

while IFS= read -r LINE; do
    echo "$LINE"
    case $LINE in
        "== failed:"*)
            FAILED=" ${LINE#== failed: } "
            ;;
        "== "*)
            N=$((N + 1))
            STEP=$(printf "%02d-%s" $N "${LINE#== }")
            STEPS+=("$STEP")
            ;;
        PASS\ *|FAIL\ *)
            LABEL=${LINE#* }
            LABEL=${LABEL%% (*}
            RESULT=pass
            [[ $LINE == FAIL* ]] && RESULT=fail
            lava-test-case "$STEP.$(name "$LABEL")" --result $RESULT
            ;;
    esac
done < <($DEV/misc/run-tests.sh "$@" 2>&1 || true)

# run-tests.sh stops after a failed restart: later steps are missing.
for S in "${STEPS[@]}"; do
    RESULT=pass
    [[ $FAILED == *" ${S#*-} "* ]] && RESULT=fail
    [[ -z $FAILED && $S == "${STEPS[-1]}" ]] && RESULT=fail
    lava-test-case "$S" --result $RESULT
done
# No "== failed:" line = run-tests.sh died.
if [ "$FAILED" = " none " ]; then
    exit 0
fi
exit 1
