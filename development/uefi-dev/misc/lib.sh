# Shared code for tests/*/*.sh. Usage: . "$(dirname "$0")/../../lib.sh"
# Rules: see misc/readme.txt "Rules".
set -eo pipefail
trap 'echo "ABORT. Error on line $LINENO (exit code $?)"' ERR

DEV=/root/SimicsWorkspace/development/uefi-dev
LOG=$DEV/logs/uefi_serial.log
DRIVER=${DRIVER:-E4999X10.EFI}
ALL_PORTS="0 1 2 3 4 5 6 7"
NAME=$(basename "$0" .sh)
FAILS=0

# --- Ports -------------------------------------------------------------------
# Port P: UEFI eth<P+1> = 192.168.P.101, MAC 0A:0P:00:08:03:18 <-> host cnic_tap_0_P = 192.168.P.200
# PFP mode (launch-simics.sh wrote TRUE to logs/pfp): MAC 0A:00:00:0P:03:1P
tap()     { echo cnic_tap_0_$1; }
eth()     { echo eth$(($1 + 1)); }
uefi_ip() { echo 192.168.$1.101; }
host_ip() { echo 192.168.$1.200; }
if [[ "$(cat $DEV/logs/pfp 2>/dev/null)" == TRUE ]]; then
    mac()     { echo 0A:00:00:0$1:03:1$1; }
    mac_hex() { echo 0A00000${1}031${1}; }
else
    mac()     { echo 0A:0$1:00:08:03:18; }
    mac_hex() { echo 0A0${1}00080318; }
fi

host_setup() {
    ip addr replace $(host_ip $1)/24 dev $(tap $1)
}

# host_ping <port> <ip> <count> [ping args]: "packets transmitted" line of a host ping.
host_ping() {
    ping -c $3 -W 3 -I $(tap $1) "${@:4}" $2 2>&1 | grep transmitted || true
}

# --- UEFI Shell session: uefi_begin, uefi_cmd ..., uefi_end, then uefi_log ---
uefi_begin() {
    MARK=${1:-$NAME}-$$
    SCRIPT='set timeout 300; match_max 100000; spawn telnet localhost 33441; send "\r"; expect -re {Shell>|FS1:}; send "fs1:\r"; expect "FS1:";'
    uefi_cmd "echo BEGIN-$MARK"
}

# uefi_cmd <command> [regex to wait for, default FS1:]
uefi_cmd() {
    local CMD=$1
    CMD=${CMD//\\/\\\\}
    CMD=${CMD//\"/\\\"}
    CMD=${CMD//\$/\\\$}
    CMD=${CMD//[/\\[}
    CMD=${CMD//]/\\]}
    SCRIPT+=" send \"$CMD\r\"; expect -re {${2:-FS1:}};"
}

uefi_load()     { uefi_cmd "load $DRIVER" 'Image.*FS1:'; }
# uefi_part <name>: marker line; log_part cuts the log at it.
uefi_part()     { uefi_cmd "echo PART $1"; }
uefi_ifconfig() { uefi_cmd "ifconfig -s $(eth $1) static $(uefi_ip $1) 255.255.255.0 192.168.$1.1"; }
uefi_ping()     { uefi_cmd "ping -n $2 -s $(uefi_ip $1) $(host_ip $1)" '(packets transmitted|No configured interfaces).*FS1:'; }

# Tcl var h = driver handle (first column of its "drivers" line, wrapped in ANSI colors).
uefi_driver_handle() {
    SCRIPT+=' send "drivers\r"; expect -re {([0-9A-Fa-f]+)\x1b\[0m[^\n]*'$DRIVER'}; set h $expect_out(1,string); expect "FS1:";'
}

# Tcl vars h = driver, c = first controller, ctrls = all controllers (PFP: one per port),
# kids = child handles (from "dh -d $h").
uefi_handles() {
    uefi_driver_handle
    SCRIPT+=' send "dh -d $h\r"; expect "FS1:"; set out $expect_out(buffer);'
    SCRIPT+=' regexp {Ctrl\[(?:\x1b\[[0-9;]*m)*([0-9A-Fa-f]+)} $out -> c;'
    SCRIPT+=' set ctrls {}; foreach {- x} [regexp -all -inline {Ctrl\[(?:\x1b\[[0-9;]*m)*([0-9A-Fa-f]+)} $out] { lappend ctrls $x };'
    SCRIPT+=' set kids {}; foreach {- k} [regexp -all -inline {Child\[(?:\x1b\[[0-9;]*m)*([0-9A-Fa-f]+)} $out] { lappend kids $k };'
}

# uefi_tcl <command>: shell command with Tcl vars ($h, $c, $k); no escaping.
uefi_tcl()        { SCRIPT+=" send \"$1\r\"; expect \"FS1:\";"; }
# uefi_each_child <command>: run it once per child, $k = child handle. Needs uefi_handles.
uefi_each_child() { SCRIPT+=" foreach k \$kids { send \"$1\r\"; expect \"FS1:\" };"; }
# uefi_each_ctrl <command>: run it once per controller, $c = controller handle. Needs uefi_handles.
uefi_each_ctrl()  { SCRIPT+=" foreach c \$ctrls { send \"$1\r\"; expect \"FS1:\" };"; }

uefi_unload() {
    uefi_driver_handle
    uefi_tcl 'unload -n $h'
}

uefi_end() {
    uefi_cmd "echo END-$MARK"
    SCRIPT+=' send "\035"; expect "telnet>"; send "quit\r"'
    expect -c "$SCRIPT" > /dev/null 2>&1
    # Simics writes the serial log late.
    for I in $(seq 1 30); do
        grep -aq "^END-$MARK" $LOG && return 0
        sleep 1
    done
    echo "WARNING: END-$MARK not found in $LOG" >&2
}

# --- Log parsing -------------------------------------------------------------
# Console output of the last session, without CR and ANSI codes. Also saved to /tmp/<test>.log.
uefi_log() {
    tr -d '\r' < $LOG | sed 's/\x1b\[[0-9;]*[A-Za-z]//g' | sed -n "/^BEGIN-$MARK\$/,/^END-$MARK\$/p" | tee /tmp/$NAME.log
}

# log_part <text> <name>: lines from "PART <name>" to the next "PART" line.
log_part() {
    sed -n "/^PART $2\$/,/^PART /p" <<< "$1"
}

# cmd_out <text> <command>: output of one shell command (exact command line).
cmd_out() {
    awk -v c="FS1:\\\\> $2" '{ sub(/ +$/, "") } $0 == c { p = 1; next } /^FS1:\\> / { p = 0 } p' <<< "$1"
}

# ping_result <text> <ping target, e.g. "192.168.0.200" or "192.168.0.200 4000 data">
ping_result() {
    grep -a -A12 "^Ping $2 " <<< "$1" | grep -a -m1 "packets transmitted" || true
}

# child_handles <text>: child handles from "dh -d" output, port order.
child_handles() {
    grep -ao "Child\[[0-9A-Fa-f]*\]" <<< "$1" | sed 's/Child\[\(.*\)\]/\1/' || true
}

# driver_line <text> [command, default drivers]: our line of the "drivers" output.
# "1BD 04099900 B - X  1  8 Intel(R) CNIC Driver 4.9.99  \E4999X10.EFI"
driver_line() {
    cmd_out "$1" "${2:-drivers}" | grep -a -m1 "$DRIVER" || true
}

# driver_name <driver line>: name column only.
driver_name() {
    awk '{ $1 = $2 = $3 = $4 = $5 = $6 = $7 = $NF = ""; print }' <<< "$1" | sed 's/^ *//; s/ *$//'
}

# --- HII (hii.efi = hii-test-tool, see tools/hii/) ----------------------------
HII_MAIN_FORM=0x200

# hii_formset <"hii.efi list" output> <port>: formset ID of the port (title ends with its MAC).
hii_formset() {
    grep -a " - $(mac $2) *\$" <<< "$1" | awk '{ print $1 }' | head -1
}

# hii_fields <"hii.efi show" output>: "prompt=value" lines. Driver debug lines may be mixed in.
hii_fields() {
    grep -aoE '(prompt|value): "[^"]*"' <<< "$1" | awk -F'"' '/^prompt/ { p = $2; next } { print p "=" $2 }' || true
}

# hii_value <fields> <prompt>
hii_value() {
    grep -a -m1 "^$2=" <<< "$1" | cut -d= -f2- || true
}

# --- Results -----------------------------------------------------------------
# check <label> <detail> <regex the detail must match>
check() {
    if [[ $2 =~ $3 ]]; then
        echo "PASS $1 ($2)"
    else
        echo "FAIL $1 ($2)"
        FAILS=$((FAILS + 1))
    fi
}

# check_eq <label> <got> <want>
check_eq() {
    if [ "$2" = "$3" ]; then
        echo "PASS $1 ($2)"
    else
        echo "FAIL $1 (got '$2', want '$3')"
        FAILS=$((FAILS + 1))
    fi
}

# check_le <label> <number> <max>
check_le() {
    if [ "${2:-x}" -le "$3" ] 2> /dev/null; then
        echo "PASS $1 ($2 <= $3)"
    else
        echo "FAIL $1 (got '$2', max $3)"
        FAILS=$((FAILS + 1))
    fi
}

finish() {
    exit $((FAILS > 0))
}
