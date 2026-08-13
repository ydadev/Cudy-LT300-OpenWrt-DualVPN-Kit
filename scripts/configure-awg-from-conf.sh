#!/bin/sh
set -eu

CONF="${1:-}"
IFACE="${2:-awg0}"
PEER="${IFACE}_peer"
ZONE="$IFACE"

[ -n "$CONF" ] || { echo "Usage: $0 /tmp/client.conf [interface-name]" >&2; exit 1; }
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
JC="$(get_value Interface Jc)"
JMIN="$(get_value Interface Jmin)"
JMAX="$(get_value Interface Jmax)"
S1="$(get_value Interface S1)"
S2="$(get_value Interface S2)"
S3="$(get_value Interface S3)"
S4="$(get_value Interface S4)"
H1="$(get_value Interface H1)"
H2="$(get_value Interface H2)"
H3="$(get_value Interface H3)"
H4="$(get_value Interface H4)"
I1="$(get_value Interface I1)"
I2="$(get_value Interface I2)"
I3="$(get_value Interface I3)"
I4="$(get_value Interface I4)"
I5="$(get_value Interface I5)"
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

BACKUP="/root/pre-awg-config-$(date +%Y%m%d-%H%M%S).tar.gz"
sysupgrade -b "$BACKUP"
echo "Backup saved to $BACKUP"

uci -q delete "network.$IFACE" || true
uci -q delete "network.$PEER" || true
uci set "network.$IFACE=interface"
uci set "network.$IFACE.proto=amneziawg"
uci set "network.$IFACE.private_key=$PRIVATE_KEY"
uci -q delete "network.$IFACE.addresses" || true
for interface_address in $(printf '%s' "$ADDRESS" | tr ',' ' '); do
    [ -n "$interface_address" ] && uci add_list "network.$IFACE.addresses=$interface_address"
done
uci set "network.$IFACE.mtu=1420"
uci set "network.$IFACE.metric=10"
uci set "network.$IFACE.nohostroute=1"

set_optional() {
    option="$1"
    value="$2"
    [ -n "$value" ] && uci set "network.$IFACE.$option=$value"
}

set_optional awg_jc "$JC"
set_optional awg_jmin "$JMIN"
set_optional awg_jmax "$JMAX"
set_optional awg_s1 "$S1"
set_optional awg_s2 "$S2"
set_optional awg_s3 "$S3"
set_optional awg_s4 "$S4"
set_optional awg_h1 "$H1"
set_optional awg_h2 "$H2"
set_optional awg_h3 "$H3"
set_optional awg_h4 "$H4"
set_optional awg_i1 "$I1"
set_optional awg_i2 "$I2"
set_optional awg_i3 "$I3"
set_optional awg_i4 "$I4"
set_optional awg_i5 "$I5"

uci set "network.$PEER=amneziawg_$IFACE"
uci set "network.$PEER.description=imported_awg_peer"
uci set "network.$PEER.public_key=$PUBLIC_KEY"
[ -n "$PRESHARED_KEY" ] && uci set "network.$PEER.preshared_key=$PRESHARED_KEY"
uci set "network.$PEER.endpoint_host=$ENDPOINT_HOST"
uci set "network.$PEER.endpoint_port=$ENDPOINT_PORT"
uci set "network.$PEER.persistent_keepalive=$KEEPALIVE"
uci set "network.$PEER.route_allowed_ips=0"
uci -q delete "network.$PEER.allowed_ips" || true
for allowed in $(printf '%s' "$ALLOWED_IPS" | tr ',' ' '); do
    [ -n "$allowed" ] && uci add_list "network.$PEER.allowed_ips=$allowed"
done

uci -q get network.wwan >/dev/null && uci set network.wwan.metric='100'
uci -q get network.wwan6 >/dev/null && uci set network.wwan6.metric='100'

uci -q delete "firewall.$ZONE" || true
uci set "firewall.$ZONE=zone"
uci set "firewall.$ZONE.name=$ZONE"
uci add_list "firewall.$ZONE.network=$IFACE"
uci set "firewall.$ZONE.input=REJECT"
uci set "firewall.$ZONE.output=ACCEPT"
uci set "firewall.$ZONE.forward=REJECT"
uci set "firewall.$ZONE.masq=1"
uci set "firewall.$ZONE.mtu_fix=1"

uci -q delete "firewall.lan_to_$ZONE" || true
uci set "firewall.lan_to_$ZONE=forwarding"
uci set "firewall.lan_to_$ZONE.src=lan"
uci set "firewall.lan_to_$ZONE.dest=$ZONE"

for forwarding in $(uci show firewall | sed -n 's/^\(firewall\.[^=]*\)=forwarding$/\1/p'); do
    src="$(uci -q get "$forwarding.src" || true)"
    dest="$(uci -q get "$forwarding.dest" || true)"
    [ "$src" = 'lan' ] && [ "$dest" = 'wan' ] && uci set "$forwarding.enabled=0"
done

if [ -n "$DNS" ]; then
    uci set dhcp.@dnsmasq[0].noresolv='1'
    uci -q delete dhcp.@dnsmasq[0].server || true
    for server in $(printf '%s' "$DNS" | tr ',' ' '); do
        [ -n "$server" ] && uci add_list "dhcp.@dnsmasq[0].server=$server"
    done
fi

uci commit network
uci commit firewall
uci commit dhcp

echo 'Configuration committed. Secrets are intentionally not printed.'
echo "Endpoint: $ENDPOINT_HOST:$ENDPOINT_PORT"
echo "Interface address: $ADDRESS"
echo 'Apply with:'
echo '  /etc/init.d/network restart'
echo '  /etc/init.d/firewall restart'
echo '  /etc/init.d/dnsmasq restart'
echo "Then delete the temporary config: rm -f '$CONF'"
