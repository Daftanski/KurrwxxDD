#!/bin/bash
# Usage: add-device.sh <n>   Add or update LAVA device simics-<n> from host-ip-<n> / host-role-<n> in config.txt.
# Tag = first word of the role, lowercase. Env: CONFIG (config.txt path), LAVA_DIR (default ~/lava).
set -eo pipefail
trap 'echo "ABORT. Error on line $LINENO (exit code $?)"' ERR

if [[ -z $1 ]]; then
    echo "Usage: $0 <host number>"
    exit 1
fi

HERE=$(dirname "$(readlink -f "$0")")
CONFIG=${CONFIG:-$HERE/../../config.txt}
LAVA_DIR=${LAVA_DIR:-$HOME/lava}
N=$1
NAME=simics-$N
REMOTE=/etc/lava-server/dispatcher-config/devices/$NAME.jinja2

conf() {
    grep -m1 "^$1=" "$CONFIG" | cut -d= -f2- || true
}

IP=$(conf host-ip-$N)
ROLE=$(conf host-role-$N)
if [[ -z $IP ]]; then
    echo "host-ip-$N not found in $CONFIG"
    exit 1
fi
TAG=$(echo "${ROLE%% *}" | tr A-Z a-z)

TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT
sed "s/@HOST_IP@/$IP/" "$HERE/devices/simics-host.jinja2.template" > "$TMP"

cd "$LAVA_DIR"
docker compose cp "$TMP" lava-server:$REMOTE
# Wrong owner makes lava-server crash-loop.
docker compose exec -T lava-server chown lavaserver:lavaserver $REMOTE

if docker compose exec -T lava-server lava-server manage devices list | grep -q "^\* $NAME ("; then
    echo "device $NAME exists, file updated"
else
    docker compose exec -T lava-server lava-server manage devices add --device-type ssh --worker worker0 $NAME
fi

if [[ -n $TAG ]]; then
    docker compose exec -T lava-server lava-server manage shell -c "
from lava_scheduler_app.models import Device, Tag
t, _ = Tag.objects.get_or_create(name='$TAG')
Device.objects.get(hostname='$NAME').tags.set([t])
"
    echo "device $NAME tag $TAG"
fi
