#!/bin/sh
set -eu

EXPECTED_BOARD='cudy,lt300-v3'
EXPECTED_KERNEL='6.12.94'
MT76_SHA='8d2e57ec9fd159311088aaa745958998cda97bf59a0acfaad636e8e7432e8fc4'
MT7603_SHA='a50b9e4bb3b6c4867d509cdec5ad9fb72226c95afd55ae40b1872b6a44fd1b84'
STOCK_MT76_SHA='447be525d8e16e11b071ac0907b22a2c53ef82d7491fdc32e475e419004a1ba4'
STOCK_MT7603_SHA='88b62202aa149ef9139650a651bf17a2cb232dbb075c29f3e414c38bd17ec815'

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
DRIVER_DIR="$SCRIPT_DIR/../drivers"
KMOD_DIR="/lib/modules/$EXPECTED_KERNEL"
BACKUP_DIR="/root/mt7603-driver-backup-$EXPECTED_KERNEL"

board="$(ubus call system board | jsonfilter -e '@.board_name')"
kernel="$(uname -r)"
[ "$board" = "$EXPECTED_BOARD" ] || {
    echo "ERROR: expected $EXPECTED_BOARD, got $board" >&2
    exit 1
}
[ "$kernel" = "$EXPECTED_KERNEL" ] || {
    echo "ERROR: expected kernel $EXPECTED_KERNEL, got $kernel" >&2
    exit 1
}

check_hash() {
    expected="$1"
    file="$2"
    sha256sum "$file" | grep -q "^$expected " || {
        echo "ERROR: SHA256 mismatch: $file" >&2
        exit 1
    }
}

check_hash "$MT76_SHA" "$DRIVER_DIR/mt76.ko"
check_hash "$MT7603_SHA" "$DRIVER_DIR/mt7603e.ko"

if [ ! -e "$BACKUP_DIR/mt76.ko" ]; then
    check_hash "$STOCK_MT76_SHA" "$KMOD_DIR/mt76.ko"
    check_hash "$STOCK_MT7603_SHA" "$KMOD_DIR/mt7603e.ko"
    mkdir -p "$BACKUP_DIR"
    cp -p "$KMOD_DIR/mt76.ko" "$BACKUP_DIR/"
    cp -p "$KMOD_DIR/mt7603e.ko" "$BACKUP_DIR/"
    [ ! -e /etc/modules.d/mt7603 ] || cp -p /etc/modules.d/mt7603 "$BACKUP_DIR/modules.d-mt7603"
    uci export wireless > "$BACKUP_DIR/wireless.uci"
fi

cp "$DRIVER_DIR/mt76.ko" "$KMOD_DIR/mt76.ko"
cp "$DRIVER_DIR/mt7603e.ko" "$KMOD_DIR/mt7603e.ko"
chmod 0644 "$KMOD_DIR/mt76.ko" "$KMOD_DIR/mt7603e.ko"
printf '%s\n' mt7603e > /etc/modules.d/mt7603
chmod 0644 /etc/modules.d/mt7603

uci set wireless.radio0.txpower='15'
uci commit wireless
sync

echo 'Patched modules installed and txpower=15 saved.'
echo 'Do not use rmmod. Reboot the router now, then run the verification commands.'
