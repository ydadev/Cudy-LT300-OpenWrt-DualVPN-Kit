# Участие в проекте

Перед изменением укажите точные board, OpenWrt release, kernel и architecture, на
которых оно проверено. Не заменяйте приложенные kernel-модули бинарниками от другой
сборки и не ослабляйте exact-проверки без отдельного варианта установки.

Перед pull request:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\validate-repo.ps1
```

В PR опишите cold boot, число Wi-Fi-клиентов, длительность нагрузки, активный VPN и
результат kill-switch-теста. Удалите из логов ключи, пароли, IMSI/IMEI, APN, публичный
IP сервера и закрытые адреса инфраструктуры.

Сообщение о проблеме должно содержать вывод `ubus call system board`, `uname -r`,
`apk --print-arch`, обезличенный `vpn-status`, релевантный `dmesg/logread` и точный
момент возникновения сбоя.
