#!/bin/sh

echo '=== BOARD ==='
ubus call system board
echo '=== KERNEL ==='
uname -a
echo '=== PACKAGE ARCHITECTURES ==='
if command -v opkg >/dev/null 2>&1; then
    opkg print-architecture
    opkg status kernel 2>/dev/null | grep -E '^(Package|Version|Architecture|Status):'
elif command -v apk >/dev/null 2>&1; then
    apk --print-arch
    apk info kernel 2>/dev/null || true
fi
echo '=== OVERLAY SPACE ==='
df -h /overlay 2>/dev/null || df -h /
echo '=== ROUTES ==='
ip -4 route
ip -6 route
echo '=== INTERFACES ==='
ubus call network.interface dump
echo '=== USB/MODEM ==='
lsusb 2>/dev/null || true
ls -l /dev/ttyUSB* /dev/ttyACM* /dev/cdc-wdm* 2>/dev/null || true
echo '=== EXISTING AWG/WIREGUARD PACKAGES ==='
if command -v opkg >/dev/null 2>&1; then
    opkg list-installed | grep -Ei 'amnezia|wireguard|luci-proto' || true
else
    apk info | grep -Ei 'amnezia|wireguard|luci-proto' || true
fi
