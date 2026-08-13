#!/bin/sh

echo '=== MODE ==='
uci show vpnmode 2>/dev/null || true
echo '=== SWITCH STATUS ==='
/usr/sbin/vpn-status 2>/dev/null || /usr/sbin/vpn-switch status 2>/dev/null || true
echo '=== ROUTES ==='
ip -4 route
ip -6 route
echo '=== ENDPOINT ROUTES ==='
for endpoint in \
    "$(uci -q get vpnmode.main.wg_endpoint || true)" \
    "$(uci -q get vpnmode.main.awg_endpoint || true)"; do
    [ -n "$endpoint" ] && ip -4 route get "$endpoint" 2>/dev/null || true
done
echo '=== FIREWALL ==='
uci show firewall.vpn 2>/dev/null || true
uci show firewall.lan_to_vpn 2>/dev/null || true
uci show firewall.vpn_endpoint_wg 2>/dev/null || true
uci show firewall.vpn_endpoint_awg 2>/dev/null || true
uci show firewall.vpn_admin_ssh_wg 2>/dev/null || true
uci show firewall.vpn_admin_ssh_awg 2>/dev/null || true
echo '=== REMOTE ADMIN ROUTES ==='
for network in \
    "$(uci -q get vpnmode.main.wg_admin_net || true)" \
    "$(uci -q get vpnmode.main.awg_admin_net || true)"; do
    [ -n "$network" ] && ip -4 route show "$network" 2>/dev/null || true
done
echo '=== DIRECT LAN TO WAN FORWARDINGS ==='
for forwarding in $(uci show firewall | sed -n 's/^\(firewall\.[^=]*\)=forwarding$/\1/p'); do
    src="$(uci -q get "$forwarding.src" || true)"
    dest="$(uci -q get "$forwarding.dest" || true)"
    enabled="$(uci -q get "$forwarding.enabled" || echo 1)"
    [ "$src" = 'lan' ] && [ "$dest" = 'wan' ] && echo "$forwarding enabled=$enabled"
done
echo '=== LEGACY WATCHDOG ==='
/etc/init.d/awg-watchdog enabled 2>/dev/null && echo enabled || echo disabled
echo '=== DNS ==='
uci show dhcp.@dnsmasq[0] | grep -E 'noresolv|server' || true
nslookup example.com 127.0.0.1 || true
echo '=== PUBLIC IP ==='
wget -qO- -T 15 https://api.ipify.org 2>/dev/null || true
echo
