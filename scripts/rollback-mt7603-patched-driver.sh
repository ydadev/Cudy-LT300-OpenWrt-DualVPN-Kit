#!/bin/sh
set -eu

EXPECTED_KERNEL='6.12.94'
KMOD_DIR="/lib/modules/$EXPECTED_KERNEL"
BACKUP_DIR="/root/mt7603-driver-backup-$EXPECTED_KERNEL"

if [ ! -s "$BACKUP_DIR/mt76.ko" ] && [ -s /root/mt7603-driver-test/original/mt76.ko ]; then
    BACKUP_DIR='/root/mt7603-driver-test/original'
fi

[ "$(uname -r)" = "$EXPECTED_KERNEL" ] || {
    echo "ERROR: this rollback is only for kernel $EXPECTED_KERNEL" >&2
    exit 1
}
[ -s "$BACKUP_DIR/mt76.ko" ] && [ -s "$BACKUP_DIR/mt7603e.ko" ] || {
    echo "ERROR: original modules not found in $BACKUP_DIR" >&2
    exit 1
}

cp "$BACKUP_DIR/mt76.ko" "$KMOD_DIR/mt76.ko"
cp "$BACKUP_DIR/mt7603e.ko" "$KMOD_DIR/mt7603e.ko"
chmod 0644 "$KMOD_DIR/mt76.ko" "$KMOD_DIR/mt7603e.ko"

if [ -s "$BACKUP_DIR/modules.d-mt7603" ]; then
    cp "$BACKUP_DIR/modules.d-mt7603" /etc/modules.d/mt7603
else
    printf '%s\n' mt7603e > /etc/modules.d/mt7603
fi

if [ -s "$BACKUP_DIR/wireless.uci" ]; then
    uci import wireless < "$BACKUP_DIR/wireless.uci"
    uci commit wireless
fi

sync
echo 'Original modules and saved wireless configuration restored.'
echo 'Do not use rmmod. Reboot the router now.'
