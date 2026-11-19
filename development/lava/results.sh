#!/bin/bash
# Usage: results.sh [--wait] <job id>   prints state, failed cases and FAIL log lines
cd "$(dirname "$0")"
source ./token.env
WAIT=0
if [[ "$1" == "--wait" ]]; then
    WAIT=1
    shift
fi
API=http://localhost/api/v0.2/jobs/$1
get() {
    curl -s --noproxy '*' -H "Authorization: Token $LAVA_TOKEN" "$API/$1"
}
state() {
    get "" | python3 -c 'import json,sys; print(json.load(sys.stdin)["state"])'
}
if [[ $WAIT == 1 ]]; then
    while [[ "$(state)" != "Finished" && "$(state)" != "Canceled" ]]; do
        sleep 30
    done
fi
get "" | python3 -c 'import json,sys; j=json.load(sys.stdin); print(j["id"], j["description"], j["state"], j["health"])'
tests() {
    local URL="$API/tests/?limit=1000"
    while [[ -n "$URL" && "$URL" != "None" ]]; do
        curl -s --noproxy '*' -H "Authorization: Token $LAVA_TOKEN" "$URL" > /tmp/lava_page.json
        python3 -c 'import json; [print(t["result"], t["name"]) for t in json.load(open("/tmp/lava_page.json"))["results"]]'
        URL=$(python3 -c 'import json; print(json.load(open("/tmp/lava_page.json")).get("next"))')
    done
}
tests | python3 -c 'import sys
r=[l.split(" ",1) for l in sys.stdin.read().splitlines() if l]
f=[n for res,n in r if res=="fail"]
print("cases:", len(r), "fail:", len(f))
for n in f: print("  FAIL", n)'
echo "log lines:"
get "logs/" | grep -a -o -E '(FAIL [^"\\]*|== failed: [^"\\]*)' | sort -u | head -50
