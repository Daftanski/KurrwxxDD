#!/bin/bash
# Usage: stats.sh [A:B] [n]   Loopback pair (default 0:1, 20): n pings A->B; per-queue rx/tx_q-*_pkts grow by >= n-1 on both ports; VSI counters (ethtool rx/tx-unicast, ip -s) INFO only, HWSTATS=1 checks them. Needs: ixd.sh done, ports not in a bridge. Changes: ports, host taps (restored). Time: ~30 s.
. "$(dirname "$0")/../lib.sh"
read -r A B <<< "$(pair_split $1)"
N=${2:-20}
guest_need
dmesg_mark
loop_up $A $B || finish

# counters <g|gb> <dev>: "<sum rx_q-*_pkts> <sum tx_q-*_pkts> <vport rx-unicast> <vport tx-unicast> <rtnl rx> <rtnl tx>"
# Queue counters are the driver's own; vport + rtnl come from the VSI HW
# counters (ixd_read_vport_stats), 0 in Simics so far: INFO only, HWSTATS=1 checks them.
counters() {
    $1 "ethtool -S $2; echo rx_packets: \$(cat /sys/class/net/$2/statistics/rx_packets); echo tx_packets: \$(cat /sys/class/net/$2/statistics/tx_packets)" |
        awk -F': *' '{ gsub(/^ +/, "", $1) }
            $1 ~ /^rx_q-[0-9]+_pkts$/ { qrx += $2 }  $1 ~ /^tx_q-[0-9]+_pkts$/ { qtx += $2 }
            $1 == "rx-unicast_pkts" { erx = $2 }    $1 == "tx-unicast_pkts" { etx = $2 }
            $1 == "rx_packets" { rx = $2 }          $1 == "tx_packets" { tx = $2 }
            END { print qrx + 0, qtx + 0, erx + 0, etx + 0, rx + 0, tx + 0 }'
}

sleep 3
read -r AQR0 AQT0 AER0 AET0 AR0 AT0 <<< "$(counters g $LOOP_DEV_A)"
read -r BQR0 BQT0 BER0 BET0 BR0 BT0 <<< "$(counters gb $LOOP_DEV_B)"
check "port $A -> port $B" "$(loop_ping_ab $N)" " ($N|$((N - 1))) received"
sleep 3
read -r AQR1 AQT1 AER1 AET1 AR1 AT1 <<< "$(counters g $LOOP_DEV_A)"
read -r BQR1 BQT1 BER1 BET1 BR1 BT1 <<< "$(counters gb $LOOP_DEV_B)"

# A sends requests and gets replies, B the other way. One ping may be lost.
M=$((N - 1))
check_ge "port $A tx_q-*_pkts +" $((AQT1 - AQT0)) $M
check_ge "port $A rx_q-*_pkts +" $((AQR1 - AQR0)) $M
check_ge "port $B rx_q-*_pkts +" $((BQR1 - BQR0)) $M
check_ge "port $B tx_q-*_pkts +" $((BQT1 - BQT0)) $M
if [ "$HWSTATS" = 1 ]; then
    check_ge "port $A ethtool tx-unicast_pkts +" $((AET1 - AET0)) $M
    check_ge "port $A ethtool rx-unicast_pkts +" $((AER1 - AER0)) $M
    check_ge "port $B ethtool rx-unicast_pkts +" $((BER1 - BER0)) $M
    check_ge "port $B ethtool tx-unicast_pkts +" $((BET1 - BET0)) $M
    check_ge "port $A tx_packets +" $((AT1 - AT0)) $M
    check_ge "port $B rx_packets +" $((BR1 - BR0)) $M
else
    echo "INFO VSI counters + (HWSTATS=1 checks): port $A tx-unicast $((AET1 - AET0)) rx-unicast $((AER1 - AER0)) tx_packets $((AT1 - AT0)); port $B rx-unicast $((BER1 - BER0)) tx-unicast $((BET1 - BET0)) rx_packets $((BR1 - BR0))"
fi

loop_down
check_dmesg "dmesg clean"
finish
