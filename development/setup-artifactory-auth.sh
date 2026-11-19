#!/bin/bash
# Usage: setup-artifactory-auth.sh <host ip>
# One-time Artifactory login on the host, so Simics can download the BIOS knob
# tools. Without it Infra Tools sends user "None" and gets 401.
# You type your own username and password; they stay on the host
# (/root/.config/devtools/config.yaml).
set -eo pipefail
trap 'echo "ABORT. Error on line $LINENO (exit code $?)"' ERR

if [[ -z $1 ]]; then
    echo "Usage: $0 <host ip>"
    exit 1
fi

HOST=root@$1
SERVER=https://simics-artifactory.devtools.intel.com
CONFIG=/root/.config/devtools/config.yaml

if ! ssh "$HOST" "test -x /root/SimicsWorkspace/bin/infra-tools-config"; then
    echo "No Infra Tools on $HOST: no login possible, seeding BIOS knob tools"
    bash "$(dirname "$0")/seed-bios-knob-tools.sh" "$1"
    exit 0
fi

if ssh "$HOST" "grep -q simics-artifactory $CONFIG" 2> /dev/null; then
    echo "Artifactory login already set on $HOST"
    exit 0
fi

echo "Artifactory login on $HOST: type your own username and password"
ssh -t "$HOST" "cd /root/SimicsWorkspace && bin/infra-tools-config auth artifactory $SERVER"

if ! ssh "$HOST" "grep -q simics-artifactory $CONFIG"; then
    echo "ERROR: login not saved in $HOST:$CONFIG"
    exit 1
fi
echo "Artifactory login set on $HOST"
