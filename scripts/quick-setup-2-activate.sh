#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ACTIVE_MODE="${1:-wg}"
PROBE_IP="${2:-1.1.1.1}"
WG_ADMIN_NET="${3:-}"
AWG_ADMIN_NET="${4:-}"

case "$ACTIVE_MODE" in wg|awg) ;; *) echo 'Usage: quick-setup-2-activate.sh [wg|awg] [probe-ip] [wg-admin-cidr] [awg-admin-cidr]' >&2; exit 1 ;; esac
[ -n "$WG_ADMIN_NET" ] && [ -n "$AWG_ADMIN_NET" ] || {
    echo 'Provide your WG and AWG administrator CIDRs explicitly.' >&2
    exit 1
}

"$SCRIPT_DIR/install-dual-vpn-switch.sh" wg0 awg0 wwan "$ACTIVE_MODE" "$PROBE_IP" "$WG_ADMIN_NET" "$AWG_ADMIN_NET"
"$SCRIPT_DIR/verify-dual-vpn.sh" wg0 awg0 wwan

echo 'Stage 2 complete. Test both manual switch commands and then make a private backup.'
echo '  /usr/sbin/vpn-use-wg'
echo '  /usr/sbin/vpn-use-awg'
echo '  /usr/sbin/vpn-status'
echo "Remote SSH networks: $WG_ADMIN_NET via wg0; $AWG_ADMIN_NET via awg0"
