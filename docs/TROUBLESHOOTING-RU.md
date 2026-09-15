# Диагностика и восстановление

Этот раздел рассчитан на Cudy LT300 v3 с точной сборкой из таблицы совместимости в
корневом `README.md`. Все команды выполняются по Ethernet: при неисправности Wi-Fi
не следует диагностировать роутер через саму проблемную радиосеть.

## Сначала собрать состояние

Не перезагружайте устройство до сохранения журналов: после reboot важные признаки
исчезнут. Скопируйте `scripts/collect-device-info.sh` в `/tmp`, затем:

```sh
chmod 700 /tmp/collect-device-info.sh
/tmp/collect-device-info.sh > /tmp/device-info.txt 2>&1
logread > /tmp/logread.txt
dmesg > /tmp/dmesg.txt
```

VPN-состояние без вывода приватных ключей:

```sh
/usr/sbin/vpn-status
ip -4 route
ifstatus wwan
wg show wg0
awg show awg0
date -u
```

Не публикуйте полный `uci export`, `/etc/config/network`, backup или вывод команд,
в котором присутствуют приватные ключи.

## В LuCI написано «Unsupported protocol»

Это означает, что UCI знает протокол `amneziawg`, но netifd/LuCI не нашёл его
обработчик. Проверьте установку пакетов и модуль:

```sh
apk info -e kmod-amneziawg amneziawg-tools luci-proto-amneziawg
lsmod | grep -E 'amnezia|wireguard'
test -x /lib/netifd/proto/amneziawg.sh && echo OK
awg --version
```

Если пакеты отсутствуют, заново передайте `packages/`, `checksums/` и запустите:

```sh
/tmp/Cudy-LT300-OpenWrt-DualVPN-Kit/scripts/install-packages-25.12.5.sh \
  /tmp/Cudy-LT300-OpenWrt-DualVPN-Kit/packages \
  /tmp/Cudy-LT300-OpenWrt-DualVPN-Kit/checksums/SHA256SUMS
reboot
```

Не устанавливайте приложенные APK на другую версию ядра.

## Кнопка переключения сообщает, что тест не пройден

Сообщение `Target tunnel ... failed the handshake/traffic test` — защитное. Старый
рабочий default route намеренно сохранён. Проверьте по порядку:

```sh
date -u
ifstatus wwan
ip -4 route get 203.0.113.10
wg show wg0 latest-handshakes
awg show awg0 latest-handshakes
logread -e netifd -e wireguard -e amnezia
```

В третьей команде подставьте реальный IP своего VPN endpoint. Маршрут до него должен
идти через LTE/`wwan`, а не через `wg0` или `awg0`. Затем попробуйте явно:

```sh
/usr/sbin/vpn-use-wg
/usr/sbin/vpn-use-awg
```

Типовые причины: LTE ещё не зарегистрирован, неверное время, endpoint/порт
недоступен через APN, устаревшие ключи, неверные параметры обфускации AWG, либо
сервер не разрешает адрес клиента.

## Handshake есть, но трафика нет

```sh
ip -4 route show default
ip -4 rule
nft list ruleset | grep -E 'lan|vpn|wwan'
ping -c 3 -I wg0 1.1.1.1
ping -c 3 -I awg0 1.1.1.1
nslookup openwrt.org 127.0.0.1
```

Для DualVPN у обоих peer должно быть `route_allowed_ips='0'`: default route создаёт
только `vpn-apply-route`. Значение `1` у обоих peer вызывает конкурирующие маршруты.
Проверьте firewall-зону `vpn`, masquerading на ней и forwarding `lan -> vpn`.
Прямой `lan -> wwan` должен оставаться выключенным — это kill switch.

## После холодного старта интернет появляется не сразу

LTE-модему нужно зарегистрироваться, выдать DHCP и сообщить время; только потом
возможен корректный handshake. Проверьте службы восстановления:

```sh
/etc/init.d/vpn-restore-mode enabled && echo enabled
/etc/init.d/vpn-restore-mode status
logread -e vpn-restore -e CCLK -e wwan
cat /etc/config/vpnmode
```

Ручное восстановление:

```sh
/usr/sbin/awg-sync-modem-time
ifup wwan
sleep 5
/usr/sbin/vpn-restore-mode
```

На испытанном модеме ответ `AT+CCLK?` соответствовал UTC. На другой ревизии или
операторе часовой пояс надо проверить вручную; неверная интерпретация времени может
сломать TLS/DNSSEC и диагностику, хотя сам WireGuard не использует сертификаты.

## Клиент за LT300 запускает свой WG/AWG к тому же серверу

Внешний туннель роутера не должен поглощать управляющие UDP-пакеты внутреннего
клиента. Установщик создаёт точечные исключения к адресам и портам обоих endpoint
через `wwan`. Проверьте маршрут и правила firewall:

```sh
ip -4 route get 203.0.113.10
nft list ruleset | grep -E '51820|51821|wwan'
```

Подставьте реальные адрес и порты. Если endpoint задан доменным именем и его IP
сменился, обновите UCI и повторно запустите установщик переключателя. Альтернатива
на клиенте — отдельный host route к endpoint через LAN-шлюз до включения VPN.

## SSH через WG/AWG не открывается

Подключайтесь к VPN-адресу самого роутера, например `<WG_ROUTER_IP>`, а не к LAN-адресу.
Проверьте на роутере:

```sh
ss -lnt | grep ':22 '
uci show firewall.vpn_admin_ssh_wg
uci show firewall.vpn_admin_ssh_awg
ip -4 route show <WG_ADMIN_CIDR>
ip -4 route show <AWG_ADMIN_CIDR>
```

Если Dropbear в `/etc/config/dropbear` принудительно привязан только к `lan`, он не
слушает VPN-адрес. Сначала сохраните Ethernet-доступ, затем удалите ограничение
`option Interface 'lan'`, перезапустите Dropbear и повторите тест. На VPN-сервере
должны быть обратные маршруты, а его firewall должен разрешать трафик между peer.
Не добавляйте общий `vpn input ACCEPT` и не открывайте порт 22 в `wan`.

### AWG-SSH работает, WG-SSH не работает

Сначала не путайте доступность интерфейса с выбранным default route. Оба туннеля
остаются поднятыми, поэтому при `default dev wg0` вход по адресу `awg0` всё равно
может работать. Фактический выход проверяется так:

```sh
ip -4 route show default
ip -4 route get 1.1.1.1
```

Затем во время попытки WG-SSH смотрите счётчики точечных правил:

```sh
nft list chain inet fw4 input_vpn
# имя цепочки зоны может отличаться; при необходимости:
nft list ruleset | grep -B3 -A3 '<WG_ADMIN_CIDR>'
```

Если счётчик правила WG остаётся `0`, TCP SYN до роутера не дошёл. Не меняйте
firewall роутера наугад: проверьте маршрут клиента и сервер. Для схемы
`роутер=<WG_ROUTER_IP>`, `клиент=<WG_CLIENT_IP>` сервер должен назначить этим двум peer
`AllowedIPs = <WG_ROUTER_IP>/32` и `AllowedIPs = <WG_CLIENT_IP>/32`, включить IPv4 forwarding
и разрешить forwarding `wg0 → wg0`. На клиенте `AllowedIPs` должен включать
`<WG_ROUTER_IP>` (например, `<WG_ADMIN_CIDR>` или `0.0.0.0/0`).

Обратная проверка с роутера:

```sh
ip -4 route get <WG_CLIENT_IP>
ping -I wg0 -c 4 <WG_CLIENT_IP>
```

Свежий handshake роутера с сервером не гарантирует связь с другим peer того же
сервера. При ошибке старого PuTTY `Couldn't agree a host key algorithm
(available: rsa-sha2-256)` используйте актуальный PuTTY или Windows OpenSSH; не
включайте устаревший `ssh-rsa` ради обхода ошибки клиента.

## Wi-Fi исчезает или перестаёт передавать трафик под нагрузкой

Сначала убедитесь, что Ethernet, LTE и VPN продолжают работать. Затем:

```sh
dmesg | grep -E 'Beacon stuck|RX PSE busy|mt7603|mt76'
iw dev wlan0 station dump
cat /sys/kernel/debug/ieee80211/phy0/aqm 2>/dev/null
/tmp/diagnose-multi-client.sh
```

На проверенном LT300 проблема была в пути энергосбережения/буферизации MT7603, а
не в DHCP или VPN. Итоговое решение — точные patched-модули плюс профиль HT20,
15 dBm, U-APSD off, DTIM 1 и MCS0–7. Подробности и контрольные хеши находятся в
`WIFI-MT7603-RU.md`.

Если обрывы остаются на другом экземпляре при 15 dBm, попробуйте уменьшить
мощность до 12 dBm по командам из раздела «Нагрузочный тест» в
`QUICKSTART-RU.md`. На втором LT300 v3 фактические 12 dBm подтверждены через
`iw`, но их устойчивость под нагрузкой ещё требует проверки. После изменения
учитывайте уменьшение радиуса покрытия и сравнивайте счётчики Wi-Fi, не только
индикатор доступа к интернету на телефоне.

Никогда не выполняйте `rmmod mt7603e` на работающем роутере. Выгрузка может зависнуть
в состоянии `D` и помешать штатному reboot/sysupgrade.

## Безопасный откат Wi-Fi-драйвера

Откат выполняется только с Ethernet и завершается reboot:

```sh
/tmp/Cudy-LT300-OpenWrt-DualVPN-Kit/scripts/rollback-mt7603-patched-driver.sh
reboot
```

Если сеть уже не стартует, используйте OpenWrt failsafe по Ethernet, восстановите
файлы из `/root/mt7603-driver-backup` и перезагрузитесь. Не прошивайте устройство
в момент, когда процесс находится в состоянии `D`.

## Проверка после исправления

```sh
/usr/sbin/vpn-status
/tmp/Cudy-LT300-OpenWrt-DualVPN-Kit/scripts/verify-dual-vpn.sh
dmesg | grep -c 'Beacon stuck'
```

Нагрузите сеть минимум двумя, лучше четырьмя Wi-Fi-клиентами 10–15 минут. Одновременно
проверяйте ping до роутера, внешний ping, DNS, handshake и рост Wi-Fi-счётчиков.
