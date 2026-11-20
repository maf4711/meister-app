# Einheitliche Diagnoseergebnisse — 24. September 2026

P0-01 aus der Roadmap: gemeinsames Ergebnisformat und Integration in neun native Module. Die übrigen Reader folgen; der gesamte Roadmap-Punkt ist noch nicht abgeschlossen.

## Gemeinsame Grundlage

`DiagnosticReport<Value>` unterscheidet einen erfolgreich ermittelten Wert (auch eine leere Liste) von fehlenden Messwerten und Teilergebnissen. Berichte tragen einen Zeitpunkt und strukturierte Hinweise. `DiagnosticIssuesView` zeigt Hinweise und die letzte Abfrage an, ohne rohe Befehlsausgaben oder mögliche Zugangsdaten einzublenden.

`CommandRunner.Result` bewahrt die Ursache: fehlendes ausführbares Werkzeug, fehlende Rechte, Zeitlimit, Signalabbruch, Ausgabegrenze oder sonstiger Fehler. Timeout und Signalabbruch werden nicht mehr zusammengefasst. Die Abfrageausgabe wird weiterhin begrenzt; die bekannte Grenze bei separat weiterlebenden Kindprozessen bleibt ein eigenes Roadmap-Paket.

## Umgestellte Module

| Modul | Geändertes Verhalten |
|---|---|
| Docker Cleanup | Gestoppter Daemon ist kein Installationsfehler. Fremdes oder unvollständiges JSON und ungültige Messwerte werden erkannt. Teilwerte bleiben sichtbar; Prune bleibt bei unvollständiger Diagnose gesperrt. Keine frei erfundene freigegebene Datenmenge aus dem Vorher-Wert. Erneutes Laden ist auch nach Fehlern möglich. |
| Disk Health | Fehler beim Auflisten oder Auslesen einzelner Disks werden sichtbar; lesbare Disks bleiben erhalten. Fehlgeschlagene Antworten ergeben keine gesunden Nullwerte. |
| Netzwerkverbindungen | Keine Treffer (`lsof` Exit 1 ohne Ausgabe) und fehlender Zugriff unterscheiden sich. Lesbare Teilbefunde bleiben mit Hinweis sichtbar. |
| WLAN | Hardwareabfrage, fehlende WLAN-Hardware, gespeicherte Netze und Zugriffsfehler werden getrennt behandelt. Bereits eingeblendete Passwörter werden beim Neuladen aus dem Modell entfernt. |
| Simulator Manager | Leere Geräteliste ist von fehlgeschlagenem `simctl`, unlesbarem JSON und fehlerhaften Einträgen unterscheidbar. |
| macOS-Updates | Ein Abfragefehler bedeutet nicht mehr „System aktuell“. Leere Ergebnisse werden nur bei expliziter „No new software available“-Antwort akzeptiert. Ein abschließendes Update-Label bleibt erhalten. |
| App-Berechtigungen | SQLite wird ausdrücklich read-only geöffnet. Erfolgreich gelesene leere Tabellen lösen keinen FDA-Hinweis und keinen dauerhaften Spinner aus. Ein allgemeiner Datenbank-Öffnungsfehler beweist keine fehlende Berechtigung. Geprüft wird die Benutzer-TCC-Datenbank, nicht eine vollständige systemweite Berechtigungsinventur. |
| Keychain Audit | Fehlgeschlagene Metadatenabfragen werden nicht mehr als Schlüsselbund mit null Einträgen gezählt. Teilergebnisse bleiben sichtbar. Unbekannte Dateigrößen werden nicht als null angezeigt. |
| Brew Doctor | Gewöhnliche Doctor-Warnungen mit Exit 1 bleiben gültige Befunde. Echte Ausführungsfehler, fehlendes Homebrew und Fehler bei `outdated` werden getrennt ausgewiesen. Unvollständige Abfragen erhalten kein „healthy“-Urteil. |

Die vollständige Umstellung umfasst Reader, Modelle und sichtbare Zustände der neun Ansichten. Nach fehlgeschlagenem Neuladen werden alte Messwerte dort nicht als neues Ergebnis übernommen. Während einer erneuten Abfrage können vorhandene Werte mit ihrem bisherigen Abfragezeitpunkt sichtbar bleiben.

## Tests

**115 macOS-XCTest-Tests erfolgreich, 0 Fehler** (vor diesem Durchlauf: 90).

Release-Build erfolgreich. Lokales Artefakt: `build/diagnostics-20260924/Meister.app`. Ad hoc signiert und mit `codesign --verify --deep --strict` erfolgreich geprüft. `git diff --check` ist ebenfalls sauber.

Die 25 ergänzten Regressionstests verwenden eingespeiste Befehlsantworten und temporäre bzw. synthetische Daten. Sie prüfen insbesondere:

- Fehlendes Tool, verweigerten Zugriff, echten Prozess-Timeout und Ausgabegrenze.
- Vollständige, leere, fehlerhafte und teilweise lesbare Berichte.
- Docker-Daemonfehler, fremdes JSON, ungültige Zahlen und das Entfernen alter Messwerte nach einem Fehler.
- Leere Socket-Auswahl versus Rechtefehler sowie partielle Netzwerkbefunde.
- Updatefehler versus explizit aktuellen Stand.
- Leere Simulatorliste versus beschädigtes Antwortformat.
- Fehlende WLAN-Hardware versus nicht lesbare Netzwerkliste.
- Teilweise nicht lesbare Datenträger.
- Read-only-TCC-Zugriff, leere Tabellen und Schemafehler.
- Nicht lesbare Schlüsselbund-Metadaten.
- Homebrew-Exit-1-Warnungen, echte Doctor-Fehler und fehlgeschlagene Paketabfragen.

Keine Bereinigung, kein Simulator-Reset, keine Änderungen an Zugriffsrechten, keine Schlüsselbund-Dumps persönlicher Daten und keine externen Nachrichten wurden zur Verifikation ausgeführt. Dies ist eine Build-/Regressionstest-Verifikation; die manuelle vollständige UI-Abnahme bleibt offen.

## Noch offen

- Weitere Reader (u. a. Hardwareinventar, Bluetooth, VPN, Login Items, Energie, Spotlight, Prozessliste und Dateisystemscanner) auf das Format umstellen.
- Einige Parser verwenden textuelle Tool-Ausgaben; Formatänderungen sollen schrittweise durch strukturierte Ausgaben und zusätzliche Fixtures abgesichert werden.
- Fehlerklassifikation für Rechte basiert bei fehlendem spezifischen Exit-Code auf bekannten Meldungen; sie ersetzt keine umfassende Berechtigungsprüfung.
- Echte Prozessgruppen-Abbruchsteuerung, CLI-Streaming und vereinheitlichtes Aktionsjournal folgen laut Roadmap.
- Installierte App und bestehende Buildnummer 39 bleiben unverändert; keine Veröffentlichung oder Notarisierung.
