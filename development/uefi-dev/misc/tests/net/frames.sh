#!/bin/bash
# Usage: frames.sh [port] [other port]   Raw frames from the host (frames.py): short, bad checksum, oversize, burst, broadcast storm. Needs: fresh boot, driver loaded.
. "$(dirname "$0")/../../lib.sh"
P=${1:-0}
Q=${2:-1}
FR=$DEV/misc/tools/frames/frames.py

for X in $P $Q; do
    host_setup $X
done

uefi_begin
uefi_ifconfig $P
uefi_ifconfig $Q
uefi_end

# echo <port> [frames.py echo options]: number of replies.
echo_replies() {
    local X=$1
    shift
    python3 $FR $(tap $X) echo $(host_ip $X) $(uefi_ip $X) $(mac $X) "$@" | sed -n 's/.*replies=\([0-9]*\).*/\1/p'
}

for S in 0 1 17 18 46 1000; do
    check_eq "port $P echo size $S" "$(echo_replies $P --size $S)" 1
done
check_eq "port $P bad IP checksum dropped" "$(echo_replies $P --bad-csum --wait 1)" 0
check_eq "port $P good after bad checksum" "$(echo_replies $P)" 1

# Frame > 1514 bytes (tap MTU raised for it): dropped or answered, but no hang and no damage.
ip link set $(tap $P) mtu 9000
echo "INFO oversize 1600: replies=$(echo_replies $P --size 1600 --wait 1)"
ip link set $(tap $P) mtu 1500
check_eq "port $P echo after oversize" "$(echo_replies $P)" 1

# Burst of 600 frames (Rx ring is 512): some may be lost, the port must survive.
echo "INFO burst 600: replies=$(echo_replies $P --size 0 --count 600 --wait 4)"
check_eq "port $P echo after burst" "$(echo_replies $P)" 1

# Broadcast storm on port P: port Q may slow down, but both ports must answer again once the backlog is processed.
python3 $FR $(tap $P) bcast $(host_ip $P) 20000 &
STORM=$!
R=$(echo_replies $Q --count 20 --wait 3)
wait $STORM
echo "INFO port $Q replies during storm on $P: ${R:-0} of 20"
# recovered <port>: seconds until an echo is answered (max 60).
recovered() {
    local T=0
    while [ $T -lt 60 ]; do
        [ "$(echo_replies $1 --wait 1)" = 1 ] && break
        T=$((T + 1))
    done
    echo $T
}
check_le "port $P recovers after storm (s)" "$(recovered $P)" 59
check_le "port $Q recovers after storm (s)" "$(recovered $Q)" 59
finish
