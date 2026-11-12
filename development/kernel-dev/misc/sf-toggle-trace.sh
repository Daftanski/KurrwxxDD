#!/bin/bash
# Trace SF repr<->vport connect/disconnect while toggling SF state.
# Run on the guest. Arg 1: devlink PF handle (default pci/0001:fb:00.0).
DL=${1:-pci/0001:fb:00.0}
T=/sys/kernel/debug/tracing

echo 0 > $T/tracing_on
echo > $T/trace
echo > $T/kprobe_events
echo 'p:sfconn ixd:ixd_esw_connect_sf port_id=%dx:u64 vsi=%cx:u64' >> $T/kprobe_events
echo 'r:sfconn_ret ixd:ixd_esw_connect_sf ret=$retval:s32' >> $T/kprobe_events
echo 'p:eswconn libie_eswitch:libie_esw_connect repr_idx=%si:u64 vsi=%dx:u64' >> $T/kprobe_events
echo 'p:sfdisc ixd:ixd_esw_disconnect_sf vsi=%dx:u64' >> $T/kprobe_events
echo 'p:eswdisc libie_eswitch:libie_esw_disconnect vsi=%si:u64' >> $T/kprobe_events
echo 'p:sfprobe ixd:ixd_sf_dev_probe' >> $T/kprobe_events
echo 'p:sfremove ixd:ixd_sf_dev_remove' >> $T/kprobe_events
echo 'p:linkchg ixd:ixd_vport_link_change' >> $T/kprobe_events
echo 1 > $T/events/kprobes/enable
echo 1 > $T/tracing_on

dmesg -C
echo "== ports before"
devlink port show | grep -E "pcisf|virtual"

echo "== toggle back-to-back"
devlink port function set $DL/0 state inactive
devlink port function set $DL/1 state inactive
# Arg 2 = "rev": activate port 1 first. Old first-unconnected scan
# would bind SF1's VSI to port 0 here.
if [[ "$2" == "rev" ]]; then
	devlink port function set $DL/1 state active
	sleep 5
	devlink port function set $DL/0 state active
else
	devlink port function set $DL/0 state active
	devlink port function set $DL/1 state active
fi
sleep 20

echo "== ports after"
devlink port show | grep -E "pcisf|virtual"
echo "== trace"
grep -vE "^#" $T/trace
echo "== dmesg"
dmesg | grep -iE "connect|vport table|error|warn|oops|BUG" | head -40

echo 0 > $T/events/kprobes/enable
echo > $T/kprobe_events
