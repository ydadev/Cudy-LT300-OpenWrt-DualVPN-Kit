#!/bin/sh
set -eu

CONF="${1:-}"
IFACE="${2:-wg0}"
PEER="${IFACE}_peer"

[ -n "$CONF" ] || { echo "Usage: $0 /tmp/wireguard.conf [interface-name]" >&2; exit 1; }
[ -r "$CONF" ] || { echo "ERROR: cannot read $CONF" >&2; exit 1; }
echo "$IFACE" | grep -Eq '^[A-Za-z0-9_]+$' || { echo 'ERROR: unsafe interface name.' >&2; exit 1; }
chmod 600 "$CONF"

get_value() {
    section="$1"
    wanted="$2"
    awk -v section="[$section]" -v wanted="$wanted" '
        function trim(s) { sub(/^[ \t\r]+/, "", s); sub(/[ \t\r]+$/, "", s); return s }
        /^[ \t]*\[/ { current=trim($0); next }
        current == section {
            pos=index($0, "=")
            if (pos > 0) {
                key=trim(substr($0, 1, pos-1))
                if (key == wanted) { print trim(substr($0, pos+1)); exit }
            }
        }
    ' "$CONF"
}

PRIVATE_KEY="$(get_value Interface PrivateKey)"
ADDRESS="$(get_value Interface Address)"
DNS="$(get_value Interface DNS)"
PUBLIC_KEY="$(get_value Peer PublicKey)"
PRESHARED_KEY="$(get_value Peer PresharedKey)"
ALLOWED_IPS="$(get_value Peer AllowedIPs)"
ENDPOINT="$(get_value Peer Endpoint)"
KEEPALIVE="$(get_value Peer PersistentKeepalive)"

[ -n "$PRIVATE_KEY" ] || { echo 'ERROR: Interface.PrivateKey is missing.' >&2; exit 1; }
[ -n "$ADDRESS" ] || { echo 'ERROR: Interface.Address is missing.' >&2; exit 1; }
[ -n "$PUBLIC_KEY" ] || { echo 'ERROR: Peer.PublicKey is missing.' >&2; exit 1; }
[ -n "$ENDPOINT" ] || { echo 'ERROR: Peer.Endpoint is missing.' >&2; exit 1; }
[ -n "$ALLOWED_IPS" ] || ALLOWED_IPS='0.0.0.0/0, ::/0'
[ -n "$KEEPALIVE" ] || KEEPALIVE='25'

case "$ENDPOINT" in
    \[*\]:*) ENDPOINT_HOST="$(printf '%s' "$ENDPOINT" | sed 's/^\[\(.*\)\]:[0-9][0-9]*$/\1/')"; ENDPOINT_PORT="${ENDPOINT##*:}" ;;
    *:*) ENDPOINT_HOST="${ENDPOINT%:*}"; ENDPOINT_PORT="${ENDPOINT##*:}" ;;
    *) ENDPOINT_HOST="$ENDPOINT"; ENDPOINT_PORT='51820' ;;
esac

BACKUP="/root/pre-wireguard-config-$(date +%Y%m%d-%H%M%S).tar.gz"
sysupgrade -b "$BACKUP"
echo "Backup saved to $BACKUP"

uci -q delete "network.$IFACE" || true
uci -q delete "network.$PEER" || true
uci set "network.$IFACE=interface"
uci set "network.$IFACE.proto=wireguard"
uci set "network.$IFACE.private_key=$PRIVATE_KEY"
uci set "network.$IFACE.mtu=1420"
uci set "network.$IFACE.metric=10"
uci set "network.$IFACE.nohostroute=1"
for interface_address in $(printf '%s' "$ADDRESS" | tr ',' ' '); do
    [ -n "$interface_address" ] && uci add_list "network.$IFACE.addresses=$interface_address"
done
for dns_entry in $(printf '%s' "$DNS" | tr ',' ' '); do
    case "$dns_entry" in
        *:*) uci add_list "network.$IFACE.dns=$dns_entry" ;;
        *[!0-9.]*) uci add_list "network.$IFACE.dns_search=$dns_entry" ;;
        *) uci add_list "network.$IFACE.dns=$dns_entry" ;;
    esac
done

uci set "network.$PEER=wireguard_$IFACE"
uci set "network.$PEER.description=imported_wireguard_peer"
uci set "network.$PEER.public_key=$PUBLIC_KEY"
[ -n "$PRESHARED_KEY" ] && uci set "network.$PEER.preshared_key=$PRESHARED_KEY"
uci set "network.$PEER.endpoint_host=$ENDPOINT_HOST"
uci set "network.$PEER.endpoint_port=$ENDPOINT_PORT"
uci set "network.$PEER.persistent_keepalive=$KEEPALIVE"
uci set "network.$PEER.route_allowed_ips=0"
for allowed in $(printf '%s' "$ALLOWED_IPS" | tr ',' ' '); do
    [ -n "$allowed" ] && uci add_list "network.$PEER.allowed_ips=$allowed"
done

uci -q get network.wwan >/dev/null && uci set network.wwan.metric='100'
uci -q get network.wwan6 >/dev/null && uci set network.wwan6.metric='100'

uci commit network
if [ -n "$(uci -q get vpnmode.main.mode || true)" ]; then
    uci set "vpnmode.main.wg_endpoint=$ENDPOINT_HOST"
    uci set "vpnmode.main.wg_port=$ENDPOINT_PORT"
    uci commit vpnmode
fi

echo 'WireGuard configuration committed. Secrets are intentionally not printed.'
echo 'DNS IPs and search domains were imported into the WG interface; LAN DHCP was not changed.'
echo 'The peer has route_allowed_ips=0 for safe dual-VPN routing.'
echo 'Reload netifd once if WireGuard packages were installed in the current boot:'
echo '  /etc/init.d/network restart'
echo "Then delete the temporary config: rm -f '$CONF'"
