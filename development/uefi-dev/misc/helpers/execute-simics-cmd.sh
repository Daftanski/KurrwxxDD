#!/bin/bash
# Usage: execute-simics-cmd.sh "cmd1" ["cmd2" ...]
set -eo pipefail
trap 'echo "ABORT. Error on line $LINENO (exit code $?)"' ERR

SCRIPT="set timeout 60; spawn telnet localhost 33341; expect -re {(simics|running)> };"
for CMD in "$@"; do
    CMD=${CMD//\\/\\\\}
    CMD=${CMD//\"/\\\"}
    CMD=${CMD//\$/\\\$}
    CMD=${CMD//[/\\[}
    CMD=${CMD//]/\\]}
    SCRIPT+=" send \"$CMD\r\"; expect -re {(simics|running)> };"
done
SCRIPT+=' send "\035"; expect "telnet>"; send "quit\r"'

expect -c "$SCRIPT" | tr -d '\r'
