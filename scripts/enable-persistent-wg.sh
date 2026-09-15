#!/bin/sh
# Opt in to fixed WireGuard routing and unlimited reconnect attempts.
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
for file in vpn-wg-persistent vpn-wg-persistent.init; do
    [ -r "$SCRIPT_DIR/$file" ] || { echo "Missing $file" >&2; exit 1; }
    /bin/sh -n "$SCRIPT_DIR/$file"
done

wg_if="$(uci -q get vpnmode.main.wg_if || echo wg0)"
[ "$(uci -q get "network.$wg_if.proto" || true)" = 'wireguard' ] || {
    echo "Configure the WireGuard interface $wg_if before enabling this mode" >&2
    exit 1
}
[ -x /usr/sbin/vpn-apply-route ] || { echo 'Install the DualVPN routing layer first' >&2; exit 1; }

umask 077
cp /etc/config/vpnmode "/root/vpnmode-before-persistent-wg-$(date +%Y%m%d-%H%M%S).conf"
if [ -x /etc/init.d/vpn-wg-persistent ]; then
    /etc/init.d/vpn-wg-persistent stop || true
fi
cp "$SCRIPT_DIR/vpn-wg-persistent" /usr/sbin/vpn-wg-persistent
cp "$SCRIPT_DIR/vpn-wg-persistent.init" /etc/init.d/vpn-wg-persistent
chmod 700 /usr/sbin/vpn-wg-persistent
chmod 755 /etc/init.d/vpn-wg-persistent

uci set vpnmode.main.mode='wg'
uci set vpnmode.main.auto_failover='0'
uci commit vpnmode
/usr/sbin/vpn-apply-route wg >/dev/null 2>&1 || true
/etc/init.d/vpn-wg-persistent enable
/etc/init.d/vpn-wg-persistent start

for path in /usr/sbin/vpn-wg-persistent /etc/init.d/vpn-wg-persistent; do
    grep -qxF "$path" /etc/sysupgrade.conf 2>/dev/null || echo "$path" >>/etc/sysupgrade.conf
done

echo 'Fixed WireGuard mode enabled. Automatic failover is disabled.'
echo 'This service overrides manual selection of the standby tunnel.'
