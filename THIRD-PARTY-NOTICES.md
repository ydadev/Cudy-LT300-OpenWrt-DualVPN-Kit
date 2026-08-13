# Источники сторонних компонентов

- [OpenWrt 25.12.5](https://downloads.openwrt.org/releases/25.12.5/) — firmware и
  официальные APK; точные хеши target находятся в
  [ramips/mt76x8/sha256sums](https://downloads.openwrt.org/releases/25.12.5/targets/ramips/mt76x8/sha256sums).
- [Исходный код OpenWrt](https://github.com/openwrt/openwrt) и включённые в него
  сведения о лицензиях пакетов.
- [AmneziaWG kernel module](https://github.com/amnezia-vpn/amneziawg-linux-kernel-module)
  и связанные upstream-проекты Amnezia.
- [OpenWrt-сборки AmneziaWG](https://github.com/Slava-Shchipunov/awg-openwrt),
  release/tag `v25.12.5`. Это сторонняя сборка, не официальный пакет OpenWrt.
- [mt76 upstream](https://github.com/openwrt/mt76). Модули в `drivers/` собраны из
  ревизии OpenWrt 25.12.5 `39c960c3` с последующими коммитами `baac541c`,
  `56fe4e0c`, `276db249`, `5504bac4`; полные тексты патчей приложены.

MIT-файл в корне распространяется только на собственные скрипты и документацию
этого проекта. Firmware, APK, kernel-модули и патчи сохраняют авторские права и
лицензии соответствующих upstream-проектов. При создании форка или бинарного релиза
сохраняйте это уведомление, ссылки на точный исходный код и лицензионные метаданные,
встроенные в пакеты и firmware.
