#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
WG_IF="${1:-wg0}"
AWG_IF="${2:-awg0}"
WWAN_IF="${3:-wwan}"
ACTIVE_MODE="${4:-wg}"
PROBE_IP="${5:-1.1.1.1}"
WG_ADMIN_NET="${6:-}"
AWG_ADMIN_NET="${7:-}"
WG_PEER="${WG_IF}_peer"
AWG_PEER="${AWG_IF}_peer"

case "$ACTIVE_MODE" in wg|awg) ;; *) echo 'ERROR: active mode must be wg or awg.' >&2; exit 1 ;; esac
for name in "$WG_IF" "$AWG_IF" "$WWAN_IF"; do
    echo "$name" | grep -Eq '^[A-Za-z0-9_]+$' || { echo "ERROR: unsafe interface name: $name" >&2; exit 1; }
done
for network in "$WG_ADMIN_NET" "$AWG_ADMIN_NET"; do
    echo "$network" | grep -Eq '^[0-9]{1,3}(\.[0-9]{1,3}){3}/[0-9]{1,2}$' || {
        echo "ERROR: invalid IPv4 admin network: $network" >&2
        exit 1
    }
done

[ "$(uci -q get "network.$WG_IF.proto" || true)" = 'wireguard' ] || { echo "ERROR: network.$WG_IF is not WireGuard." >&2; exit 1; }
[ "$(uci -q get "network.$AWG_IF.proto" || true)" = 'amneziawg' ] || { echo "ERROR: network.$AWG_IF is not AmneziaWG." >&2; exit 1; }
[ -n "$(uci -q get "network.$WWAN_IF.proto" || true)" ] || { echo "ERROR: network.$WWAN_IF does not exist." >&2; exit 1; }

WG_ENDPOINT="$(uci -q get "network.$WG_PEER.endpoint_host" || true)"
AWG_ENDPOINT="$(uci -q get "network.$AWG_PEER.endpoint_host" || true)"
WG_PORT="$(uci -q get "network.$WG_PEER.endpoint_port" || true)"
AWG_PORT="$(uci -q get "network.$AWG_PEER.endpoint_port" || true)"
[ -n "$WG_ENDPOINT" ] && [ -n "$WG_PORT" ] || { echo "ERROR: endpoint is missing in network.$WG_PEER." >&2; exit 1; }
[ -n "$AWG_ENDPOINT" ] && [ -n "$AWG_PORT" ] || { echo "ERROR: endpoint is missing in network.$AWG_PEER." >&2; exit 1; }

for file in vpn-switch vpn-apply-route vpn-restore-mode vpn-restore-mode.init 96-vpn-route; do
    [ -r "$SCRIPT_DIR/$file" ] || { echo "ERROR: missing $SCRIPT_DIR/$file" >&2; exit 1; }
    /bin/sh -n "$SCRIPT_DIR/$file"
done

BACKUP="/root/pre-dual-vpn-$(date +%Y%m%d-%H%M%S).tar.gz"
sysupgrade -b "$BACKUP"
echo "Backup saved to $BACKUP"

cp "$SCRIPT_DIR/vpn-switch" /usr/sbin/vpn-switch
cp "$SCRIPT_DIR/vpn-apply-route" /usr/sbin/vpn-apply-route
cp "$SCRIPT_DIR/vpn-restore-mode" /usr/sbin/vpn-restore-mode
cp "$SCRIPT_DIR/vpn-restore-mode.init" /etc/init.d/vpn-restore-mode
cp "$SCRIPT_DIR/96-vpn-route" /etc/hotplug.d/iface/96-vpn-route
chmod 700 /usr/sbin/vpn-switch /usr/sbin/vpn-apply-route /usr/sbin/vpn-restore-mode
chmod 755 /etc/init.d/vpn-restore-mode
chmod 755 /etc/hotplug.d/iface/96-vpn-route
ln -sf /usr/sbin/vpn-switch /usr/sbin/vpn-use-wg
ln -sf /usr/sbin/vpn-switch /usr/sbin/vpn-use-awg
ln -sf /usr/sbin/vpn-switch /usr/sbin/vpn-status
/etc/init.d/vpn-restore-mode enable

touch /etc/config/vpnmode
uci -q delete vpnmode.main || true
uci set vpnmode.main=mode
uci set "vpnmode.main.mode=$ACTIVE_MODE"
uci set "vpnmode.main.wg_if=$WG_IF"
uci set "vpnmode.main.awg_if=$AWG_IF"
uci set "vpnmode.main.wwan_if=$WWAN_IF"
uci set "vpnmode.main.wg_endpoint=$WG_ENDPOINT"
uci set "vpnmode.main.awg_endpoint=$AWG_ENDPOINT"
uci set "vpnmode.main.wg_port=$WG_PORT"
uci set "vpnmode.main.awg_port=$AWG_PORT"
uci set "vpnmode.main.probe_ip=$PROBE_IP"
uci set "vpnmode.main.wg_admin_net=$WG_ADMIN_NET"
uci set "vpnmode.main.awg_admin_net=$AWG_ADMIN_NET"
uci set vpnmode.main.auto_failover='0'
uci commit vpnmode
chmod 600 /etc/config/vpnmode

uci set "network.$WG_IF.nohostroute=1"
uci set "network.$AWG_IF.nohostroute=1"
uci set "network.$WG_PEER.route_allowed_ips=0"
uci set "network.$AWG_PEER.route_allowed_ips=0"
uci -q get "network.$WWAN_IF.metric" >/dev/null || uci set "network.$WWAN_IF.metric=100"

uci -q delete network.vpn_admin_wg_route || true
uci set network.vpn_admin_wg_route=route
uci set "network.vpn_admin_wg_route.interface=$WG_IF"
uci set "network.vpn_admin_wg_route.target=$WG_ADMIN_NET"
uci set network.vpn_admin_wg_route.metric='5'
uci -q delete network.vpn_admin_awg_route || true
uci set network.vpn_admin_awg_route=route
uci set "network.vpn_admin_awg_route.interface=$AWG_IF"
uci set "network.vpn_admin_awg_route.target=$AWG_ADMIN_NET"
uci set network.vpn_admin_awg_route.metric='5'
uci commit network

uci -q delete firewall.awg0 || true
uci -q delete firewall.lan_to_awg0 || true
uci -q delete firewall.vpn || true
uci set firewall.vpn=zone
uci set firewall.vpn.name='vpn'
uci add_list "firewall.vpn.network=$WG_IF"
uci add_list "firewall.vpn.network=$AWG_IF"
uci set firewall.vpn.input='REJECT'
uci set firewall.vpn.output='ACCEPT'
uci set firewall.vpn.forward='REJECT'
uci set firewall.vpn.masq='1'
uci set firewall.vpn.mtu_fix='1'

uci -q delete firewall.lan_to_vpn || true
uci set firewall.lan_to_vpn=forwarding
uci set firewall.lan_to_vpn.src='lan'
uci set firewall.lan_to_vpn.dest='vpn'

# Permit router administration only from the two encrypted client networks.
# This does not open TCP/22 in the WAN/LTE zone.
uci -q delete firewall.vpn_admin_ssh_wg || true
uci set firewall.vpn_admin_ssh_wg=rule
uci set firewall.vpn_admin_ssh_wg.name='Allow-SSH-from-WireGuard-network'
uci set firewall.vpn_admin_ssh_wg.src='vpn'
uci set firewall.vpn_admin_ssh_wg.family='ipv4'
uci set firewall.vpn_admin_ssh_wg.proto='tcp'
uci set "firewall.vpn_admin_ssh_wg.src_ip=$WG_ADMIN_NET"
uci set firewall.vpn_admin_ssh_wg.dest_port='22'
uci set firewall.vpn_admin_ssh_wg.target='ACCEPT'

uci -q delete firewall.vpn_admin_ssh_awg || true
uci set firewall.vpn_admin_ssh_awg=rule
uci set firewall.vpn_admin_ssh_awg.name='Allow-SSH-from-AmneziaWG-network'
uci set firewall.vpn_admin_ssh_awg.src='vpn'
uci set firewall.vpn_admin_ssh_awg.family='ipv4'
uci set firewall.vpn_admin_ssh_awg.proto='tcp'
uci set "firewall.vpn_admin_ssh_awg.src_ip=$AWG_ADMIN_NET"
uci set firewall.vpn_admin_ssh_awg.dest_port='22'
uci set firewall.vpn_admin_ssh_awg.target='ACCEPT'

for forwarding in $(uci show firewall | sed -n 's/^\(firewall\.[^=]*\)=forwarding$/\1/p'); do
    src="$(uci -q get "$forwarding.src" || true)"
    dest="$(uci -q get "$forwarding.dest" || true)"
    [ "$src" = 'lan' ] && [ "$dest" = 'wan' ] && uci set "$forwarding.enabled=0"
done

add_endpoint_exception() {
    section="$1"
    label="$2"
    endpoint="$3"
    port="$4"
    uci -q delete "firewall.$section" || true
    case "$endpoint" in
        ''|*[!0-9.]*)
            echo "WARNING: $label endpoint is not an IPv4 literal; downstream-client exception was not created." >&2
            return 0
            ;;
    esac
    uci set "firewall.$section=rule"
    uci set "firewall.$section.name=Allow-LAN-$label-Endpoint-Direct"
    uci set "firewall.$section.src=lan"
    uci set "firewall.$section.dest=wan"
    uci set "firewall.$section.family=ipv4"
    uci set "firewall.$section.proto=udp"
    uci set "firewall.$section.dest_ip=$endpoint"
    uci set "firewall.$section.dest_port=$port"
    uci set "firewall.$section.target=ACCEPT"
}

add_endpoint_exception vpn_endpoint_wg WireGuard "$WG_ENDPOINT" "$WG_PORT"
add_endpoint_exception vpn_endpoint_awg AmneziaWG "$AWG_ENDPOINT" "$AWG_PORT"
uci commit firewall

uci -q delete luci.vpn_switch_wg || true
uci set luci.vpn_switch_wg=command
uci set luci.vpn_switch_wg.name='VPN_WireGuard_fast'
uci set luci.vpn_switch_wg.command='/usr/sbin/vpn-use-wg'
uci -q delete luci.vpn_switch_awg || true
uci set luci.vpn_switch_awg=command
uci set luci.vpn_switch_awg.name='VPN_AmneziaWG_reserve'
uci set luci.vpn_switch_awg.command='/usr/sbin/vpn-use-awg'
uci -q delete luci.vpn_status || true
uci set luci.vpn_status=command
uci set luci.vpn_status.name='VPN_status'
uci set luci.vpn_status.command='/usr/sbin/vpn-status'
uci commit luci

/etc/init.d/awg-watchdog stop 2>/dev/null || true
/etc/init.d/awg-watchdog disable 2>/dev/null || true
/etc/init.d/vpn-watchdog stop 2>/dev/null || true
/etc/init.d/vpn-watchdog disable 2>/dev/null || true

for path in \
    /usr/sbin/vpn-switch \
    /usr/sbin/vpn-apply-route \
    /usr/sbin/vpn-use-wg \
    /usr/sbin/vpn-use-awg \
    /usr/sbin/vpn-status \
    /usr/sbin/vpn-restore-mode \
    /etc/init.d/vpn-restore-mode \
    /etc/hotplug.d/iface/96-vpn-route; do
    grep -qxF "$path" /etc/sysupgrade.conf 2>/dev/null || echo "$path" >>/etc/sysupgrade.conf
done

/etc/init.d/firewall reload
rm -f /tmp/luci-indexcache
/etc/init.d/rpcd restart

ifup "$WG_IF" 2>/dev/null || true
ifup "$AWG_IF" 2>/dev/null || true

if ! /usr/sbin/vpn-apply-route "$ACTIVE_MODE"; then
    echo 'ERROR: route activation failed.' >&2
    echo 'If WireGuard was installed during this boot, restart network once and reconnect:' >&2
    echo '  /etc/init.d/network restart' >&2
    exit 1
fi

echo 'Dual-VPN switch installed. Automatic failover is OFF.'
echo "Remote SSH is allowed only from $WG_ADMIN_NET and $AWG_ADMIN_NET inside VPN."
echo 'LuCI: System -> Custom Commands.'
/usr/sbin/vpn-status
