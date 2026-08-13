#!/bin/sh

OUT="/tmp/wifi-load-monitor.log"
PHY="/sys/kernel/debug/ieee80211/phy0"

: > "$OUT"
i=0
while [ "$i" -lt 300 ]; do
    {
        printf '\n=== '
        date '+%Y-%m-%d %H:%M:%S'
        cat /proc/loadavg
        printf 'aql_enable='; cat "$PHY/aql_enable" 2>/dev/null
        printf 'num_sta_ps='; cat "$PHY/netdev:phy0-ap0/num_sta_ps" 2>/dev/null
        printf 'total_ps_buffered='; cat "$PHY/total_ps_buffered" 2>/dev/null
        cat "$PHY/aql_pending" 2>/dev/null
        cat "$PHY/mt76/xmit-queues" 2>/dev/null
        iw dev phy0-ap0 station dump 2>/dev/null | \
            grep -E '^(Station|[[:space:]]+(inactive time|tx packets|tx retries|tx failed|signal:|tx bitrate|rx bitrate|connected time):)'
    } >> "$OUT" 2>&1
    i=$((i + 1))
    sleep 1
done
