#!/bin/bash
# Usage: seed-bios-knob-tools.sh <host ip>
# Puts the BIOS knob tools (progknobs, xmlcli, BpmGen) into the host's Simics
# artifactory cache. Needed when the Simics Python has no devtools_base
# package: then Simics cannot download them itself ("'NoneType' object has
# no attribute 'download_artifact'" in has-log/simics_vm1.log).
# The files are public (no login).
set -eo pipefail
trap 'echo "ABORT. Error on line $LINENO (exit code $?)"' ERR

if [[ -z $1 ]]; then
    echo "Usage: $0 <host ip>"
    exit 1
fi

ssh "root@$1" '
set -e
U=https://simics-artifactory.devtools.intel.com/artifactory/simics-repos/pub/tools
D=/root/SimicsWorkspace/artifactory/simics-repos/pub/tools
mkdir -p $D/xmlcli
for f in progknobs_xmlcli_2.0.0.tar.gz xmlcli/xmlcli-2.1.1.tar.gz BpmGen.tar.gz; do
    [ -s $D/$f ] || curl -sSf -o $D/$f $U/$f
    ls -l $D/$f
done
'
