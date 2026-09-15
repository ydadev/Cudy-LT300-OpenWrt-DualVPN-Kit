# Cudy LT300 OpenWrt DualVPN Kit

Воспроизводимый комплект для **Cudy LT300 v3** с OpenWrt 25.12.5: LTE
используется как транспорт, а весь клиентский трафик выходит в
интернет через WireGuard или AmneziaWG 2.0.

Репозиторий основан на настройке и нагрузочном тестировании реального LT300 v3.
Он включает офлайн-пакеты, примеры конфигураций без ключей, ручной переключатель
VPN в LuCI, kill switch, восстановление маршрутов после загрузки и исправленные
модули Wi-Fi MT7603.

> Это независимый проект, не официальный продукт Cudy, OpenWrt или Amnezia.

## Что получилось

- `usb0`/`wwan` — LTE-транспорт до VPN endpoint;
- WireGuard — основной быстрый режим;
- AmneziaWG 2.0 — ручной резерв;
- оба туннеля остаются поднятыми, а выбранный режим определяет только основной
  маршрут интернет-трафика; SSH через резервный туннель продолжает работать;
- переключение командами или кнопками **System → Custom Commands**;
- проверка handshake и трафика до смены default route;
- endpoint обоих туннелей всегда маршрутизируется прямо через LTE;
- LAN/Wi-Fi не получает прямой выход в LTE при падении VPN;
- клиент за роутером может поднять собственный WG/AWG к тем же endpoint;
- время до NTP берётся от LTE-модема;
- выбранный VPN-режим восстанавливается после reboot;
- необязательная служба закрепляет WG и бесконечно повторяет восстановление без
  переключения на AWG;
- SSH к роутеру разрешён из `<WG_ADMIN_CIDR>` и `<AWG_ADMIN_CIDR>`, но не открыт в LTE/WAN;
- Wi-Fi выдержал одновременную реальную нагрузку четырёх телефонов.

## Точная совместимость готовых бинарников

| Параметр | Значение |
|---|---|
| Устройство | Cudy LT300 v3 |
| Board | `cudy,lt300-v3` |
| OpenWrt | `25.12.5 r33051-f5dae5ece4` |
| Target | `ramips/mt76x8` |
| Architecture | `mipsel_24kc` |
| Kernel | `6.12.94` |
| Wi-Fi | MT7628AN / `mt7603e` / `mt76` |
| Package manager | `apk` |

APK, firmware и `.ko` из этого репозитория нельзя устанавливать на другую
модель, target или kernel. Для другого OpenWrt-устройства переносится логика, но
пакеты и драйверы подбираются заново.

## Быстрый путь

Если на LT300 v3 уже работает OpenWrt, начните с
[QUICKSTART-RU.md](docs/QUICKSTART-RU.md). После передачи каталогов
`packages/`, `drivers/`, `scripts/`, `checksums/` и двух личных конфигов только в
`/tmp` основная установка выполняется в два этапа:

> При переходе со старой OpenWrt не переносите её `/etc/config/network`:
> OpenWrt 25.12.5 создаёт для LT300 v3 собственную схему LAN/VLAN. Перед
> запуском первого этапа задайте защищённые SSID и пароль Wi-Fi — скрипт
> включит радиомодуль. Оба шага подробно описаны в быстром руководстве.

```sh
/tmp/Cudy-LT300-OpenWrt-DualVPN-Kit/scripts/quick-setup-1-prepare.sh \
  /tmp/wireguard.conf /tmp/amneziawg.conf
reboot
```

После повторного входа по Ethernet:

```sh
/root/cudy-dualvpn-stage2/quick-setup-2-activate.sh \
  wg 1.1.1.1 <WG_ADMIN_CIDR> <AWG_ADMIN_CIDR>
```

Скрипты проверяют board, OpenWrt, kernel и SHA256, создают backup и не печатают
приватные ключи. Прошивку и первый переход со штатной Cudy firmware выполняйте
отдельно по официальной инструкции: для OEM требуется подписанный промежуточный
образ Cudy.

## Wi-Fi: что было выяснено

На штатном `mt7603e` точка под несколькими клиентами формально оставалась `UP`,
но трафик останавливался. Наблюдались:

- сотни `Beacon stuck` и отдельные `RX PSE busy stuck`;
- тысячи TX retries/failed при сильном сигнале;
- зависшая очередь mac80211 до 1077 пакетов и примерно 1,45 МБ;
- Ethernet, LTE, CPU и весь роутер при этом продолжали работать.

Четыре свежих upstream-исправления PS/U-APSD уменьшили сбои, а рабочий профиль
получился после снижения `txpower` с 20 до **15 dBm**. Итоговый профиль:

- HT20, корректный country code, фиксированный канал;
- U-APSD off, `disassoc_low_ack=0`, DTIM=1;
- AP TX MCS0–7;
- patched `mt76.ko`/`mt7603e.ko`;
- 15 dBm.

Подробности, счётчики, сборка и откат: [WIFI-MT7603-RU.md](docs/WIFI-MT7603-RU.md).

## Документация

- [Быстрое повторение на таком же LT300 v3](docs/QUICKSTART-RU.md)
- [Полная пошаговая установка](docs/INSTALL-RU.md)
- [Архитектура DualVPN и маршрутизация](docs/ARCHITECTURE-RU.md)
- [Постоянный WG и замена приватного профиля](docs/FIXED-WG-RU.md)
- [Расследование и стабилизация MT7603](docs/WIFI-MT7603-RU.md)
- [Диагностика и восстановление](docs/TROUBLESHOOTING-RU.md)
- [Перенос на другую модель OpenWrt](docs/OTHER-DEVICES-RU.md)
- [Состав файлов и логика скриптов](docs/FILES-RU.md)
- [Безопасность публикации](SECURITY.md)
- [Сторонние компоненты и источники](THIRD-PARTY-NOTICES.md)

## Важные ограничения

- Автоматический failover намеренно выключен. По умолчанию переключение ручное;
  дополнительный фиксированный режим WG отменяет ручной выбор AWG, пока включён.
- `rmmod mt7603e` на работающей системе не используйте: зависшая выгрузка может
  заблокировать shutdown/sysupgrade.
- Не используйте `sysupgrade -F`, прямой `mtd write` или образ от другой ревизии.
- После обновления OpenWrt/ядра кастомные Wi-Fi-модули надо пересобрать.
- Реальные ключи, пароли и backup не должны попадать в git.

## Лицензии

Собственные скрипты и документация распространяются по MIT. Firmware, APK,
модули и патчи сохраняют лицензии своих upstream-проектов; см.
[THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).

## Проверка и локальный release

Перед публикацией:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\validate-repo.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\build-release.ps1
```

Архив и его SHA256 появятся в `dist/` и намеренно не добавляются в git. Репозиторий
проекта: [ydadev/Cudy-LT300-OpenWrt-DualVPN-Kit](https://github.com/ydadev/Cudy-LT300-OpenWrt-DualVPN-Kit).
