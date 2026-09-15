# Состав репозитория и логика файлов

## Корень

- `README.md` — назначение, совместимость и маршрут по документации.
- `VERSION`, `CHANGELOG.md` — версия набора и история изменений.
- `SECURITY.md` — правила работы с ключами, конфигами и backup.
- `THIRD-PARTY-NOTICES.md` — происхождение firmware, пакетов и патчей.
- `LICENSE` — MIT для собственных скриптов и текста проекта.

## Документация

- `docs/QUICKSTART-RU.md` — кратчайшее повторение на таком же LT300 v3.
- `docs/INSTALL-RU.md` — ручная пошаговая установка и объяснение команд.
- `docs/ARCHITECTURE-RU.md` — маршруты, firewall, DNS, время и переключение.
- `docs/FIXED-WG-RU.md` — необязательный постоянный WG, замена профиля и reboot-тест.
- `docs/WIFI-MT7603-RU.md` — расследование Wi-Fi, patched-драйвер и откат.
- `docs/TROUBLESHOOTING-RU.md` — диагностика типовых отказов.
- `docs/OTHER-DEVICES-RU.md` — правила переноса на другую модель.

## Бинарные артефакты

- `firmware/` — официальный sysupgrade OpenWrt только для LT300 v3.
- `packages/` — офлайн APK для exact OpenWrt 25.12.5, kernel 6.12.94 и
  `mipsel_24kc`.
- `drivers/mt76.ko`, `drivers/mt7603e.ko` — exact patched Wi-Fi-модули.
- `drivers/patches/` — четыре upstream-патча, применённые при сборке модулей.
- `checksums/SHA256SUMS` — контрольные суммы публикуемых бинарников.

Перед применением бинарников обязательны board/kernel-проверки. Контрольная сумма
подтверждает целостность файла, но не заменяет проверку его источника и подписи.

## Примеры

- `examples/wireguard.example.conf` — синтетический WG-конфиг.
- `examples/amneziawg.example.conf` — синтетический AWG 2.0-конфиг.
- `examples/vpnmode.example` — итоговая схема UCI выбора режима.

Настоящих ключей и endpoint в репозитории нет. Импортёры читают только первый peer;
если в конфиге их несколько, оставьте нужный peer в отдельном временном файле.

## Быстрая установка

- `quick-setup-1-prepare.sh` — exact-проверка устройства, backup, проверка/установка
  APK, импорт VPN, профиль Wi-Fi, служебные скрипты и установка patched-драйвера.
- `quick-setup-2-activate.sh` — после reboot устанавливает DualVPN-маршрутизацию,
  firewall/LuCI-команды, выбирает режим и запускает итоговую проверку.
- `install-packages-25.12.5.sh` — офлайн-установка только после сверки SHA256.
- `configure-wireguard-from-conf.sh`, `configure-awg-from-conf.sh` — безопасный импорт
  первого peer в UCI с `route_allowed_ips=0`.

Этапы разделены reboot, потому что kernel/Wi-Fi-модули нельзя безопасно заменять
«на лету» на работающей точке доступа.

## Переключение и восстановление VPN

- `install-dual-vpn-switch.sh` — устанавливает всю подсистему, firewall-зону `vpn`,
  kill switch, исключения endpoint и кнопки LuCI.
- `vpn-switch` — preflight целевого туннеля, затем атомарная смена default route.
- `vpn-apply-route` — host route endpoint через LTE и default через активный VPN.
- `vpn-restore-mode` + init/hotplug — одноразовое восстановление сохранённого режима
  после boot; это не автоматический failover.
- `enable-persistent-wg.sh`, `vpn-wg-persistent*` — необязательный WG-only watchdog
  с автозапуском, без переключения на AWG.
- `verify-dual-vpn.sh` — итоговая проверка интерфейсов, маршрута и DNS.
- `enable-vpn-remote-ssh.sh` — отдельное идемпотентное обновление уже настроенного
  роутера: backup, два VPN-маршрута и два ограниченных правила TCP/22.

Подсистема также создаёт ограниченные правила удалённого SSH из `<WG_ADMIN_CIDR>` через
WG и `<AWG_ADMIN_CIDR>` через AWG, а также симметричные маршруты ответа. Общий input из
VPN и вход через LTE/WAN остаются закрыты.

Установщик создаёт симлинки `/usr/sbin/vpn-use-wg`, `/usr/sbin/vpn-use-awg` и команду
`/usr/sbin/vpn-status`. Те же команды отображаются в LuCI → System → Custom Commands.

## Время и LTE-модем

- `awg-sync-modem-time` — читает `AT+CCLK?` и устанавливает время до NTP.
- `95-vpn-clock` — hotplug-вызов синхронизации при поднятии LTE.
- `awg-modem-recover` — ограниченное восстановление модема/интерфейса.

Порт `/dev/ttyUSB2` и трактовку часового пояса надо подтвердить на своей ревизии.

## Wi-Fi

- `apply-lt300-wifi-profile.sh` — HT20, фиксированный канал, 15 dBm, U-APSD off,
  DTIM 1 и `disassoc_low_ack=0`.
- `install-mt7603-patched-driver.sh` — exact-проверка, backup и постоянная установка
  `mt76.ko`/`mt7603e.ko`; активация только после reboot.
- `rollback-mt7603-patched-driver.sh` — восстановление stock-модулей из backup.
- `wifi-mcs-limit` + init/hotplug — необязательный сравнительный профиль TX
  MCS0–7; быстрая установка его не ставит и не включает по умолчанию.
- `diagnose-multi-client.sh`, `wifi-load-monitor.sh` — нагрузочная диагностика.
- `cudy-stability-monitor*` — длительный сбор состояния в RAM; включается вручную,
  чтобы не расходовать flash.

## Инструменты сопровождающего

- `tools/validate-repo.ps1` — структура, SHA256, локальные Markdown-ссылки, синтаксис
  shell (если есть WSL) и базовый поиск секретов.
- `tools/build-release.ps1` — создаёт чистый ZIP без `.git`, `dist` и приватных
  конфигов, затем пишет SHA256 рядом.
- `.github/workflows/validate.yml` — повторяет проверки SHA256, shell syntax и ссылок
  в GitHub Actions.

## Что не входит

- реальные WG/AWG-конфиги, ключи, пароли и адреса частного сервера;
- backup `/etc`, `/etc/shadow`, Wi-Fi-конфигурация конкретного владельца;
- подписанный промежуточный OEM-образ Cudy для самого первого перехода на OpenWrt;
- готовые бинарники для иных моделей, target или версий ядра.
