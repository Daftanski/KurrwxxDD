#!/bin/bash
# Usage: submit.sh [PFD|PFP] [step ...]   (default: PFD all)
# Submits one Simics job to LAVA and prints the job id.
cd "$(dirname "$0")"
source ./token.env
MODE=${1:-PFD}
shift
STEPS=${*:-all}
PFP=FALSE
TAG=pfd
if [ "$MODE" = PFP ]; then
    PFP=TRUE
    TAG=pfp
fi
# Device tag picks the host of that mode.
JOB=$(sed -e "s/^job_name: .*/job_name: simics uefi $MODE - $STEPS/" \
          -e "s/^tags: .*/tags: [$TAG]/" \
          -e "s/STEPS: .*/STEPS: \"$STEPS\"/" \
          -e "s/PFP: .*/PFP: \"$PFP\"/" jobs/simics-ping.yaml)
python3 -c 'import json,sys; print(json.dumps({"definition": sys.stdin.read()}))' <<< "$JOB" |
    curl -s --noproxy '*' -H "Authorization: Token $LAVA_TOKEN" \
         -H 'Content-Type: application/json' -d @- \
         http://localhost/api/v0.2/jobs/
echo
