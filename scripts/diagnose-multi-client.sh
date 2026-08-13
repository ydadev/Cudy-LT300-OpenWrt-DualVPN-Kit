#!/bin/sh
set -u

PROBE="${1:-$(uci -q get vpnmode.main.probe_ip || echo 1.1.1.1)}"
MODE="$(uci -q get vpnmode.main.mode || echo wg)"
case "$MODE" in
    wg) VPN_IF="$(uci -q get vpnmode.main.wg_if || echo wg0)"; VPN_CMD='wg' ;;
    awg) VPN_IF="$(uci -q get vpnmode.main.awg_if || echo awg0)"; VPN_CMD='awg' ;;
    *) VPN_IF='wg0'; VPN_CMD='wg' ;;
esac
WIFI_IF="$(iw dev 2>/dev/null | awk '$1 == "Interface" { print $2; exit }')"

echo '=== TIME / LOAD / MEMORY ==='
date -u
uptime
free
df -h /overlay /tmp

echo '=== CONNTRACK ==='
printf 'count='; cat /proc/sys/net/netfilter/nf_conntrack_count
printf 'max='; cat /proc/sys/net/netfilter/nf_conntrack_max

echo '=== ROUTES ==='
ip -4 route

echo '=== VPN (PEER IDS REDACTED) ==='
echo "mode=$MODE interface=$VPN_IF"
ifstatus "$VPN_IF" 2>/dev/null | jsonfilter -e '@.up' 2>/dev/null || true
"$VPN_CMD" show "$VPN_IF" latest-handshakes 2>/dev/null | awk '{ print "peer=<redacted> latest_handshake=" $2 }'
"$VPN_CMD" show "$VPN_IF" transfer 2>/dev/null | awk '{ print "peer=<redacted> rx=" $2 " tx=" $3 }'

echo '=== WIFI CONFIG (NO KEY) ==='
uci -q show wireless | grep -vE 'key=|password='

echo '=== WIFI CLIENTS (MAC REDACTED) ==='
if [ -n "$WIFI_IF" ]; then
    iw dev "$WIFI_IF" station dump 2>/dev/null | awk '
        /^Station / { station++; print "Station <redacted>-" station; next }
        /^[ \t]+(inactive time|tx retries|tx failed|signal|signal avg|tx bitrate|rx bitrate|connected time):/ { print }
    '
fi

echo '=== SMALL PING ==='
ping -I "$VPN_IF" -c 20 -W 2 "$PROBE" || true

echo '=== LARGE PING (1300 BYTE PAYLOAD) ==='
ping -I "$VPN_IF" -c 10 -W 2 -s 1300 "$PROBE" || true

echo '=== SQM / QDISC ==='
uci -q show sqm 2>/dev/null || echo 'SQM is not configured.'
if command -v tc >/dev/null 2>&1; then
    tc qdisc show dev "$VPN_IF" 2>/dev/null || true
fi

echo '=== RECENT RELEVANT LOGS (MAC REDACTED) ==='
logread | grep -Ei 'AP-STA-(DIS)?CONNECTED|oom|out of memory|nf_conntrack|table full|usb.*(reset|disconnect)|vpn-switch' | tail -n 120 | \
    sed -E 's/([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}/XX:XX:XX:XX:XX:XX/g'

echo 'NOTE: this script never runs an active Wi-Fi scan and does not change settings.'
