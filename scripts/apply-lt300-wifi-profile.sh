#!/bin/sh
set -eu

RADIO="${1:-radio0}"
WIFINET="${2:-}"
COUNTRY="${3:-RU}"
CHANNEL="${4:-1}"
TXPOWER="${5:-15}"

if [ -z "$WIFINET" ]; then
    WIFINET="$(uci show wireless | sed -n 's/^wireless\.\([^=]*\)=wifi-iface$/\1/p' | head -n1)"
fi

for name in "$RADIO" "$WIFINET"; do
    echo "$name" | grep -Eq '^[A-Za-z0-9_]+$' || {
        echo "ERROR: unsafe or missing UCI section name: $name" >&2
        exit 1
    }
done
echo "$COUNTRY" | grep -Eq '^[A-Z][A-Z]$' || { echo 'ERROR: country must be two uppercase letters.' >&2; exit 1; }
echo "$CHANNEL" | grep -Eq '^[0-9]+$' || { echo 'ERROR: channel must be numeric.' >&2; exit 1; }
echo "$TXPOWER" | grep -Eq '^[0-9]+$' || { echo 'ERROR: txpower must be numeric.' >&2; exit 1; }
[ "$CHANNEL" -ge 1 ] && [ "$CHANNEL" -le 13 ] || { echo 'ERROR: expected 2.4 GHz channel 1..13.' >&2; exit 1; }
[ "$TXPOWER" -ge 1 ] && [ "$TXPOWER" -le 20 ] || { echo 'ERROR: expected txpower 1..20 dBm.' >&2; exit 1; }
[ "$(uci -q get "wireless.$RADIO" || true)" = wifi-device ] || { echo "ERROR: wireless.$RADIO is not a wifi-device." >&2; exit 1; }
[ "$(uci -q get "wireless.$WIFINET" || true)" = wifi-iface ] || { echo "ERROR: wireless.$WIFINET is not a wifi-iface." >&2; exit 1; }

stamp="$(date +%Y%m%d-%H%M%S)"
cp /etc/config/wireless "/root/wireless.before-lt300-profile-$stamp.conf"
chmod 600 "/root/wireless.before-lt300-profile-$stamp.conf"

uci set "wireless.$RADIO.country=$COUNTRY"
uci set "wireless.$RADIO.channel=$CHANNEL"
uci set "wireless.$RADIO.htmode=HT20"
uci set "wireless.$RADIO.txpower=$TXPOWER"
uci set "wireless.$RADIO.disabled=0"
uci set "wireless.$WIFINET.uapsd=0"
uci set "wireless.$WIFINET.disassoc_low_ack=0"
uci set "wireless.$WIFINET.dtim_period=1"
uci -q delete "wireless.$WIFINET.multicast_to_unicast_all" || true
uci set "wireless.$WIFINET.disabled=0"
uci commit wireless

echo "Saved LT300 Wi-Fi profile: $COUNTRY channel=$CHANNEL HT20 txpower=$TXPOWER."
echo "Backup: /root/wireless.before-lt300-profile-$stamp.conf"
echo 'Run wifi reload when connected by Ethernet, or reboot.'
