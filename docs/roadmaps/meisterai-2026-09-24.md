# MeisterAI: Roadmap für Integration und Release-Verhalten

Ziel: Die bereits veröffentlichten Wartungskorrekturen in der Meister-App zuverlässig nutzen und die beim letzten CPR beobachteten Release-Nebeneffekte abstellen. Umsetzung im Meister-App-Repository; CLI-Fachlogik bleibt im Homebrew-Backend. Keine neuen Backup-Ziel-Hinweise. Kein TestFlight-Upload, keine Nachricht und kein Produktionsrelease als Teil dieser Roadmap.

## Anforderungen und Abnahme

| ID | Arbeitspaket | Abnahme | Status |
|---|---|---|---|
| R1 | MeisterAI bevorzugen, vorhandenes meister als Fallback erhalten | Hermetische Swift-Tests für Reihenfolge, Fallback, nicht ausführbare und fehlende Dateien; Argumente und Ausgabe bleiben unverändert | erledigt |
| R2 | Automatisches TestFlight und Nachrichten nur nach expliziter Aktivierung | Fixture-Tests beweisen: Standard ohne Build/Upload/Nachricht; beide Aktivierungen unabhängig, vorhandene Sperrdateien gehen vor; Nachricht als AppleScript-Argument | erledigt |
| R3 | Verhaltensprüfungen in CI und Dokumentation | macOS-Swift-Pakettests und isolierte Skripttests statt bloßer README-Prüfung; lokale Prüfungen bestanden; Betriebshinweise aktuell | erledigt |

## Reihenfolge und Teststrategie

1. Bestand aufgenommen und Paket-Baseline mit `swift test --package-path Packages/MeisterKit` geprüft (Exit 0).
2. R1: Tests in `Packages/MeisterKit/Tests/MeisterKitTests/MeisterBashTests.swift`; temporäre ausführbare Skripte statt Änderungen an Homebrew. Zuerst falsche Präferenz nachweisen, anschließend minimalen Resolver ergänzen.
3. R2 parallel in isoliertem Worktree: `scripts/tests/test_release_guards.py` verwendet Kopien und Stubs, führt keine externen Aktionen aus. Zuerst bisherige Nebenwirkungen nachweisen.
4. R3: CI führt beide Tests auf passenden Plattformen aus; Workflow und README dokumentieren Grenzen. Kein Simulator wird gebootet.
5. Unabhängiger Review, vollständige lokale Prüfungen, Ergebnis und verbleibende Grenzen hier dokumentieren. Integration erfolgt lokal; Veröffentlichung benötigt einen neuen expliziten Release-Auftrag.

## Ergebnis und Nachweise

- R1: Ausgangstest scheiterte mit tatsächlicher Auswahl `/opt/homebrew/bin/meister` statt `MeisterAI`. Nach Korrektur bestehen sechs hermetische Bridge-Tests plus der vorhandene Shell-Test (7/7). Sie verwenden temporäre Skripte und verändern Homebrew nicht.
- R2: Die neuen Schutztests scheiterten zunächst an den unbeabsichtigten Nebenwirkungen. Nach Korrektur bestehen alle zehn Fixture-Tests. TestFlight und Kontaktbenachrichtigung benötigen getrennte, exakt auf `1` gesetzte Aktivierungen; die bisherigen Sperrdateien gehen vor. Nachrichtentext wird nicht mehr in AppleScript-Quelltext interpoliert.
- R3: CI enthält einen Ubuntu-Job für Skripttests und einen macOS-Job für Paket- und Skripttests. `actionlint` besteht. Alle drei betroffenen Shell-Skripte sind einzeln auf Syntax geprüft; die SwiftUI-Datei besteht den Swift-Syntaxparser.
- Unabhängiger Review abgeschlossen. Sein Hinweis, Shell-Dateien einzeln statt als weitere Argumente an `bash -n` zu prüfen, wurde umgesetzt.
- Änderungen lokal in `~/Developer/meister` übernommen. Anschließender CPR-Auftrag autorisiert Commit, Push und Quellcode-Release; TestFlight und Kontaktaufnahme bleiben deaktiviert.

## Prüfgrenzen

Der vollständige macOS-Release-Build wurde im CPR erfolgreich für arm64 und x86_64 ausgeführt. Die vorhandene Abhängigkeit unter `~/Developer/meradOS-Design4` wurde über den dokumentierten Guard-Override geprüft und für den Build in der temporären Xcode-Projektkonfiguration gesetzt. Der kanonische relative Pfad bleibt eine Einschränkung für frische Checkouts. Für extern verteilbare notarisierten App-Binaries fehlt lokal ein Developer-ID-Zertifikat; der Release veröffentlicht den Quellcode. Der nachfolgende Remote-Merge enthielt Referenzen auf drei fehlende Helferdateien. Diese wurden ergänzt und mit zwei zusätzlichen Offline-Swift-Harnesses geprüft (insgesamt 12 Python-Testfälle). Der zusammengeführte App-Release-Build für arm64 und x86_64 besteht. Prozess-Timeouts gelten für den direkt gestarteten Prozess; Prozessbaum-Abbruch und Ausgabemengenbegrenzung sind nicht implementiert. Die CI-Jobs werden nach dem finalen Push geprüft.

## Recap

Alle drei Arbeitspakete sind implementiert und lokal geprüft: 7 Swift-Tests, 10 Skripttests, Workflow- und Syntaxprüfungen grün. Änderungen liegen im Meister-Projekt; Der vollständige App-Build ist ebenfalls erfolgreich; CPR veröffentlicht den Quellcode und prüft CI sowie lokale Installation.
