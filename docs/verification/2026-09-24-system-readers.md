# Systemdiagnosen – 24. September 2026

Prozessliste, Energieverbrauch, VPN-Tunnel-Erkennung und Bluetooth verwenden jetzt `DiagnosticReport` mit Fehlerarten und Abfragezeitpunkt. Zusammen mit den vorherigen neun Modulen sind damit 13 Reader migriert; die vollständige Migration bleibt offen.

## Änderungen

- Prozessliste: Befehlsfehler werden sichtbar. Bei fehlenden Prozessargumenten bleiben gemessene Prozesse mit Teilfehler erhalten. Nicht endliche oder negative Kennzahlen und RSS-Werte mit Multiplikationsüberlauf werden verworfen.
- Energie: Fehlgeschlagene und nicht auswertbare Antworten werden angezeigt. Ungültige Kennzahlen werden verworfen. Ein verwalteter Aktualisierungstask ersetzt den Timer; parallele Abfragen werden verhindert und abgebrochene Ergebnisse nicht übernommen.
- VPN: Tunnel werden auch hinter dem ersten Interface erkannt. Die Oberfläche verspricht keinen VPN-Schutz aufgrund eines Interface-Namens. DNS-Adressen sind dedupliziert; Fehler erscheinen statt einer scheinbar erfolgreichen Leeranzeige.
- Bluetooth: Befehls-, JSON- und Gerätegruppenfehler werden unterschieden. Geräte ohne Adresse erhalten einen Namen als Ersatz-ID. Batteriewerte außerhalb 0–100 werden nicht angezeigt. Gleichnamige Geräte ohne Adresse sind damit weiterhin nicht unterscheidbar.

## Prüfung

123 macOS-XCTest-Tests bestanden, darunter acht neue Tests für die vier Reader. Die neuen Tests verwenden synthetische Antworten und führen keine Systemänderungen aus. Release-Build und lokale Ad-hoc-Signatur geprüft. Artefakt: `build/system-readers-20260924/Meister.app`. `git diff --check` ohne Befund.

Die laufende App wurde nicht neu gestartet oder ersetzt. Kein manueller UI-Abnahmetest dieses Builds erfolgt.

## Weiter offen

`MeisterKit/Shell.swift` besitzt weiterhin keine Abbruchsteuerung, Ausgabegrenze oder Live-Ausgabe. Der native CommandRunner begrenzt Laufzeit und Ausgabe, beendet aber keine vollständige Kindprozessgruppe; ein Kindprozess kann eine Pipe offen halten. P0-02 bleibt deshalb offen. Auch die Reader-Aktualisierungstasks können eine bereits laufende synchrone Betriebssystemabfrage noch nicht abbrechen.
