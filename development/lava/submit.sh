#!/bin/bash
# Usage: submit.sh <uefi|kernel> <tag> [step ...]   (default steps: all)
# Submits one Simics job and prints only the job id. tag = device tag = role in
# config.txt (pfd, pfp); PFP=TRUE for tag pfp. AI and people: use lava-test.sh.
cd "$(dirname "$0")"
source ./token.env
LAVA_URL=${LAVA_URL:-http://localhost}
SETUP=$1
TAG=$(tr A-Z a-z <<< "$2")
if [[ $SETUP != uefi && $SETUP != kernel ]] || [[ -z $TAG ]]; then
    echo "Usage: $0 <uefi|kernel> <tag> [step ...]" >&2
    exit 1
fi
shift 2
STEPS=${*:-all}
PFP=FALSE
[ "$TAG" = pfp ] && PFP=TRUE
JOB=$(sed -e "s/^job_name: .*/job_name: \"$SETUP $TAG: $STEPS\"/" \
          -e "s/^tags: .*/tags: [$TAG]/" \
          -e "s/SETUP: .*/SETUP: \"$SETUP\"/" \
          -e "s/STEPS: .*/STEPS: \"$STEPS\"/" \
          -e "s/PFP: .*/PFP: \"$PFP\"/" jobs/simics.yaml)
python3 -c 'import json,sys; print(json.dumps({"definition": sys.stdin.read()}))' <<< "$JOB" |
    curl -s --noproxy '*' -H "Authorization: Token $LAVA_TOKEN" \
         -H 'Content-Type: application/json' -d @- \
         "$LAVA_URL/api/v0.2/jobs/" |
    python3 -c 'import json,sys
d = json.load(sys.stdin)
if "job_ids" not in d:
    sys.exit("submit failed: %s" % d)
print(d["job_ids"][0])'
