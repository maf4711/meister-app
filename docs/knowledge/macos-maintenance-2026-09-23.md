# Meister: Erkenntnisse zur macOS-Wartung

Stand: 23. September 2026. Die Verhaltenskorrekturen wurden mit meister/MeisterAI v6.31 veröffentlicht. Diese Datei dokumentiert Regeln und Nachweise; sie wird nicht als ausführbare Learned-Fix-Regel eingelesen.

## Dauerhafte Regeln

1. **Preferences bewahren.** Ein fehlgeschlagenes `plutil -lint` beweist keine Beschädigung: TCC, Dateirechte oder eine inzwischen verschwundene Datei können dieselbe Fehlerklasse erzeugen. Keine Einstellungen allein deshalb verschieben oder zurücksetzen. Apple-eigene Preferences im Healer auslassen; andere Fehler als Warnung mit unveränderter Datei melden. Nur tatsächlich erfolgreiche Änderungen als FIX zählen.
2. **Verfügbarkeit prüfen.** Auf dem untersuchten macOS 27.2 fehlt `periodic`. Verfügbarkeit zur Laufzeit prüfen, statt aus Versionsnummern auf vorhandene Programme zu schließen. Fehlende Aufgaben nicht automatisch einplanen. Ein expliziter DNS-Flush bleibt unabhängig möglich; fehlende sudo-Berechtigung und fehlgeschlagene Befehle ehrlich melden. Dry-run führt keine privilegierten Änderungen aus.
3. **Datenvolume messen.** Doctor muss auf Systemen mit `/System/Volumes/Data` dieses Volume prüfen, andernfalls `/`. Beim untersuchten Mac zeigte das Systemvolume 2 %, das Datenvolume dagegen 83 % Belegung mit etwa 639 GiB frei. Das sind historische Messwerte, keine aktuellen Grenzwerte.
4. **Keine Hinweise auf fehlende Backup-Ziele.** Auf ausdrücklichen Nutzerwunsch keine Warnung in Wartung, Doctor oder Tagesübersicht und kein automatisches Öffnen der Time-Machine-Einstellungen. Explizites `backup` bleibt nutzbar. Bereits eingerichtete Ziele können weiterhin auf Backup-Alter geprüft werden.
5. **Beide CLIs synchron halten.** Feature-Quelle ist `MeisterAI.sh`; `scripts/sync-twins.sh` erzeugt `meister.sh`. Beide verwenden dieselben Wartungsregeln und denselben Zustand unter `~/.meister`.
6. **Lernen benötigt Belege.** `learned_fixes.v2.tsv` speichert nur tatsächlich verifizierte, erlaubte Reparaturbefehle mit Modul, Fehlerfingerprint und OS-Kontext. Dokumentierte Erkenntnisse oder bestandene Mock-Tests niemals als erfolgreich ausgeführte Reparatur eintragen. Diese Wissensdatei erteilt keine Ausführungsrechte.
7. **Systemzustand nicht blind verändern.** Vorhandene Sicherheitsdienste, cpu-guard, sim-guard und den laufenden HUD-Prozess erhalten. Schlaf-Assertions sind Diagnosebefunde, keine pauschale Berechtigung zum Beenden von Prozessen. Beim untersuchten Mac waren SIP, FileVault und Firewall aktiv; thermische Warnungen wurden nicht gemeldet.

## Test- und Release-Erkenntnisse

- macOS-spezifische Werkzeuge sind auf Linux nicht vorhanden. Der Plist-Migrationstest verwendet dort einen eng begrenzten `plistlib`-Adapter für Print/Set; auf macOS weiterhin echtes PlistBuddy. Die Assertions bleiben identisch. Beide Wege wurden lokal getestet, anschließend bestand die Linux-CI.
- Lokaler Qualitätscheck: `bash scripts/check.sh`; 172 Bats-Tests, 22 Python-Tests und 24 Offline-Evaluationsfälle bestanden. Die Offline-Evaluation belegt keine Live-Modellqualität.
- GitHub-Releases an die vollständige Commit-SHA binden. Der Versuch mit einer verkürzten SHA wurde von GitHub zurückgewiesen; die vollständige SHA funktionierte.
- Ein gerade angelegtes Tag-Archiv kann zunächst 404 liefern. Release und Tag über GitHub prüfen, erneut abrufen und die SHA256 des tatsächlich heruntergeladenen Release-Archivs verwenden. Niemals eine Ersatzdatei ungeprüft mit der veröffentlichten Prüfsumme verbinden.
- Homebrew bleibt Eigentümer der installierten Binaries. Nach dem Release Formula aktualisieren, lokal installieren und beide Versionen sowie Dateiinhalte prüfen. Ein temporärer lokaler Snapshot ist kein veröffentlichtes Release; die Tap-Formula muss anschließend exakt wiederhergestellt werden.
- Veröffentlichte Tags nicht verschieben. Nachfolgende reine CI-Testkorrekturen wurden separat auf main committed.

## Ablage und Zuständigkeit

Dieses Wissen gehört zum Meister-App-Projekt unter `~/Developer/meister` (`maf4711/meister-app`). Die implementierten Bash-Korrekturen liegen im kanonischen Backend `maf4711/homebrew-meister` und sind als v6.31 veröffentlicht und lokal installiert. Die App verwendet dieses CLI; die Implementierung wird hier nicht als zweite Bash-Kopie dupliziert.

## Nachweise

- Release: https://github.com/maf4711/homebrew-meister/releases/tag/v6.31
- Release-Commit: `f42211de1b416b3475e113fc44e92fbe532f9c9c`
- Formula-Commit: `b8b5930dead0c1f164cabc79a1620e9dd85117dd`
- CI-Testkorrektur: `f1671008e40dc8b466620e49f0ec22155728bf6f`
- Grüne Linux-/macOS-CI einschließlich nativer Tests und Release-Build: https://github.com/maf4711/homebrew-meister/actions/runs/35844787154
- Installationsprüfung: beide CLIs meldeten v6.31; `brew test maf4711/meister/meister` bestand. Installierte CLI-Dateien stimmten mit dem Quellcode überein.
- Details: [Reparaturbericht](https://github.com/maf4711/homebrew-meister/blob/main/docs/verification/2026-09-23-macos-repair.md), [Release-Notizen](https://github.com/maf4711/homebrew-meister/blob/main/docs/releases/6.31.md).

## Recap

- Wartungsregeln, Nutzerpräferenz, Testbefunde und Release-Erkenntnisse sind hier dauerhaft dokumentiert.
- Die entsprechenden Verhaltenskorrekturen sind in v6.31 enthalten; dieses Dokument ergänzt das Wissen für künftige Arbeiten.
