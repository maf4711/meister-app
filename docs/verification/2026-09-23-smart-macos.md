# Meister macOS: Prüfung und Verbesserungen

Stand: 23. September 2026. Lokale Änderungen; kein Release veröffentlicht und keine installierte App ersetzt.

## Ergebnis der Produktprüfung

Meister hat einen sinnvollen Kern als lokales Diagnose- und Aktionszentrum. Erfasst wurden **87 registrierte Module: 50 native Ansichten und 37 CLI-Einstiege**. Die größte Schwäche war die Zuverlässigkeit gemeinsamer Grundlagen und mehrerer Aktionsabläufe, nicht ein Mangel an Menüeinträgen.

Das ist eine technische Bewertung des Repositorys, keine abgeschlossene Marktvalidierung. Inventarisierung und erfolgreicher Build bedeuten nicht, dass alle 87 Module mit realen Benutzerdateien ausgeführt wurden.

## Umgesetzte Korrekturen

| Bereich | Vorher | Jetzt |
|---|---|---|
| Native Befehle | Dutzende separate Process-/Pipe-Helfer; Warten vor dem Lesen konnte bei großen Ausgaben blockieren | Gemeinsamer CommandRunner, laufendes Lesen, Zeitlimit, begrenzter Speicher, stabiler PATH und Locale, kein geerbtes Terminal-stdin |
| Health Score | Cache-Menge, Snapshot-Anzahl und fehlendes Backup-Ziel verursachten Abzüge | Kernschutzfunktionen, verfügbarer Platz des Datenvolumes, Alter bereits eingerichteter Backups; unbekannte Messwerte ausgeschlossen und als Teilbewertung ausgewiesen |
| Empfehlungen | Alarm wegen fehlendem Backup; Snapshot-Anzahl als Speicherproblem | Priorisierte, anklickbare nächste Schritte aus konkreten Sicherheits-/Speicher-/Backup-Befunden |
| Dashboard | Doppelte Scans; wirkungslose Spalten-Spans im LazyVGrid | Gemeinsame Beobachtung für Score und Empfehlungen; adaptive Kacheln; Messzeit sichtbar |
| Laufende Health-Anzeige | Wiederholte rekursive Cache-/Quarantäne-Scans | Score-Abfrage ohne Cleanup-/Snapshot-Details; nur Kern-Sicherheitschecks |
| Sicherheit | Unlesbare Befehlsausgabe wurde als deaktivierter Schutz gewertet; unbekanntes XProtect erschien grün | Unbekannt als eigener Zustand; Quarantäne-Markierung allein ist kein Defekt |
| Modulsuche | Englische Titel und Gruppen, potenziell negativer Auswahlindex | IDs und CLI-Befehle suchbar, deutsche Aufgabenbegriffe, Mehrwortsuche, stabile Sortierung und Leerzustand |
| Navigation | View-State konnte beim Wechsel ähnlicher Zielansichten weiterleben | Zielansicht an Modul-ID gebunden |
| System Cleanup | Cache-Kategorien überlappten; Papierkorb war „safe default“ | Überschneidende Unterkategorien abgegrenzt; Papierkorb explizit abzuwählen entfällt, er ist standardmäßig ausgeschlossen |
| Quick Clean / Alles erledigen | Automatisches Leeren konnte gerade recycelte Dateien endgültig entfernen | Papierkorb bleibt erhalten; AppleDouble-Ressourcen nicht mehr automatisch ausgewählt |
| Cleanup-Journal | Erst am Ende gespeichert; Dateinamen konnten kollidieren | Schreibprobe vor Beginn, eindeutige Journal-ID, Fortschritt nach Aktionen, exakter Papierkorbpfad aus NSWorkspace |
| Undo | Papierkorbziel anhand des Originalnamens geraten | Exakter protokollierter Zielpfad; alte Journale ohne Zuordnung werden nicht automatisch wiederhergestellt |
| Teilfehler | Manche Bereinigungen meldeten trotz Einzelfehlern Erfolg | System-/Quick-Clean und Uninstaller zeigen Einzelfehler an; Auto-Clean markiert fehlgeschlagene Phasen |
| Firefox | Verlaufspfad zeigte auf places.sqlite inklusive Lesezeichen | Gemeinsame Datenbank nicht mehr zum Recyceln angeboten; Hinweis auf browserinterne Verlaufsbereinigung |
| Duplikate | Überlappende Scan-Wurzeln erzeugten falsche Duplikate; Lesefehler konnten Hashes liefern | Wurzelergebnisse dedupliziert, Lesefehler ausgeschlossen, begrenzte parallele Hash-Arbeit; erneute Hash-Prüfung vor dem Verschieben |
| Uninstaller | Veraltetes Scanergebnis konnte einer anderen Auswahl zugeordnet werden; Datenreste trotz fehlgeschlagenem App-Verschieben entfernt | Auswahl abgeglichen; laufende Apps geschützt; kein Entfernen von Resten nach fehlgeschlagenem Bundle-Schritt |
| Bloatware | Manche Schutzprogramme als pauschale Entfernen-Kandidaten | Bestehende Schutzdienste und cpu-/sim-guard/HUD geschützt; KEEP-Regel auch im Cleaner geprüft |
| Kopierbare Befehle | Pfade/Labels nur mit Leerzeichen- oder Doppelquote-Escaping | Shell-Argumente robust einzeln zitiert, einschließlich Apostrophen und Substitutionen |
| Netzwerkverbindungen | Protokoll und TCP-Zustand aus falschen lsof-Feldern abgeleitet | P-/TST-Felder und Dateideskriptor-Grenzen ausgewertet |
| WLAN | Dienstname „Wi-Fi“ statt Hardwaregerät verwendet | Gerät über Hardwareports erkannt; Fehlertexte nicht als SSID-Liste interpretiert |
| Docker | Fehlender erster Binarypfad konnte Fallback verhindern; unlesbare Antwort wurde leere Nutzung | Binary vorher gewählt, Exit-Code und parsebare Antwort geprüft |
| Prozessmanager | Ungültige PID hätte Prozessgruppe adressieren können | PID 0, negative PIDs, PID 1, eigener Prozess und unzulässige Signale abgewiesen |
| Time Machine | Thermischer Zustand als Netzstromindikator verwendet; Snapshot direkt löschbar | Stromversorgung über IOKit; irreversible Snapshot-Löschung bestätigt |
| Metadaten | AppleDouble-Dateien als Müll bezeichnet; Entfernen ohne Bestätigung | Ressourcen-/Schutzbedeutung erklärt; separate Bestätigung |
| Speicherprognose | Vergangene Cleanup-Bytes als künftiges Wachstum interpretiert | Lokale Speicherstand-Messreihe, Datenvolume, Mindestspanne von 7 Tagen und 3 Beobachtungen |
| Autopilot | Versprach automatische Reinigung; launchctl-Fehler ignoriert | Ehrlich als Erinnerung beschrieben; geladenen Dienst prüfen; Fehler beim Aktivieren/Deaktivieren sichtbar |
| Slack | URL mit Zugangsdaten in UserDefaults, frei sichtbares Feld, HTTP erlaubt | Login-Schlüsselbund mit Migration beim Öffnen; SecureField; validierte Slack-HTTPS-URLs, keine Redirects, Versandzeitlimit |
| Aktualisieren | Mehrfach gestartete Reloads konnten sich überlappen | Zusätzliche Sperren während laufender Aktualisierungen |

Die Snapshot-Korrektur entspricht Apples Beschreibung: lokale Snapshots werden bei Bedarf freigegeben; ihre Anzahl allein belegt keinen Speicherengpass. [Apple: lokale Time-Machine-Snapshots](https://support.apple.com/en-ie/102154).

## Verifikation

Umgebung: Xcode 27.2, lokales arm64-macOS, Deployment Target macOS 14.0.

- Design-Paket-Voraussetzung lokal erfüllt (`scripts/ensure-design-system.sh`).
- Xcode-Projekt erfolgreich neu generiert.
- **Release-Build erfolgreich.** Lokales App-Artefakt: `build/smart-macos/Meister.app`, Build 39. Für lokale Nutzung ad hoc signiert; `codesign --verify --deep --strict` erfolgreich. Keine Developer-ID-Veröffentlichung oder Notarisierung.
- **90 macOS-XCTest-Tests erfolgreich, 0 Fehler.**
- **1 MeisterKit-XCTest erfolgreich, 0 Fehler**, einschließlich Ausgabe größer als ein Pipe-Puffer.
- Regressionstests u. a. für fehlende Backup-Ziele, unbekannte Sicherheitswerte, Speicherknappheit, Snapshot-Anzahl, deutsche Suche, Forecast-Mindestdaten, große Prozessausgaben, Timeout, Shell-Quoting, Webhook-Validierung, Dienstschutz, Cache-Überschneidung, WLAN, lsof, ungültige Prozessziele und Duplikat-Sicherheit.
- `git diff --check` und Shell-Syntaxprüfung des neuen lokalen Prüfscripts erfolgreich.
- Wiederholbarer lokaler Einstieg: `bash scripts/check-macos.sh`.

Der vorhandene Avast-Test erwartete zuvor eine P0-Entfernungsempfehlung. Er prüft jetzt ausdrücklich den Erhalt bestehender Sicherheitssoftware, entsprechend der gespeicherten Wartungsregel. Die CleanMyMac-/CCleaner-Assertions bleiben bestehen.

Xcode meldet weiterhin systemseitige App-Intents-Metadaten-/linkd-Hinweise, weil derzeit keine App Intents integriert sind. Das ist kein fehlgeschlagener App-Test. App Intents stehen auf der Roadmap.

## Grenzen und offene Arbeit

- Keine reale Bereinigung persönlicher Dateien, kein Papierkorb-Leeren, kein Uninstall, kein Beenden fremder Prozesse, keine Änderungen an LaunchAgents, keine Slack-Nachricht während dieser Prüfung.
- Keine manuelle vollständige UI-/VoiceOver-/Accessibility-Abnahme und kein Test aller unterstützten macOS-Versionen.
- Keychain-Migration ist implementiert, aber wurde nicht mit den persönlichen Slack-Zugangsdaten ausgeführt.
- Rücknahme aus alten Journals ohne exakten Papierkorbpfad erfolgt über Finder; alte Dateinamen werden aus Sicherheitsgründen nicht geraten.
- Native Listen-Reader verwenden noch nicht überall dasselbe strukturierte Fehler-/Berechtigungsmodell. Ein leeres Ergebnis muss in weiteren Modulen von einem nicht ermittelbaren Ergebnis unterschieden werden.
- CommandRunner begrenzt native Einzelprozesse; vollständige Kindprozess-/Prozessgruppen-Abbruchsteuerung und die gesonderte CLI-Pipeline bleiben ein eigenes Arbeitspaket.
- Journale sind verbessert, aber noch keine vollständige Crash-Transaktion mit Wiederaufnahme über alle Cleaner.
- Browser-Lebenszyklus, profilübergreifende Datenbanken, einheitliches Restore aller Module, APFS-Klone/Hardlinks und messbare tatsächliche Speicherfreigabe brauchen zusätzliche Arbeit.
- Die lokale MeradOSDesign4-Geschwisterabhängigkeit bleibt bestehen. Die vorhandene GitHub-CI baut die App noch nicht; sie prüft README-Präsenz.
- Die bereits vor diesem Durchlauf geänderte Buildnummer `39` in `project.yml` wurde erhalten.
- Keine Veröffentlichung, kein Push und keine Ersetzung von `/Applications/Meister.app`.

Die weitere Umsetzung ist mit Abhängigkeiten und Abnahmekriterien in der [Roadmap](../ROADMAP.md) priorisiert. „Alle Funktionen vollständig live-verifiziert“ wäre mit dieser Prüftiefe keine zutreffende Aussage.
