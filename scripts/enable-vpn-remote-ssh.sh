#!/bin/sh
set -eu

WG_ADMIN_NET="${1:-}"
AWG_ADMIN_NET="${2:-}"
WG_IF="${3:-wg0}"
AWG_IF="${4:-awg0}"

for name in "$WG_IF" "$AWG_IF"; do
    echo "$name" | grep -Eq '^[A-Za-z0-9_]+$' || { echo "ERROR: unsafe interface name: $name" >&2; exit 1; }
    [ -n "$(uci -q get "network.$name.proto" || true)" ] || { echo "ERROR: network.$name does not exist." >&2; exit 1; }
done
for network in "$WG_ADMIN_NET" "$AWG_ADMIN_NET"; do
    echo "$network" | grep -Eq '^[0-9]{1,3}(\.[0-9]{1,3}){3}/[0-9]{1,2}$' || {
        echo "ERROR: invalid IPv4 network: $network" >&2
        exit 1
    }
done
[ "$(uci -q get firewall.vpn.name || true)" = 'vpn' ] || {
    echo 'ERROR: firewall zone vpn is missing; install the DualVPN switch first.' >&2
    exit 1
}

BACKUP="/root/pre-vpn-remote-ssh-$(date +%Y%m%d-%H%M%S).tar.gz"
sysupgrade -b "$BACKUP"

touch /etc/config/vpnmode
uci -q get vpnmode.main >/dev/null || uci set vpnmode.main=mode
uci set "vpnmode.main.wg_admin_net=$WG_ADMIN_NET"
uci set "vpnmode.main.awg_admin_net=$AWG_ADMIN_NET"
uci commit vpnmode
chmod 600 /etc/config/vpnmode

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
uci commit firewall

ifup "$WG_IF" 2>/dev/null || true
ifup "$AWG_IF" 2>/dev/null || true
sleep 2
ip link show "$WG_IF" >/dev/null 2>&1 && ip -4 route replace "$WG_ADMIN_NET" dev "$WG_IF" metric 5 || true
ip link show "$AWG_IF" >/dev/null 2>&1 && ip -4 route replace "$AWG_ADMIN_NET" dev "$AWG_IF" metric 5 || true
/etc/init.d/firewall reload

echo "Backup: $BACKUP"
echo "SSH allowed from $WG_ADMIN_NET via $WG_IF and $AWG_ADMIN_NET via $AWG_IF."
echo 'LTE/WAN SSH was not opened.'
uci show firewall.vpn_admin_ssh_wg
uci show firewall.vpn_admin_ssh_awg
ip -4 route show "$WG_ADMIN_NET" 2>/dev/null || true
ip -4 route show "$AWG_ADMIN_NET" 2>/dev/null || true
