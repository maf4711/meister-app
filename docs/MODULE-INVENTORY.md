# macOS-Modulinventar

Stand: 23. September 2026. Aus `BashModule.all` erfasst. „Vorhanden“ bedeutet registriert und im Build enthalten; kein Nachweis eines real ausgeführten Änderungsablaufs.

87 registrierte Module, davon 50 native Ansichten und 37 CLI-Einstiege.

| Bereich | Modul | ID | Anbindung |
|---|---|---|---|
| overview | Dashboard | `dashboard` | Native Ansicht |
| overview | Health Score | `health-score` | Native Ansicht |
| overview | Health Dashboard | `health` | `meister -H` |
| overview | TUI Menu | `menu` | `meister menu` |
| maintenance | Maintenance Preview | `maintain-dry` | `meister -n -a` |
| maintenance | Run All Maintenance | `maintain-all` | `meister -a` |
| maintenance | Auto-Heal Preview | `heal-dry` | `meister heal --dry-run` |
| maintenance | Auto-Heal | `heal` | `meister heal` |
| maintenance | Install LaunchAgent | `launch-agent` | `meister -I` |
| storage | Alles erledigen | `auto-clean-all` | Native Ansicht |
| storage | Quick Clean | `quick-clean` | Native Ansicht |
| storage | Autopilot | `autopilot` | Native Ansicht |
| storage | Storage Forecast | `storage-forecast` | Native Ansicht |
| storage | Extended Attrs | `extended-attributes` | Native Ansicht |
| storage | Symlink Inspector | `symlink-inspector` | Native Ansicht |
| storage | System Cleanup | `system-cleanup` | Native Ansicht |
| storage | Uninstaller | `uninstaller` | Native Ansicht |
| storage | Bloatware Remover | `bloatware` | Native Ansicht |
| storage | Large & Old Files | `large-old-files` | Native Ansicht |
| storage | Duplicate Finder | `duplicates` | Native Ansicht |
| storage | Undo Last Cleanup | `undo-cleanup` | Native Ansicht |
| storage | Disk Analyzer | `disk` | `meister disk` |
| storage | Large Files | `large-files` | `meister -L -n` |
| storage | Clean Caches | `caches` | `meister -C -n` |
| storage | Empty Trash | `trash` | `meister -T -n` |
| storage | Hard Trash Tool | `hardtrash` | `meister -~:hardtrash` |
| storage | Git Cleanup | `git-clean` | `meister -G -n` |
| storage | Xcode Cleanup | `xcode-clean` | `meister -X -n` |
| storage | Free RAM | `free` | `meister free` |
| storage | Startup Items | `startup` | `meister startup` |
| storage | Clear Recent Items | `clear-recent` | `meister -clearrecent` |
| privacy | Security Status | `security-status` | Native Ansicht |
| privacy | App Permissions (TCC) | `app-permissions` | Native Ansicht |
| privacy | Wi-Fi Networks | `wifi-passwords` | Native Ansicht |
| privacy | Hosts Blocklist | `hosts-blocklist` | Native Ansicht |
| privacy | Keychain Audit | `keychain-audit` | Native Ansicht |
| privacy | SSH Keys | `ssh-keys` | Native Ansicht |
| privacy | Browser Privacy | `browser-privacy` | Native Ansicht |
| privacy | Login Items & Agents | `login-items` | Native Ansicht |
| privacy | /etc/hosts | `hosts-file` | Native Ansicht |
| privacy | Notification Perms | `notification-perms` | Native Ansicht |
| privacy | VPN Status | `vpn-status` | Native Ansicht |
| backup | Time Machine & Snapshots | `time-machine` | Native Ansicht |
| backup | iCloud Drive | `icloud-sync` | Native Ansicht |
| network | DNS-Cache löschen | `dns-flush` | Native Ansicht |
| network | Wi-Fi Diagnostics | `wifi` | `meister wifi` |
| network | Open Ports | `ports` | `meister ports` |
| network | DNS Leak Test | `dns` | `meister dns` |
| network | DNS Debug | `dns-debug` | `meister -dns-debug` |
| network | SSL Certificates | `certs` | `meister certs` |
| network | Network Top | `ntop` | `meister ntop 1` |
| network | Process Top | `top` | `meister top 1` |
| network | Network Sniffer | `sniff` | `meister sniff 1` |
| network | Sniffnet Monitor | `sniffnet` | `meister -N` |
| hardware | Hardware Inventory | `hardware-inventory` | Native Ansicht |
| hardware | Disk Health (SMART) | `ssd-health` | Native Ansicht |
| hardware | Disk Map | `disk-map` | Native Ansicht |
| hardware | Prozess-Manager | `process-manager` | Native Ansicht |
| network | Network Connections | `network-connections` | Native Ansicht |
| maintenance | System Updates | `system-updates` | Native Ansicht |
| maintenance | Spotlight Index Audit | `spotlight-audit` | Native Ansicht |
| maintenance | Crash Reports | `crash-reports` | Native Ansicht |
| macTools | Code Signature | `code-signature` | Native Ansicht |
| hardware | Memory Pressure (Live) | `memory-pressure` | Native Ansicht |
| hardware | Bluetooth Devices | `bluetooth-devices` | Native Ansicht |
| hardware | Energy Impact | `energy-impact` | Native Ansicht |
| hardware | USB Devices | `usb-devices` | Native Ansicht |
| hardware | Battery Health | `battery` | `meister battery` |
| hardware | Thermal | `thermal` | `meister thermal 1` |
| hardware | Performance Check | `performance` | `meister -P -n` |
| macTools | Xcode Switcher | `xcode-switcher` | Native Ansicht |
| macTools | Simulator Manager | `simulator-manager` | Native Ansicht |
| macTools | Docker Cleanup | `docker-cleanup` | Native Ansicht |
| macTools | Brew Doctor | `brew-doctor` | Native Ansicht |
| macTools | Rosetta Audit | `rosetta-audit` | Native Ansicht |
| macTools | Install Rosetta | `rosetta` | `meister -rosetta` |
| macTools | Simulator Fix | `simfix` | `meister simfix` |
| macTools | Reset Safari | `reset-safari` | `meister -resetsafari` |
| macTools | Spotlight Repair | `spotlight-fix` | `meister -spotOK` |
| macTools | Organize Desktop | `desktop-fix` | `meister -organise_desktop_fix` |
| macTools | Monitor Controller | `moncon` | `meister -moncon` |
| macTools | Default Apps | `default-apps` | Native Ansicht |
| macTools | Slack Webhook | `slack-webhook` | Native Ansicht |
| dataTools | AddressBook Cleanup | `addressbook` | Native Ansicht |
| dataTools | Tag Manager | `tag-manager` | Native Ansicht |
| dataTools | Dotfiles Status | `dotfiles-status` | `meister -dotfiles` |
| dataTools | Dotfiles Push | `dotfiles-push` | `meister push` |

## Prüftiefe

Alle Module sind im macOS-Testbuild kompiliert. Die bestehenden Destination-Tests erzeugen jede Zielansicht. Parser-, Modell- und Dateisystemtests decken ausgewählte Funktionen ab. Administratoraktionen, echte Bereinigungen, Keychain-Migration und externe Übertragungen wurden nicht an persönlichen Daten ausgeführt.

Nächste Schritte und Integrationstiefe: [Roadmap](ROADMAP.md).
