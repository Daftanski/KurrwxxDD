#!/bin/bash
# Usage: driver-log.sh   Scan the whole UEFI log (since boot) for driver errors. Needs: any.
. "$(dirname "$0")/../../lib.sh"
ERRORS="ASSERT|No SEM hash room|SEM (add|del).*(Error|Timeout|Not Found)|No VSI"
INFO="virtchnl2 op 53|RX SEM rules"

tr -d '\r' < $LOG | grep -aE "$ERRORS|$INFO" | cut -c1-140 | sort | uniq -c || true
N=$(tr -d '\r' < $LOG | grep -acE "$ERRORS" || true)
check "driver log" "errors=$N" "^errors=0\$"
finish
