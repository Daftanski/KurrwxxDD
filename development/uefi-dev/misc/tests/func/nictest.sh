#!/bin/bash
# Usage: nictest.sh   Protocol members via nictest.efi: ComponentName2, DriverHealth, AIP, FMP, NII/!PXE, SNP, EFI version, UNDI bad commands. Needs: driver loaded.
. "$(dirname "$0")/../../lib.sh"
N=$(wc -w <<< "$ALL_PORTS")
CMDS="cn2 health aip fmp nii snp ver cdb hiirc snpf"

for Q in $ALL_PORTS; do
    host_setup $Q
done

uefi_begin
for C in $CMDS; do
    uefi_part $C
    uefi_cmd "nictest.efi $C" 'NICTEST done.*FS1:'
done
# Data path must still work after snpf changed and restored the filters.
uefi_part ping
for Q in $ALL_PORTS; do
    uefi_ifconfig $Q
    uefi_ping $Q 2
done
uefi_part END
uefi_end

OUT=$(uefi_log)
# t <cmd> <line regex>: NICTEST lines of one subcommand that match.
t() { log_part "$OUT" $1 | grep -aE "^NICTEST $2" || true; }
# all_match <label> <lines> <regex>: every line matches, and there is at least one.
all_match() {
    local BAD
    BAD=$(grep -avcE "$3" <<< "$2" || true)
    check "$1" "lines=$(grep -ac . <<< "$2" || true) bad=$BAD" "^lines=[1-9][0-9]* bad=0\$"
}

check "find" "$(t cn2 find)" "status=Success .*children=$N\b"

all_match "cn2 every language" "$(t cn2 'cn2 driver lang=[a-wyz]')" "status=Success name=.*CNIC"
check "cn2 bad language" "$(t cn2 'cn2 driver lang=xx-XX')" "status=Unsupported"
check "cn2 NULL language" "$(t cn2 'cn2 driver lang=NULL')" "status=Invalid Parameter"
check "cn2 NULL name" "$(t cn2 'cn2 driver name=NULL')" "status=Invalid Parameter"
all_match "cn2 controller names" "$(t cn2 'cn2 ctrl [0-9]')" "status=Success name=."
all_match "cn2 child names" "$(t cn2 'cn2 child [0-9]')" "status=(Success name=.|Unsupported)"
check "cn2 foreign controller" "$(t cn2 'cn2 ctrl foreign')" "status=Unsupported"

check "health driver" "$(t health 'health driver')" "status=Success health=0 "
all_match "health controllers" "$(t health 'health ctrl [0-9]')" "status=Success health=0 "
all_match "health children" "$(t health 'health child [0-9]')" "status=(Success health=0 |Unsupported)"
check "health foreign controller" "$(t health 'health ctrl foreign')" "status=Unsupported"

all_match "aip types" "$(t aip 'aip [0-9]+ types')" "status=Success count=[1-9]"
all_match "aip get each type" "$(t aip 'aip [0-9]+ get [0-9A-F]')" "status=Success size=[1-9]"
all_match "aip media state" "$(t aip 'aip [0-9]+ media')" "state=Success"
all_match "aip unknown type" "$(t aip 'aip [0-9]+ get unknown')" "status=Unsupported"
all_match "aip set media" "$(t aip 'aip [0-9]+ set media')" "status=(Unsupported|Write Protected)"

all_match "fmp info" "$(t fmp 'fmp [0-9]+ info ')" "status=Success .*count=[1-9]"
all_match "fmp image" "$(t fmp 'fmp [0-9]+ image')" "index=[1-9][0-9]* .*version=[0-9a-fA-F]+ "
all_match "fmp empty image" "$(t fmp 'fmp [0-9]+ check empty')" "(status=(Invalid Parameter|Unsupported|Aborted|Bad Buffer Size)|updatable=(0|[2-9a-f][0-9a-f]*)\b)"
all_match "fmp junk image" "$(t fmp 'fmp [0-9]+ check junk')" "(status=(Invalid Parameter|Unsupported|Aborted|Security Violation)|updatable=(0|[2-9a-f][0-9a-f]*)\b)"
all_match "fmp bad index" "$(t fmp 'fmp [0-9]+ check badindex')" "status=(Invalid Parameter|Unsupported|Not Found)"
all_match "fmp NULL image" "$(t fmp 'fmp [0-9]+ check null')" "status=Invalid Parameter"
# SetImage with bad images must fail (nothing is written).
all_match "fmp set junk fails" "$(t fmp 'fmp [0-9]+ set junk')" "status=[^S]"
all_match "fmp set null fails" "$(t fmp 'fmp [0-9]+ set null')" "status=[^S]"
all_match "fmp set empty fails" "$(t fmp 'fmp [0-9]+ set empty')" "status=[^S]"

all_match "nii revision / type" "$(t nii 'nii [0-9]+ revision')" "revision=[0-9a-f]+ type=[12] "
all_match "nii !PXE struct" "$(t nii 'nii [0-9]+ pxe')" "signature=1 len=[1-9][0-9]* sum=0 "
check_eq "nii unique ifnum" "$(t nii 'nii [0-9]+ revision' | grep -ao 'ifnum=[0-9]*' | sort -u | wc -l)" $N

all_match "snp mode" "$(t snp 'snp [0-9]+ mode')" "maxpacket=1500 header=14 "
all_match "snp mac" "$(t snp 'snp [0-9]+ mac')" "current=([0-9A-F]{12}) permanent=\1"
all_match "snp stats" "$(t snp 'snp [0-9]+ stats')" "status=(Success|Unsupported)"
all_match "snp mcast ipv4" "$(t snp 'snp [0-9]+ mcast4')" "status=Success mac=01005E000001"
all_match "snp mcast ipv6" "$(t snp 'snp [0-9]+ mcast6')" "status=Success mac=333300000001"

check "efi version" "$(t ver ver)" "status=Success length=[1-9][0-9]* version=[1-9a-f]"

# UNDI CDB: a good command works, bad ones return a StatCode (not 0) and do not crash.
all_match "cdb getstate" "$(t cdb 'cdb [0-9]+ getstate stat')" "stat=0 flags=[cC]00[0-3]"
# UNDI Reset in the Initialized state works (SNP Reset returns Invalid Parameter: see snpstate.sh).
all_match "cdb reset" "$(t cdb 'cdb [0-9]+ reset stat')" "stat=0 flags=[cC]00[0-3]"
for B in badopcode badifnum getstate-baddb start-nocpb transmit-nocpb receive-nocpb getstatus-nulldb; do
    all_match "cdb $B" "$(t cdb "cdb [0-9]+ $B ")" "stat=[1-9a-f][0-9a-f]* "
done

# HII config access with bad strings: always an error, never a crash.
for B in "route null" "route garbage" "route badguid" "route badoffset" "route long" "extract garbage" "extract noprogress"; do
    all_match "hiirc $B" "$(t hiirc "hiirc [0-9]+ $B ")" "status=[^S]"
done

all_match "snpf start" "$(t snpf 'snpf [0-9]+ start')" "state=2 "
all_match "snpf enable" "$(t snpf 'snpf [0-9]+ enable')" "status=(Success supported=1 set=1|Invalid Parameter supported=0 set=0)"
all_match "snpf disable" "$(t snpf 'snpf [0-9]+ disable')" "status=Success set=0"
all_match "snpf mcast add" "$(t snpf 'snpf [0-9]+ mcast add')" "status=Success count=1\b"
# SNP (BIOS code, not ours) decides this one; seen: Success.
all_match "snpf mcast unicast" "$(t snpf 'snpf [0-9]+ mcast unicast')" "status=(Invalid Parameter|Success)"
all_match "snpf mcast reset" "$(t snpf 'snpf [0-9]+ mcast reset')" "status=Success count=0\b"
all_match "snpf restore" "$(t snpf 'snpf [0-9]+ restore')" "status=Success "
all_match "snpf station new" "$(t snpf 'snpf [0-9]+ station new')" "status=(Success changeable=1 same=1|(Unsupported|Device Error) changeable=0)"
all_match "snpf station reset" "$(t snpf 'snpf [0-9]+ station reset')" "status=(Success|Unsupported) permanent=1"
all_match "snpf stats reset" "$(t snpf 'snpf [0-9]+ stats reset')" "status=(Success|Unsupported)"
R=$(log_part "$OUT" ping)
for Q in $ALL_PORTS; do
    check "ping after snpf: port $Q" "$(ping_result "$R" $(host_ip $Q))" " 2 received"
done
finish
