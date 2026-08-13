#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PACKAGE_DIR="${1:-$SCRIPT_DIR/../packages}"
CHECKSUM_FILE="${2:-$SCRIPT_DIR/../checksums/SHA256SUMS}"
board="$(ubus call system board | jsonfilter -e '@.board_name')"
version="$(ubus call system board | jsonfilter -e '@.release.version')"
kernel="$(uname -r)"

[ "$board" = 'cudy,lt300-v3' ] || { echo "ERROR: expected cudy,lt300-v3, found $board" >&2; exit 1; }
[ "$version" = '25.12.5' ] || { echo "ERROR: packages require OpenWrt 25.12.5, found $version" >&2; exit 1; }
[ "$kernel" = '6.12.94' ] || { echo "ERROR: packages require kernel 6.12.94, found $kernel" >&2; exit 1; }
[ -d "$PACKAGE_DIR" ] || { echo "ERROR: package directory not found: $PACKAGE_DIR" >&2; exit 1; }
[ -r "$CHECKSUM_FILE" ] || { echo "ERROR: checksum file not found: $CHECKSUM_FILE" >&2; exit 1; }
command -v apk >/dev/null 2>&1 || { echo 'ERROR: apk is missing.' >&2; exit 1; }

set -- "$PACKAGE_DIR"/*.apk
[ -f "$1" ] || { echo "ERROR: no APK files in $PACKAGE_DIR" >&2; exit 1; }

for package in "$@"; do
    relative="packages/${package##*/}"
    expected="$(awk -v file="$relative" '$2 == file { print $1; exit }' "$CHECKSUM_FILE")"
    [ -n "$expected" ] || { echo "ERROR: checksum entry is missing: $relative" >&2; exit 1; }
    printf '%s  %s\n' "$expected" "$package" | sha256sum -c -
done

# The SIM may not reach public repositories before VPN is active.
# Install only the verified local package set.
apk add --no-network --allow-untrusted "$@"
modprobe wireguard
modprobe amneziawg
wg --version
awg --version
echo 'PACKAGE_INSTALL_OK'
