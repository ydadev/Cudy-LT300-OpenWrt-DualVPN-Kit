# Быстрое повторение на Cudy LT300 v3

Инструкция рассчитана на точно такое же устройство и версии:

```text
board:        cudy,lt300-v3
OpenWrt:      25.12.5
target:       ramips/mt76x8
architecture: mipsel_24kc
kernel:       6.12.94
```

Если хотя бы один пункт отличается, не устанавливайте APK, firmware или `.ko`
из репозитория. Используйте [OTHER-DEVICES-RU.md](OTHER-DEVICES-RU.md).

## 1. Что понадобится

- LT300 v3 с исправным проводным Ethernet;
- стабильное питание 5 В / 2 А;
- компьютер, подключённый к LT300 кабелем;
- отдельный интернет компьютера через другой Wi-Fi — это нормально;
- собственный WireGuard-конфиг;
- собственный AmneziaWG 2.0-конфиг;
- APN специальной SIM-карты.

Не помещайте реальные конфиги в каталог git. Передавайте их на роутер только в
`/tmp`: это RAM, которая очищается после reboot.

## 2. Если OpenWrt ещё не установлен

Со штатной Cudy firmware нужен подписанный промежуточный OpenWrt-образ Cudy.
После него можно ставить официальный sysupgrade. Следуйте странице устройства
OpenWrt и инструкции Cudy; этот репозиторий не автоматизирует OEM-переход.

Если на роутере уже OpenWrt 24.10.x или 25.12.x, используйте LuCI
**System → Backup / Flash Firmware** либо `sysupgrade` только после проверки
board и SHA256.

## 3. Проверить устройство и сохранить backup

```sh
ubus call system board
uname -r
df -h /overlay
sysupgrade -b /tmp/before-dualvpn.tar.gz
sha256sum /tmp/before-dualvpn.tar.gz
```

Скопируйте backup на компьютер и храните закрыто: в нём могут быть пароли и
ключи.

Ожидаемые значения после установки OpenWrt 25.12.5:

```text
board_name: cudy,lt300-v3
version:    25.12.5
kernel:     6.12.94
```

## 4. Чистое обновление до 25.12.5

В репозитории находится:

```text
firmware/openwrt-25.12.5-ramips-mt76x8-cudy_lt300-v3-squashfs-sysupgrade.bin
```

Его SHA256 должен быть:

```text
d2b8dd37026d1185041cc3f1d4e2383bf971a480458bb0ea93b1d74da6a97c0c
```

Команды выполняются на роутере после передачи файла в `/tmp`:

```sh
sha256sum /tmp/openwrt-25.12.5-ramips-mt76x8-cudy_lt300-v3-squashfs-sysupgrade.bin
sysupgrade -T /tmp/openwrt-25.12.5-ramips-mt76x8-cudy_lt300-v3-squashfs-sysupgrade.bin
sysupgrade -n /tmp/openwrt-25.12.5-ramips-mt76x8-cudy_lt300-v3-squashfs-sysupgrade.bin
```

`-n` означает чистую установку без сохранения старых настроек. Не используйте
`-F`. Не отключайте питание. Если ранее зависал `rmmod mt7603e`, сначала сделайте
обычный reboot и только затем запускайте sysupgrade.

## 5. Первый вход и LTE

После чистой установки задайте пароль root, настройте LAN-адрес при
необходимости и проверьте LTE/RNDIS:

```sh
ip link show usb0
ubus call network.interface.wwan status
ip -4 route
ping -c 3 <VPN_ENDPOINT_IP>
```

Пример WWAN:

```sh
uci -q delete network.wwan
uci set network.wwan=interface
uci set network.wwan.proto='dhcp'
uci set network.wwan.device='usb0'
uci set network.wwan.metric='100'
uci commit network
/etc/init.d/network restart
```

APN обычно задаётся самому LTE-модему AT-командой или его внутренним web UI.
Способ зависит от модема и оператора.

## 6. Передать минимальный набор

На Windows OpenSSH для Dropbear используйте старый SCP-протокол `-O`:

```powershell
ssh root@192.168.10.1 "mkdir -p /tmp/Cudy-LT300-OpenWrt-DualVPN-Kit"
scp -O -r packages drivers scripts checksums root@192.168.10.1:/tmp/Cudy-LT300-OpenWrt-DualVPN-Kit/
scp -O .\my-wireguard.conf root@192.168.10.1:/tmp/wireguard.conf
scp -O .\my-amneziawg.conf root@192.168.10.1:/tmp/amneziawg.conf
```

Firmware в `/tmp` для обычной настройки передавать не нужно — это экономит
flash. Установочные файлы можно удалить после успешной настройки.

## 7. Проверить имена секций Wi-Fi

```sh
uci show wireless | grep '=wifi-iface'
```

На проверенном роутере секция называлась `wifinet0`. После чистой генерации она
может называться `default_radio0`. Если третий аргумент stage 1 не задан, скрипт
возьмёт первую `wifi-iface` автоматически.

## 8. Этап 1: пакеты, VPN-конфиги, Wi-Fi и драйвер

```sh
cd /tmp/Cudy-LT300-OpenWrt-DualVPN-Kit
chmod 755 scripts/*
scripts/quick-setup-1-prepare.sh \
  /tmp/wireguard.conf \
  /tmp/amneziawg.conf \
  wifinet0
sync
reboot
```

Stage 1:

1. проверяет board/version/kernel;
2. создаёт полный backup;
3. проверяет SHA256 каждого APK;
4. устанавливает WG/AWG офлайн;
5. импортирует конфиги без печати ключей;
6. сохраняет профиль HT20, U-APSD off, DTIM=1 и 15 dBm;
7. ставит MCS0–7 hotplug;
8. сохраняет штатные Wi-Fi-модули и устанавливает patched MT7603;
9. оставляет реальные конфиги только в `/tmp` — reboot их удаляет.

Перезагрузка нужна, чтобы netifd увидел новые протоколы, а ядро загрузило новые
модули. Не пытайтесь применять драйвер через `rmmod`.

## 9. Этап 2: маршруты, firewall и LuCI-кнопки

Основной режим WireGuard:

```sh
/root/cudy-dualvpn-stage2/quick-setup-2-activate.sh \
  wg 1.1.1.1 10.8.1.0/24 10.8.2.0/23
```

Последние два аргумента — сети, из которых разрешён удалённый SSH через
соответствующий туннель: `10.8.1.0/24` для WireGuard и `10.8.2.0/23` для
AmneziaWG. Эти правила не открывают SSH через LTE/WAN.

Нужные stage 2-скрипты были сохранены в `/root` до reboot.

Если публичный ICMP фильтруется, вместо `1.1.1.1` используйте стабильный
внутренний IP, доступный через оба туннеля.

## 10. Ручное переключение

```sh
/usr/sbin/vpn-status
/usr/sbin/vpn-use-wg
/usr/sbin/vpn-use-awg
```

Команда сначала проверяет handshake и ping через целевой tunnel interface.
Default route меняется только после успешного теста. В LuCI доступны те же три
команды: **System → Custom Commands**.

Удалённое управление не зависит от текущего default VPN: отдельные маршруты
`10.8.1.0/24 dev wg0` и `10.8.2.0/23 dev awg0` возвращают ответ в тот же туннель,
из которого пришёл SSH. Подключайтесь к адресу самого роутера внутри VPN:

```sh
ssh root@10.8.1.3
```

`10.8.1.3` — пример `Address` интерфейса WG. Для AWG используйте адрес интерфейса
`awg0` из своего конфига. После проверки положите публичный SSH-ключ в
`/etc/dropbear/authorized_keys`; пароль отключайте только после проверки резервного
входа по Ethernet.

Для уже настроенного набора можно применить только это дополнение:

```sh
/tmp/Cudy-LT300-OpenWrt-DualVPN-Kit/scripts/enable-vpn-remote-ssh.sh \
  10.8.1.0/24 10.8.2.0/23 wg0 awg0
```

Скрипт сначала создаёт закрытый backup в `/root`, затем меняет только UCI-маршруты
и два правила firewall. Полный установщик повторно запускать не требуется.

## 11. Проверка после reboot

```sh
ubus call system board
date -u
ip -4 route
ip -4 route get <VPN_ENDPOINT_IP>
/usr/sbin/vpn-status
nslookup openwrt.org 127.0.0.1
iw dev phy0-ap0 info
cat /sys/kernel/debug/ieee80211/phy0/mt76/reset
cat /sys/kernel/debug/ieee80211/phy0/aqm
```

Ожидается:

- endpoint `/32` через gateway LTE и `usb0`;
- default route через выбранный `wg0` или `awg0`;
- `txpower 15.00 dBm`;
- после свежего reboot reset-счётчики равны нулю;
- `fq_backlog 0` без трафика;
- интернет и DNS работают.

## 12. Нагрузочный тест

Подключите минимум четыре клиента и одновременно запустите видео/загрузку на
3–5 минут. Во время теста:

```sh
scripts/wifi-load-monitor.sh &
iw dev phy0-ap0 station dump
cat /sys/kernel/debug/ieee80211/phy0/mt76/reset
cat /sys/kernel/debug/ieee80211/phy0/aqm
```

На проверенном устройстве четыре телефона работали одновременно без обрыва.
Единичный `Beacon stuck`, после которого очередь остаётся 0 и трафик продолжается,
не равен прежнему зависанию. Плохой признак — быстро растущий счётчик, большой
`fq_backlog` и потеря связи всех клиентов.

## 13. Финальный закрытый backup

```sh
sysupgrade -b /tmp/cudy-dualvpn-working.tar.gz
sha256sum /tmp/cudy-dualvpn-working.tar.gz
```

Скопируйте файл с роутера и не публикуйте. Затем выполните один контролируемый
cold boot: выключить питание на 10 секунд, включить и повторить проверки.
