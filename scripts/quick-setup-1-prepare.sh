#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
WG_CONF="${1:-}"
AWG_CONF="${2:-}"
WIFINET="${3:-}"

[ -r "$WG_CONF" ] && [ -r "$AWG_CONF" ] || {
    echo "Usage: $0 /tmp/wireguard.conf /tmp/amneziawg.conf [wifi-iface]" >&2
    exit 1
}
[ "$(ubus call system board | jsonfilter -e '@.board_name')" = 'cudy,lt300-v3' ] || {
    echo 'ERROR: this quick setup is only for cudy,lt300-v3.' >&2
    exit 1
}

backup="/root/pre-cudy-dualvpn-$(date +%Y%m%d-%H%M%S).tar.gz"
sysupgrade -b "$backup"
echo "Initial backup: $backup"

"$SCRIPT_DIR/install-packages-25.12.5.sh"
"$SCRIPT_DIR/configure-wireguard-from-conf.sh" "$WG_CONF" wg0
"$SCRIPT_DIR/configure-awg-from-conf.sh" "$AWG_CONF" awg0
"$SCRIPT_DIR/apply-lt300-wifi-profile.sh" radio0 "$WIFINET" RU 1 15

cp "$SCRIPT_DIR/awg-sync-modem-time" /usr/sbin/awg-sync-modem-time
cp "$SCRIPT_DIR/awg-modem-recover" /usr/sbin/awg-modem-recover
cp "$SCRIPT_DIR/95-vpn-clock" /etc/hotplug.d/iface/95-vpn-clock
chmod 700 /usr/sbin/awg-sync-modem-time /usr/sbin/awg-modem-recover
chmod 755 /etc/hotplug.d/iface/95-vpn-clock

"$SCRIPT_DIR/install-mt7603-patched-driver.sh"

STAGE2_DIR='/root/cudy-dualvpn-stage2'
mkdir -p "$STAGE2_DIR"
for file in quick-setup-2-activate.sh install-dual-vpn-switch.sh enable-vpn-remote-ssh.sh enable-persistent-wg.sh vpn-wg-persistent vpn-wg-persistent.init vpn-switch vpn-apply-route vpn-restore-mode vpn-restore-mode.init 96-vpn-route verify-dual-vpn.sh; do
    cp "$SCRIPT_DIR/$file" "$STAGE2_DIR/$file"
    chmod 700 "$STAGE2_DIR/$file"
done

for path in /usr/sbin/awg-sync-modem-time /usr/sbin/awg-modem-recover /etc/hotplug.d/iface/95-vpn-clock; do
    grep -qxF "$path" /etc/sysupgrade.conf 2>/dev/null || echo "$path" >> /etc/sysupgrade.conf
done

chmod 600 "$WG_CONF" "$AWG_CONF"
sync
echo 'Stage 1 complete. The configs remain only in /tmp and disappear after reboot.'
echo 'Reboot now. Then reconnect by Ethernet and run:'
echo '  /root/cudy-dualvpn-stage2/quick-setup-2-activate.sh wg <PROBE_IP> <WG_ADMIN_CIDR> <AWG_ADMIN_CIDR>'
