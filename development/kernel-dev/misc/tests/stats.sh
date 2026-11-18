#!/bin/bash
# Usage: stats.sh [port] [n]   Host sends n pings (default port 0, 20): guest per-queue rx/tx_q-*_pkts grow by >= n-1; VSI counters (ethtool rx/tx-unicast, ip -s) INFO only, HWSTATS=1 checks them. Needs: ixd.sh done, port not in a bridge. Changes: port (restored). Time: ~15 s.
. "$(dirname "$0")/../lib.sh"
P=${1:-0}
N=${2:-20}
guest_need
dmesg_mark
port_up $P || finish
D=${PORT_DEV[$P]}

# counters: "<sum rx_q-*_pkts> <sum tx_q-*_pkts> <vport rx-unicast> <vport tx-unicast> <rtnl rx> <rtnl tx>"
# Queue counters are the driver's own; vport + rtnl come from the VSI HW
# counters (ixd_read_vport_stats), 0 in Simics so far: INFO only, HWSTATS=1 checks them.
counters() {
    g "ethtool -S $D; echo rx_packets: \$(cat /sys/class/net/$D/statistics/rx_packets); echo tx_packets: \$(cat /sys/class/net/$D/statistics/tx_packets)" |
        awk -F': *' '{ gsub(/^ +/, "", $1) }
            $1 ~ /^rx_q-[0-9]+_pkts$/ { qrx += $2 }  $1 ~ /^tx_q-[0-9]+_pkts$/ { qtx += $2 }
            $1 == "rx-unicast_pkts" { erx = $2 }    $1 == "tx-unicast_pkts" { etx = $2 }
            $1 == "rx_packets" { rx = $2 }          $1 == "tx_packets" { tx = $2 }
            END { print qrx + 0, qtx + 0, erx + 0, etx + 0, rx + 0, tx + 0 }'
}

sleep 3
read -r QRX0 QTX0 ERX0 ETX0 RX0 TX0 <<< "$(counters)"
check "port $P host->guest" "$(host_ping $P $N -i 0.2)" " ($N|$((N - 1))) received"
sleep 3
read -r QRX1 QTX1 ERX1 ETX1 RX1 TX1 <<< "$(counters)"

# One ping may be lost: N-1 echo requests in, replies out.
check_ge "port $P rx_q-*_pkts +" $((QRX1 - QRX0)) $((N - 1))
check_ge "port $P tx_q-*_pkts +" $((QTX1 - QTX0)) $((N - 1))
if [ "$HWSTATS" = 1 ]; then
    check_ge "port $P ethtool rx-unicast_pkts +" $((ERX1 - ERX0)) $((N - 1))
    check_ge "port $P ethtool tx-unicast_pkts +" $((ETX1 - ETX0)) $((N - 1))
    check_ge "port $P rx_packets +" $((RX1 - RX0)) $((N - 1))
    check_ge "port $P tx_packets +" $((TX1 - TX0)) $((N - 1))
else
    echo "INFO VSI counters + (HWSTATS=1 checks): rx-unicast $((ERX1 - ERX0)) tx-unicast $((ETX1 - ETX0)) rx_packets $((RX1 - RX0)) tx_packets $((TX1 - TX0))"
fi

port_down $P
check_dmesg "dmesg clean"
finish
