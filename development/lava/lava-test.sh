#!/bin/bash
# lava-test.sh - run Simics tests through LAVA with a short answer (for AI and people).
#   lava-test.sh <uefi|kernel> <tag> <step ...>   submit, wait, print the summary
#   lava-test.sh wait <job id>                    wait for / summarize a job already submitted
#   lava-test.sh list <uefi|kernel>               test catalog (local, no LAVA)
# Summary: "job <id> ... PASS|FAIL|ERROR" + FAIL lines (max 20) + log path.
# Full plain log: ~/lava/svl/logs/<id>.txt (read it only on FAIL / ERROR).
# Exit: 0 PASS, 1 FAIL, 2 ERROR (job broken, canceled, no verdict).
HERE=$(dirname "$0")
REPO=$(dirname "$(readlink -f "$0")")/..
cd "$HERE"
source ./token.env
LAVA_URL=${LAVA_URL:-http://localhost}
LOGS=$PWD/logs
mkdir -p "$LOGS"

api() {
    curl -s --noproxy '*' -H "Authorization: Token $LAVA_TOKEN" "$LAVA_URL/api/v0.2/jobs/$1"
}
field() {
    python3 -c "import json,sys; print(json.load(sys.stdin).get('$1', ''))"
}

case $1 in
    list)
        exec bash "$REPO/$2-dev/misc/run-tests.sh" list ;;
    wait)
        ID=$2 ;;
    uefi|kernel)
        ID=$(./submit.sh "$@") || exit 2
        echo "job $ID submitted: $*" ;;
    *)
        sed -n '2,8s/^# \{0,1\}//p' "$0"
        exit 2 ;;
esac

START=$SECONDS
while :; do
    STATE=$(api "$ID/" | field state)
    case $STATE in
        Finished|Canceled|"") break ;;
    esac
    sleep 20
done

J=$(api "$ID/")
HEALTH=$(field health <<< "$J")
DESC=$(field description <<< "$J")
DUR=$(python3 -c 'import json,sys,datetime as d
j = json.load(sys.stdin)
f = lambda s: d.datetime.fromisoformat(s.replace("Z", "+00:00"))
try: print("%dm%02ds" % divmod(int((f(j["end_time"]) - f(j["start_time"])).total_seconds()), 60))
except Exception: print("?")' <<< "$J")

# Plain log: test output (target) + errors. LAVA log = YAML list of {dt, lvl, msg}.
LOG=$LOGS/$ID.txt
api "$ID/logs/" | python3 -c 'import sys, yaml
for e in yaml.safe_load(sys.stdin) or []:
    m = e.get("msg")
    if e.get("lvl") in ("target", "error", "exception") and isinstance(m, str):
        print(m if e["lvl"] == "target" else "LAVA-%s %s" % (e["lvl"], m))' > "$LOG" 2> /dev/null

VERDICT=$(grep -a -m1 '^== failed:' "$LOG")
if [[ $VERDICT == "== failed: none" ]]; then
    R=PASS; RC=0
elif [[ -n $VERDICT ]]; then
    R=FAIL; RC=1
else
    R=ERROR; RC=2
fi
echo "job $ID $R ($STATE/$HEALTH, $DUR) $DESC"
echo "  $(grep -a -c '^PASS ' "$LOG") checks passed, $(grep -a -c '^FAIL ' "$LOG") failed. $VERDICT"
if [ $RC = 1 ]; then
    # FAIL line with its step: "<step>: FAIL ..."
    awk '/^== / { s = substr($0, 4) } /^FAIL / { print "  " s ": " $0 }' "$LOG" | head -20
elif [ $RC = 2 ]; then
    grep -a -E '^(LAVA-|ABORT)' "$LOG" | tail -5 | cut -c1-300 | sed 's/^/  /'
    tail -5 "$LOG" | cut -c1-300 | sed 's/^/  | /'
fi
echo "  log: $LOG"
exit $RC
