# Подробная инструкция: Cudy LT300 v3, OpenWrt 25.12.5, WireGuard и AmneziaWG 2.0

Это полный ручной сценарий. Для повторения на идентичном LT300 v3 используйте
сначала [QUICKSTART-RU.md](QUICKSTART-RU.md): он вызывает те же операции двумя
проверяемыми этапами и оставляет этот документ для объяснения и диагностики.

## 1. Назначение и схема

LTE-модем получает ограниченный доступ через специальную SIM/APN. Этот канал служит транспортом до VPN-сервера. После handshake роутер устанавливает VPN-интерфейс маршрутом по умолчанию и раздаёт уже туннелированный интернет по LAN и Wi-Fi.

```text
LAN/Wi-Fi → firewall zone lan → zone vpn → wg0 или awg0 → сервер → Интернет
VPN endpoint → отдельный маршрут /32 → usb0/LTE
```

Маршрут `/32` к endpoint обязателен: после установки default route через VPN управляющие пакеты туннеля не должны попасть внутрь самого туннеля.

Обычный forwarding `lan → wan` отключается как kill switch. Разрешаются точечные UDP-исключения к WG/AWG endpoint. Они позволяют устройству внутри LAN запускать собственный VPN-клиент к тому же серверу: такие пакеты выходят прямо через LTE и не заворачиваются во внешний VPN роутера.

## 2. Совместимость

Этот комплект проверяет:

- board `cudy,lt300-v3`;
- OpenWrt `25.12.5`;
- kernel `6.12.94`;
- target `ramips/mt76x8`;
- architecture `mipsel_24kc`.

Для другой модели нельзя использовать образ из `firmware/`. Для другой версии ядра нельзя устанавливать приложенные `kmod-*.apk`.

## 3. Подготовка к прошивке

1. Подключите компьютер к LAN кабелем.
2. Интернет компьютера можно оставить на другом Wi-Fi.
3. Обеспечьте стабильное питание минимум на 10 минут.
4. Узнайте текущий IP, пароль и точную модель.
5. Скачайте backup и проверьте SHA-256.
6. Не используйте `-F`, firmware другой модели и прямой `mtd write`.

Запишите исходную версию OpenWrt и выясните, поддержан ли переход к 25.12.x.
Для 23.05.x и более старых выпусков [обычное обновление не поддержано
официально](https://openwrt.org/releases/25.12/notes-25.12.3). Даже если
`sysupgrade -T` принимает образ, это подтверждает совместимость образа с board,
но не переносимость старых настроек. Подготовьте штатный способ recovery Cudy
перед началом работы.

```sh
ubus call system board
cat /proc/mtd
free
```

Перед sysupgrade проверьте отсутствие процессов в непрерываемом состоянии `D`:

```sh
for s in /proc/[0-9]*/stat; do
    read p n st rest < "$s"
    [ "$st" = D ] && echo "BLOCKED: $p $n"
done
```

Если ранее завис `rmmod mt7603e`, сначала выполните обычный reboot. Процесс в состоянии `D` нельзя завершить сигналом, а sysupgrade обязан остановить все процессы перед записью.

## 4. Закрытый backup

```sh
sysupgrade -b /tmp/cudy-before-upgrade.tar.gz
sha256sum /tmp/cudy-before-upgrade.tar.gz
```

Скачайте архив командой `scp -O`. Он может содержать `/etc/shadow`, Wi-Fi-пароль и приватные VPN-ключи. Не публикуйте его.

## 5. Чистая установка 25.12.5

Скопируйте sysupgrade-образ в `/tmp`, затем:

```sh
sha256sum /tmp/openwrt.bin
sysupgrade -T /tmp/openwrt.bin
echo $?
```

Сверьте SHA-256 с `checksums/SHA256SUMS`. Только при коде `0`:

```sh
sysupgrade -n -v /tmp/openwrt.bin
```

`-n` не переносит старый overlay. Сначала SSH закроется, затем ping исчезнет на время записи, после чего загрузится новая система. Строка `Command failed: ... Connection failed` при закрытии ubus/SSH обычно штатна.

Не добавляйте `-f <old-backup.tar.gz>` к `-n`: `-f` восстанавливает файлы
архива и отменяет смысл чистого обновления. В частности, **не переносите
`/etc/config/network` старой прошивки**. Для LT300 v3 в OpenWrt 25.12.5
`/etc/board.json` назначает LAN на `eth0.2`, WAN на `eth0.1` и создаёт
switch/VLAN; старый конфиг с мостом на `eth0` может сделать LAN недоступным.
После чистой загрузки меняйте лишь желаемый адрес и прочие параметры через
`uci`, сохраняя сгенерированные порты и VLAN.

Не отключайте питание во время записи. Если остался только ping, а SSH/HTTP закрыты, ждите минимум 8–10 минут. Физическое выключение — крайний вариант после доказанного зависания; безопаснее иметь UART/recovery.

После чистой прошивки адрес обычно `192.168.1.1/24`. Временно задайте компьютеру `192.168.1.2/24`, без шлюза и DNS.

Если после обновления не отвечает ни заводской, ни старый LAN-адрес, сначала
проверьте адрес компьютера, затем используйте [описанный в быстрых шагах
failsafe и штатную регенерацию network](QUICKSTART-RU.md#4-чистое-обновление-до-25125).
Failsafe подтверждает, что ядро загрузилось; без этой проверки не повторяйте
прошивку и не отключайте питание поспешно.

## 6. Первый вход

```sh
ssh root@192.168.1.1
passwd
ubus call system board
mount | grep ' /overlay '
df -h /overlay
```

Должны отображаться OpenWrt 25.12.5, kernel 6.12.94 и writable JFFS2 overlay.

## 7. Офлайн-установка APK

SIM может не видеть публичные репозитории до VPN. Скопируйте `packages/` и `scripts/` в `/tmp` и выполните:

```sh
/tmp/Cudy-LT300-OpenWrt-DualVPN-Kit/scripts/install-packages-25.12.5.sh \
  /tmp/Cudy-LT300-OpenWrt-DualVPN-Kit/packages \
  /tmp/Cudy-LT300-OpenWrt-DualVPN-Kit/checksums/SHA256SUMS
```

Скрипт использует `--no-network`. `--allow-untrusted` нужен для локальных APK без скачанного индекса; это не разрешение устанавливать неизвестные файлы. Скрипт предварительно сверяет каждый APK с `checksums/SHA256SUMS`.
Файл сумм может иметь окончания строк CRLF после передачи с Windows;
установщик учитывает их при поиске записи, не отключая проверку SHA256.

## 8. LTE и APN

На LT300 v3 модем обычно создаёт `usb0` и `/dev/ttyUSB0...3`:

```sh
uci set network.wwan=interface
uci set network.wwan.device='usb0'
uci set network.wwan.proto='dhcp'
uci set network.wwan.metric='100'
uci commit network
ifup wwan
ifstatus wwan
```

APN может храниться внутри модема. На другой модели он настраивается через uqmi, umbim, ModemManager, AT-команду или vendor UI. Сначала выясните модель модема и правильный PDP context.

## 9. Время от модема

При загрузке RTC может показывать старую дату. Это ломает HTTPS, проверку возраста handshake и автоматизацию, а NTP через специальную SIM до VPN недоступен.

`awg-sync-modem-time` читает `AT+CCLK?` из `/dev/ttyUSB2`, выставляет UTC и пишет событие `awg-clock`. Для него включены `coreutils` и `coreutils-stty`.

```sh
ls -l /dev/ttyUSB*
/usr/sbin/awg-sync-modem-time
date -u
logread | grep awg-clock
```

Если AT-порт другой, измените `PORT` в `awg-sync-modem-time` и `awg-modem-recover`.

## 10. Импорт VPN-конфигов

Скопируйте реальные конфиги только в `/tmp`:

```sh
chmod 600 /tmp/wireguard.conf /tmp/amneziawg.conf
/tmp/Cudy-LT300-OpenWrt-DualVPN-Kit/scripts/configure-wireguard-from-conf.sh /tmp/wireguard.conf wg0
/tmp/Cudy-LT300-OpenWrt-DualVPN-Kit/scripts/configure-awg-from-conf.sh /tmp/amneziawg.conf awg0
rm -f /tmp/wireguard.conf /tmp/amneziawg.conf
```

Проверяйте отдельные параметры, но не публикуйте полный `uci show network`.

## 11. Переключатель и firewall

```sh
/tmp/Cudy-LT300-OpenWrt-DualVPN-Kit/scripts/install-dual-vpn-switch.sh \
  wg0 awg0 wwan wg <PROBE_IP> <WG_ADMIN_CIDR> <AWG_ADMIN_CIDR>
```

Создаются `vpn-switch`, `vpn-apply-route`, LuCI-кнопки, zone `vpn`, forwarding `lan → vpn`, endpoint-исключения и файл `vpnmode`.

Два последних аргумента разрешают SSH к самому роутеру только из сетей WireGuard
`<WG_ADMIN_CIDR>` и AmneziaWG `<AWG_ADMIN_CIDR>`. Для них создаются отдельные маршруты через
`wg0`/`awg0`, поэтому ответ не уходит в активный по умолчанию другой туннель. Порт
22 в LTE/WAN не открывается. Подключайтесь к `Address` соответствующего интерфейса
роутера, например `ssh root@<WG_ROUTER_IP>`.

Переключатель сначала поднимает цель и проверяет handshake + ping отдельным временным маршрутом. Рабочий default route меняется только после успеха. Поэтому неисправный резерв не должен уронить текущий режим.

Автоматический failover выключен. На слабом LTE краткие потери нормальны, а агрессивный watchdog создаёт лишние перерегистрации. Сначала подтвердите ручную стабильность.

Если нужен **только WG** с постоянными повторными попытками и без автоматического
перехода на AWG, включите необязательную службу после проверки туннеля. Полный
порядок, замена личного профиля и тест после reboot: [FIXED-WG-RU.md](FIXED-WG-RU.md).

Скрипт `vpn-restore-mode` не является failover: он запускается один раз после boot, ждёт LTE/первый handshake и ограниченное число раз пытается восстановить сохранённый режим `vpnmode.main.mode`. После успеха процесс завершается. Проверка:

```sh
logread | grep vpn-restore-mode
ip -4 route show default
```

## 12. Wi-Fi

Перед включением точки доступа после чистой прошивки задайте собственный
SSID, `psk2` (WPA2) и сильный пароль по [быстрой инструкции](QUICKSTART-RU.md#7-проверить-имена-секций-wi-fi). Смешанный WPA2/WPA3 можно отдельно протестировать после нагрузочной проверки.
Стандартная Wi-Fi-секция OpenWrt может быть выключена и не иметь ключа;
профиль стабильности включает её, но не придумывает безопасный пароль.

Для MT7628/mt7603e используйте HT20. `NOHT` ограничивает скорость 802.11g; HT40 сильнее зависит от загруженности диапазона.

На LT300 v3 обнаружено воспроизводимое зависание/переподключение `mt76` при одновременной реальной интернет-нагрузке нескольких клиентов: клиенты могут остаться associated без трафика, перейти в цикл WPA reconnect, а kernel worker `phy0` — в состояние `D`. Обновление до OpenWrt 25.12.5, отключение U-APSD и `multicast_to_unicast_all=1` по отдельности проблему не устранили.

На первом LT300 v3 нагрузочный тест четырёх телефонов прошёл с HT20/WMM/802.11n, `disassoc_low_ack=0`, DTIM=1, 15 dBm и маской AP TX MCS0–7. Дополнительно были установлены исправленные `mt76.ko`/`mt7603e.ko` с четырьмя upstream PS/U-APSD-патчами; после reboot Wi-Fi, LTE и VPN поднялись автоматически. Это результат для сочетания параметров, а не доказательство необходимости маски отдельно. На втором LT300 v3 пользователь сообщил о нормальной работе после её снятия при WPA2 и 12 dBm; долгосрочный и послеребутный тест ещё необходимы.

Рекомендуемая база:

- канал 1, 6 или 11 после анализа эфира;
- `HT20`, страна `RU`;
- U-APSD выключен;
- `disassoc_low_ack=0`;
- `dtim_period=1`;
- `txpower=15` (на проверенном месте сигналы клиентов около −25…−40 dBm);
- без `multicast_to_unicast_all` — на проверенном устройстве он не помог;
- без автоматической маски AP TX MCS0–7 по умолчанию; включайте её только для
  отдельного сравнительного теста, если профиль без маски нестабилен;
- без SQM до завершения диагностики.

Необязательная установка постоянной маски MCS0–7 на проверяемом экземпляре:

```sh
cp /tmp/Cudy-LT300-OpenWrt-DualVPN-Kit/scripts/wifi-mcs-limit /usr/sbin/wifi-mcs-limit
cp /tmp/Cudy-LT300-OpenWrt-DualVPN-Kit/scripts/99-wifi-mcs-limit /etc/hotplug.d/net/99-wifi-mcs-limit
cp /tmp/Cudy-LT300-OpenWrt-DualVPN-Kit/scripts/wifi-mcs-limit.init /etc/init.d/wifi-mcs-limit
chmod 755 /usr/sbin/wifi-mcs-limit \
  /etc/hotplug.d/net/99-wifi-mcs-limit \
  /etc/init.d/wifi-mcs-limit
/etc/init.d/wifi-mcs-limit enable
/usr/sbin/wifi-mcs-limit
logread | grep wifi-mcs-limit
```

После `wifi down radio0; wifi up radio0` или reboot с установленной маской должна появиться новая строка `Applied HT MCS0-7 TX mask to phy0-ap0`. Скрипт ждёт `hostapd status=ENABLED`, потому что ранняя маска может быть сброшена во время запуска AP. Проверяйте фактическую скорость каждого клиента:

```sh
iw dev phy0-ap0 station dump
```

Если маску включили для теста и решили вернуть исходные скорости, отключите
автоприменение и очистите текущую маску без перезагрузки радио:

```sh
test ! -e /root/99-wifi-mcs-limit.disabled
/etc/init.d/wifi-mcs-limit disable
mv /etc/hotplug.d/net/99-wifi-mcs-limit /root/99-wifi-mcs-limit.disabled
iw dev phy0-ap0 set bitrates
```

`iw` без аргументов очищает установленную маску. Hotplug-скрипт сохранён в
`/root` для отката; проводная сеть и VPN не затрагиваются. Если скрипт уже
переносился, не повторяйте `mv` и проверьте его точное расположение.

Одних MCS0–7, `disassoc_low_ack=0` и DTIM=1 оказалось недостаточно: на 20 dBm драйвер накопил более 100 `Beacon stuck`, `RX PSE busy`, тысячи повторов и очередь из 1077 пакетов. Штатный TX-hang reset очистил очередь. После установки исправленных модулей и снижения мощности до 15 dBm четыре клиента одновременно выдержали реальную нагрузку с маской без обрыва. Из этого теста нельзя заключить, что маска обязательна: на втором экземпляре после её снятия связь стала нормальной. Выполните собственный длительный тест и проверку после отключения питания.

Установка модулей только для точной версии из `drivers/README.md`:

```sh
chmod 755 /tmp/Cudy-LT300-OpenWrt-DualVPN-Kit/scripts/install-mt7603-patched-driver.sh
/tmp/Cudy-LT300-OpenWrt-DualVPN-Kit/scripts/install-mt7603-patched-driver.sh
sync
reboot
```

Скрипт проверяет board, kernel и SHA256, сохраняет штатные модули в `/root` и не делает live `rmmod`. Для отката запустите `rollback-mt7603-patched-driver.sh`, затем reboot.

После настройки подключите минимум два клиента и запустите длительную загрузку:

```sh
iw dev phy0-ap0 station dump
logread -f
free
cat /proc/sys/net/netfilter/nf_conntrack_count
```

Не выгружайте `mt7603e` на работающей системе: зависший `rmmod` способен заблокировать sysupgrade.

## 13. Проверка маршрутов

```sh
fw4 check
ip -4 route show
ip -4 route get <VPN_ENDPOINT_IP>
ip -4 route get 1.1.1.1
```

Endpoint должен идти через gateway LTE на `usb0`, публичный адрес — через активный VPN. `lan → wan` выключен, `lan → vpn` включён.

```sh
/usr/sbin/vpn-use-awg
ping -I awg0 -c 3 1.1.1.1
/usr/sbin/vpn-use-wg
ping -I wg0 -c 3 1.1.1.1
```

## 14. Reboot, cold boot и backup

```sh
sync
reboot
```

После загрузки проверьте версию, время, Wi-Fi, маршруты, DNS и оба handshake. Создайте новый закрытый backup:

```sh
sysupgrade -b /tmp/cudy-configured.tar.gz
sha256sum /tmp/cudy-configured.tar.gz
```

После успешного программного reboot выполните контролируемый cold boot: питание выключить на 10 секунд, включить и повторить проверки. Reset не нажимать.

## 15. Диагностика

Нет handshake:

```sh
date -u
ip -4 route get <VPN_ENDPOINT_IP>
wg show wg0
awg show awg0
logread | tail -n 100
```

`failed the handshake/traffic test` означает: целевой туннель не прошёл безопасную предварительную проверку, поэтому режим не изменён. Проверяйте время, endpoint `/32`, `probe_ip` и доступность probe через оба VPN.

Если Wi-Fi виден, но трафик зависает, смотрите station retries/failed и процессы в состоянии `D`. Если маска включена для теста, `logread | grep wifi-mcs-limit` должен подтвердить её применение. Проверяйте также питание, температуру и канал; исключите SQM и автоматические recovery-циклы. Не выгружайте `mt7603e`: зависший `rmmod` может остановить shutdown/sysupgrade и потребовать цикл питания.

## 16. Другая модель

Переносится логика, но не бинарники и не весь `/etc/config/network`:

- скачайте firmware для точной модели;
- подберите target/architecture/kernel;
- получите соответствующие WG/AWG kmod;
- определите LTE-интерфейс и AT-порт;
- адаптируйте DSA/switch/VLAN;
- сохраните проводной LAN и recovery.
