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

Если на роутере уже OpenWrt, используйте LuCI **System → Backup / Flash
Firmware** либо `sysupgrade` только после проверки board, версии, типа образа
и SHA256. Переход с 23.05.x или старше на 25.12.x [официально не поддержан
обычным обновлением с переносом настроек](https://openwrt.org/releases/25.12/notes-25.12.3):
не восстанавливайте старый backup поверх новой системы. Для иных исходных
версий также заранее изучите примечания к выпуску и страницу устройства.

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

`-n` означает чистую установку без сохранения старых настроек. `-F` не
используйте вообще; не добавляйте и `-f <backup.tar.gz>` к `-n`: указание
архива через `-f` всё равно восстановит содержащиеся в нём файлы. Особенно
опасно переносить
`/etc/config/network` со старой сборки. Держите полный backup **на компьютере**
только для выборочного восстановления данных после первого входа. Не отключайте
питание. Если ранее зависал `rmmod mt7603e`, сначала сделайте обычный reboot и
только затем запускайте sysupgrade.

На проверенном LT300 v3 со старой OpenWrt мост LAN использовал `eth0` без
настройки switch/VLAN. В штатной схеме OpenWrt 25.12.5 этот же роутер имеет
**LAN `eth0.2`, WAN `eth0.1`**, а разделы `switch` и `switch_vlan` создаются
заново по `/etc/board.json`. Перенос старого `network` оставил роутер без
доступа по Ethernet после первого reboot. Не переписывайте новый файл
`/etc/config/network` старым целиком — меняйте только нужные параметры через
`uci`, оставляя созданные новой версией интерфейсы и VLAN.

Если доступ потерян после обновления, сначала проверьте и заводской адрес
`192.168.1.1`, и ранее назначенный адрес, переключая **только адрес Ethernet
компьютера** в соответствующую подсеть. Если оба недоступны, попробуйте
[failsafe OpenWrt](https://openwrt.org/docs/guide-user/troubleshooting/failsafe_and_factory_reset):
включите роутер и **кратко** нажмите Reset, когда системный индикатор начал
мигать. Не удерживайте Reset во время подачи питания: у Cudy это может вызвать
загрузчик/TFTP-recovery. В failsafe Wi-Fi и DHCP выключены, LAN отвечает на
`192.168.1.1`; задайте Ethernet компьютеру, например, `192.168.1.20/24`.
После SSH выполните:

```sh
mount_root
mv /etc/config/network /etc/config/network.before-vlan-recovery
/bin/board_detect
/bin/config_generate
uci set network.lan.ipaddr='192.168.1.1'  # или ваш желаемый LAN-адрес
uci commit network
uci -q get network.lan.ipaddr
uci show network | grep -E 'eth0\.1|eth0\.2|switch_vlan'
sync
reboot
```

Генератор берёт схему портов из **текущего** `/etc/board.json`; указанная
команда `mv` сохраняет старый файл на роутере для диагностики. После reboot
переведите Ethernet компьютера в подсеть выбранного LAN-адреса и проверьте SSH.
Если failsafe не запускается, не повторяйте прошивку вслепую — переходите к
официальной процедуре восстановления Cudy.

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
ssh root@<ROUTER_LAN_IP> "mkdir -p /tmp/Cudy-LT300-OpenWrt-DualVPN-Kit"
scp -O -r packages drivers scripts checksums root@<ROUTER_LAN_IP>:/tmp/Cudy-LT300-OpenWrt-DualVPN-Kit/
scp -O .\my-wireguard.conf root@<ROUTER_LAN_IP>:/tmp/wireguard.conf
scp -O .\my-amneziawg.conf root@<ROUTER_LAN_IP>:/tmp/amneziawg.conf
```

Firmware в `/tmp` для обычной настройки передавать не нужно — это экономит
flash. Установочные файлы можно удалить после успешной настройки.
`checksums/SHA256SUMS` допускает Windows-окончания строк CRLF: установщик
убирает завершающий `\r` при поиске записи, а затем проверяет реальный SHA256
каждого APK. Не отключайте эту проверку, если установка остановилась.

## 7. Проверить имена секций Wi-Fi

```sh
uci show wireless | grep '=wifi-iface'
```

На проверенном роутере секция называлась `wifinet0`. После чистой генерации она
может называться `default_radio0`. Если третий аргумент stage 1 не задан, скрипт
возьмёт первую `wifi-iface` автоматически.

**До stage 1** установите своё имя Wi-Fi и пароль: скрипт включит радио, а
после чистой установки штатная `wifi-iface` может ещё не иметь шифрования.
Не переносите весь `network` из старого бэкапа ради сохранения Wi-Fi.

```sh
WIFI_IFACE="$(uci show wireless | sed -n 's/^wireless\.\([^=]*\)=wifi-iface$/\1/p' | head -n1)"
test -n "$WIFI_IFACE"
uci set "wireless.$WIFI_IFACE.ssid=<YOUR_WIFI_SSID>"
uci set "wireless.$WIFI_IFACE.encryption=psk2"
uci set "wireless.$WIFI_IFACE.key=<STRONG_WIFI_PASSWORD>"
uci commit wireless
uci -q get "wireless.$WIFI_IFACE.encryption"
```

На том же LT300 v3 можно выборочно взять старые SSID/пароль из закрытого
бэкапа, проверив совпадение пути радио; архив и ключи храните только закрыто.
Первый проверенный роутер использовал WPA2 (`psk2`), поэтому для быстрого
повторения указан именно он. На втором роутере смешанный WPA2/WPA3
(`sae-mixed`) тоже тестировался, но переключение на WPA2 само по себе не
устранило исчезновение сети. WPA3 можно включать отдельно после стабильного
нагрузочного теста; не меняйте режим защиты одновременно с другими параметрами.

## 8. Этап 1: пакеты, VPN-конфиги, Wi-Fi и драйвер

```sh
cd /tmp/Cudy-LT300-OpenWrt-DualVPN-Kit
chmod 755 scripts/*
scripts/quick-setup-1-prepare.sh \
  /tmp/wireguard.conf \
  /tmp/amneziawg.conf
```

Stage 1:

1. проверяет board/version/kernel;
2. создаёт полный backup;
3. проверяет SHA256 каждого APK;
4. устанавливает WG/AWG офлайн;
5. импортирует конфиги без печати ключей, endpoint и VPN-адресов; IP-адреса
   из поля DNS направляет резолверу, а имена доменов использует как поисковые
   домены (не как DNS-серверы); необязательные AWG-поля можно не задавать;
6. сохраняет профиль HT20, U-APSD off, DTIM=1 и 15 dBm;
7. не устанавливает ограничение MCS0–7: его необходимость с исправленным
   драйвером не подтверждена, а на втором LT300 v3 оно снято;
8. сохраняет штатные Wi-Fi-модули и устанавливает patched MT7603;
9. оставляет реальные конфиги только в `/tmp` — reboot их удаляет.

Перезагрузка нужна, чтобы netifd увидел новые протоколы, а ядро загрузило новые
модули. Не пытайтесь применять драйвер через `rmmod`.

Если хотите сразу повторить текущий профиль второго LT300 v3, после stage 1,
но **до `reboot`**, выполните:

```sh
uci set wireless.radio0.txpower='12'
uci commit wireless
```

Установщик драйвера в stage 1 выставляет базовые 15 dBm, поэтому команда до
него не сохранит 12 dBm. Автоматической MCS-маски в этом варианте нет, а WPA2
задаётся на предыдущем шаге. На первом LT300 v3 15 dBm с маской выдержали
нагрузку; на втором снижение до 12 dBm само по себе обрывы не устранило.

Для базового профиля 15 dBm пропустите необязательные команды выше. Затем в
обоих вариантах завершите этап:

```sh
sync
reboot
```

## 9. Этап 2: маршруты, firewall и LuCI-кнопки

Основной режим WireGuard:

```sh
/root/cudy-dualvpn-stage2/quick-setup-2-activate.sh \
  wg 1.1.1.1 <WG_ADMIN_CIDR> <AWG_ADMIN_CIDR>
```

Последние два аргумента — сети, из которых разрешён удалённый SSH через
соответствующий туннель: `<WG_ADMIN_CIDR>` для WireGuard и `<AWG_ADMIN_CIDR>` для
AmneziaWG. Эти правила не открывают SSH через LTE/WAN.

Нужные stage 2-скрипты были сохранены в `/root` до reboot.

Для фиксированного WG без автоматического выбора AWG после проверки обоих
туннелей используйте [FIXED-WG-RU.md](FIXED-WG-RU.md). Этот режим необязателен
и отменяет ручной выбор AWG, пока служба работает.

Если публичный ICMP фильтруется, вместо `1.1.1.1` используйте стабильный
внутренний IP, доступный через оба туннеля.

### DNS и DHCP после выбора основного WG

Если у WG и AWG в конфигах **разные DNS IP**, первый этап мог оставить
`dnsmasq` с сервером из AWG. При основном маршруте WG такой сервер может быть
недоступен. Проверьте один DNS IP из WG через **оба** туннеля и только если он
доступен через оба, выдавайте его клиентам. Если общего DNS нет, нужна отдельная
политика DNS-маршрутов/переключения; не назначайте недоступный адрес.

На чистом LT300 v3 без других DHCP-опций:

```sh
set -- $(uci -q get network.wg0.dns)
test "$#" -eq 1
WG_DNS="$1"
set -- $(uci -q get network.wg0.dns_search)
test "$#" -eq 1
VPN_DOMAIN="$1"
ping -I wg0 -c 1 -W 3 "$WG_DNS"
ping -I awg0 -c 1 -W 3 "$WG_DNS"
cp /etc/config/dhcp /root/dhcp.before-vpn-dns.conf
chmod 600 /root/dhcp.before-vpn-dns.conf
uci set dhcp.@dnsmasq[0].noresolv='1'
uci -q delete dhcp.@dnsmasq[0].server
uci add_list "dhcp.@dnsmasq[0].server=$WG_DNS"
uci -q delete dhcp.lan.dhcp_option
uci add_list "dhcp.lan.dhcp_option=6,$WG_DNS"
uci add_list "dhcp.lan.dhcp_option=15,$VPN_DOMAIN"
uci add_list "dhcp.lan.dhcp_option=119,$VPN_DOMAIN"
uci commit dhcp
/etc/init.d/dnsmasq restart
nslookup -type=A openwrt.org 127.0.0.1
```

Опции DHCP 6, 15 и 119 соответственно выдают DNS, доменное имя и поисковый
суффикс ([примеры OpenWrt](https://openwrt.org/docs/guide-user/base-system/dhcp_configuration),
[RFC 2132](https://www.rfc-editor.org/info/rfc2132/),
[RFC 3397](https://www.rfc-editor.org/info/rfc3397/)). Если в
`dhcp.lan.dhcp_option` уже есть другие опции, **не удаляйте
весь список** как в примере: сохраните их и замените лишь 6/15/119. После
изменения переподключите клиентов, чтобы они получили новую DHCP-аренду.
Отсутствующий в WG `dns_search` замените своим поисковым доменом либо не
выдавайте опции 15/119.

Если оба ваших профиля имеют только IPv4 `Address`, а VPN-сервер не даёт IPv6,
отключите объявления IPv6 в LAN: иначе клиентам будет выдан префикс без
рабочего выхода. IPv4 DHCP при этом остаётся включённым. Не делайте этого при
действительно рабочем IPv6 через туннель.

```sh
uci set network.lan.ip6assign='0'
uci set dhcp.lan.ra='disabled'
uci set dhcp.lan.dhcpv6='disabled'
uci commit network
uci commit dhcp
/etc/init.d/odhcpd restart
```

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
`<WG_ADMIN_CIDR> dev wg0` и `<AWG_ADMIN_CIDR> dev awg0` возвращают ответ в тот же туннель,
из которого пришёл SSH. Подключайтесь к адресу самого роутера внутри VPN:

```sh
ssh root@<WG_ROUTER_IP>
```

`<WG_ROUTER_IP>` — пример `Address` интерфейса WG. Для AWG используйте адрес интерфейса
`awg0` из своего конфига. После проверки положите публичный SSH-ключ в
`/etc/dropbear/authorized_keys`; пароль отключайте только после проверки резервного
входа по Ethernet.

Для уже настроенного набора можно применить только это дополнение:

```sh
/tmp/Cudy-LT300-OpenWrt-DualVPN-Kit/scripts/enable-vpn-remote-ssh.sh \
  <WG_ADMIN_CIDR> <AWG_ADMIN_CIDR> wg0 awg0
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
- `txpower 15.00 dBm` для базового профиля; после дополнительного шага ниже — `12.00 dBm`;
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
Это был первый LT300 v3 с 15 dBm и установленной маской MCS0–7; вклад каждого
параметра по отдельности не доказан. На втором экземпляре при 12 dBm и WPA2
сеть продолжала исчезать, а после снятия MCS0–7 пользователь подтвердил
нормальную работу. Длительный тест и проверка после выключения питания ещё
нужны: не считайте это доказательством, что маска всегда вредна.
Единичный `Beacon stuck`, после которого очередь остаётся 0 и трафик продолжается,
не равен прежнему зависанию. Плохой признак — быстро растущий счётчик, большой
`fq_backlog` и потеря связи всех клиентов.

Если конкретный LT300 всё ещё отключает Wi-Fi при 15 dBm, попробуйте 12 dBm,
подключившись по Ethernet или имея другой способ вернуть доступ:

```sh
uci set wireless.radio0.txpower='12'
uci commit wireless
wifi reload radio0
uci -q get wireless.radio0.txpower
iw dev phy0-ap0 info | grep txpower
```

Обе проверки должны показать 12 dBm. UCI сохраняет значение после reboot;
проверьте его повторно после перезагрузки и проведите нагрузочный тест. На втором
LT300 v3 12 dBm применились, но сами по себе не устранили обрывы.
Не снижайте мощность вслепую: уменьшится зона покрытия. Установщик драйвера
`install-mt7603-patched-driver.sh` выставляет базовые 15 dBm; после его повторного
запуска выполните команды выше снова, если нужен профиль 12 dBm.

## 13. Финальный закрытый backup

```sh
sysupgrade -b /tmp/cudy-dualvpn-working.tar.gz
sha256sum /tmp/cudy-dualvpn-working.tar.gz
```

Скопируйте файл с роутера и не публикуйте. Затем выполните один контролируемый
cold boot: выключить питание на 10 секунд, включить и повторить проверки.
Backup `sysupgrade -b` сохраняет настройки, но **не заменяет** firmware,
совместимые APK и патченные `.ko` из комплекта. Храните их отдельно; после
чистой прошивки пакеты и драйвер нужно устанавливать заново для её точной
версии ядра.
