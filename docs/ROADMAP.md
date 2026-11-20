# Meister — das Schweizer Messer für macOS

Stand: 24. September 2026. Produkt- und Integrationsroadmap, kein Versprechen bereits implementierter Funktionen.

## Entscheidung: weiterbauen, mit einem klaren Schwerpunkt

**Ja, Meister ergibt Sinn als lokales Diagnose- und Aktionszentrum für den eigenen Mac.** Der vorhandene Katalog verbindet native Werkzeuge mit dem installierten Meister-CLI. Der Mehrwert entsteht durch verständliche Befunde, passende nächste Schritte und kontrollierbare Aktionen. Die bloße Zahl der Menüeinträge ist kein Qualitätsmaßstab.

Dies ist eine technische Produktbewertung des vorhandenen Codes. Nutzerinterviews, Zahlungsbereitschaft und Marktvalidierung wurden nicht untersucht.

Das Zielbild: „Mein Mac ist langsam / voll / offline / verhält sich ungewöhnlich“ führt zu einer nachvollziehbaren Diagnose, einer Vorschau und einer überprüften Maßnahme. Für Experten bleiben einzelne Werkzeuge direkt erreichbar.

## Aktueller Stand

- Vollständiger registrierter Funktionskatalog: [Modulinventar](MODULE-INVENTORY.md).
- Änderungen und geprüfte Grenzen dieses Durchlaufs: [Prüfbericht](verification/2026-09-23-smart-macos.md).
- Native macOS-App, CLI-Anbindung, Menüleiste, Modulsuche, Cleanup, Prozesse, Netzwerk, Sicherheitsstatus und Entwicklerwerkzeuge sind vorhanden.
- Die GUI besitzt inzwischen umfangreiche eigene native Diagnose- und Bereinigungsmodule; die alte README-Matrix unterschätzt den tatsächlichen Umfang.
- „Autopilot“ ist derzeit eine tägliche Erinnerung zum Öffnen von Quick Clean. Unbeaufsichtigte Wartung ist noch nicht implementiert.
- Slack ist eine optionale, manuell auslösbare Integration; ein automatischer Bericht nach Wartung ist noch nicht verdrahtet.
- Der Health Score ist eine dokumentierte Heuristik aus Messwerten, keine vollständige Sicherheitsprüfung oder KI-Diagnose.

## Leitplanken für jede Erweiterung

1. Lokale Verarbeitung ist Standard; externe Übertragung benötigt eine klar erkennbare Aktion oder eingerichtete Zustimmung.
2. Jeder Befund enthält Quelle, Messzeit, Messwert, Unsicherheit und eine passende Aktion.
3. Fehlende Berechtigungen, fehlende Tools und leere Ergebnisse sind unterschiedliche Zustände.
4. Änderungen zeigen Vorschau, betroffene Objekte, erwartete Wirkung, Rücknahmefähigkeit und Ergebnis.
5. Kein automatisches Leeren des Papierkorbs, Entfernen von Schutzsoftware oder Zurücksetzen von Apple-Einstellungen.
6. Keine Hinweise auf nicht eingerichtete Time-Machine-Ziele. Alter nur bei eingerichtetem Ziel bewerten.
7. CLI bleibt Quelle bestehender Wartungsfunktionen. Neue GUI-Funktionen verwenden strukturierte CLI-Ausgaben oder Apple-Frameworks.
8. Tests verändern ausschließlich Fixtures; reale destruktive Abläufe werden in einer isolierten Testumgebung geprüft.
9. Fähigkeiten werden zur Laufzeit erkannt. Fehlende APIs oder Berechtigungen ergeben einen erklärten Zustand.
10. „Bearbeitete Dateigröße“, „in den Papierkorb verschoben“ und „tatsächlich zusätzlich verfügbarer Speicher“ werden getrennt erfasst.

## Phase 0 — verlässliche Grundlage (höchste Priorität)

**Fortschritt 24. September:** P0-01 ist begonnen. Gemeinsames Ergebnisformat und Anzeigen sind in Docker, Disk Health, Netzwerkverbindungen, WLAN, Simulatoren, macOS-Updates, App-Berechtigungen, Keychain Audit und Brew Doctor integriert. Zusätzlich sind jetzt Prozessliste, Energieverbrauch, VPN-Tunnel-Erkennung und Bluetooth migriert. Fehlende Tools, verweigerte Zugriffe, Timeouts, unerwartete Antworten und Teilergebnisse werden unterschieden. Die Migration der übrigen Reader ist weiterhin offen; P0-01 ist noch nicht abgeschlossen. [Prüfbericht](verification/2026-09-24-diagnostic-results.md).

**CLI-Fortschritt 24. September:** Live-Ausgabe, Abbrechen, Zeitlimits und Ausgabegrenzen sind im gemeinsamen Shell-Runner integriert. Eigene Prozessgruppen erlauben das Beenden normaler Kindprozesse; die native Diagnoseausführung nutzt denselben Runner. 10 Pakettests decken unter anderem Abbruch, ignoriertes SIGTERM, einen bereits beendeten Elternprozess, große Ausgaben und Eingaben ab. Offen bleiben die manuelle UI-Abnahme und der CLI-Vertrag für Programme, die sich absichtlich in eine andere Sitzung/Prozessgruppe lösen. [Prüfbericht](verification/2026-09-24-cli-lifecycle.md).

**In diesem Durchlauf umgesetzt:** zentrale native Prozessausführung; verbesserter Health Score und Empfehlungen; weniger redundante Scans; deutsche Suchbegriffe; Cache-Abgrenzung; Erhalt des Papierkorbs; echte Papierkorbpfade im Cleanup-Protokoll; Schutz der Firefox-Lesezeichen; Schlüsselbund für Slack; native Parserkorrekturen. Details im Prüfbericht.

**Noch zu erledigen, bevor unbeaufsichtigte Wartung freigegeben wird:**

| Aufgabe | Ergebnis / Abnahme | Abhängigkeit |
|---|---|---|
| Einheitliches Ergebnisformat für alle Reader | Erfolg, leer, fehlendes Tool, fehlende Berechtigung, Teilfehler, Timeout jeweils im UI unterscheidbar; Fixtures pro Zustand | Gemeinsame Prozessausführung |
| CLI-Prozesssteuerung | Live-Ausgabe, Abbrechen und Timeouts einschließlich Kindprozessen; kein verwaister Wartungsprozess | MeisterKit/Shell + CLI-Vertrag |
| Transaktionales Aktionsjournal | Crash mitten in einer Änderung bleibt rekonstruierbar; Wiederaufnahme und Rücknahme werden getestet | Einheitliche Action-IDs |
| Einheitliche Rücknahme | Cleanup, Browser, Uninstaller, Bloatware, Hosts und Metadaten erhalten exakte Zielpfade und Konfliktbehandlung | Journal |
| Browser-Lebenszyklus | Laufende Browser erkennen; Datenbanken nicht im geöffneten Zustand verschieben; Profile und WAL-Dateien berücksichtigen | App-Zustand + Journal |
| Dateisystem-Grenzen | Symlinks, Hardlinks, APFS-Klone, Cloud-Platzhalter und Rechtefehler als Fixtures; keine stillschweigenden Erfolgsmeldungen | Scan-Ergebnisformat |
| Reproduzierbare Builds | MeradOSDesign4 versioniert beziehen oder bewusst vendoren; Clean-Clone-Build ohne lokale Geschwisterverzeichnisse | Paketentscheidung |
| Echte CI | macOS-Build, Tests, Lint und Artefaktprüfung; aktuelle GitHub-CI prüft bisher nur README-Präsenz | Reproduzierbare Abhängigkeiten |
| UI-Abnahme | VoiceOver, Tastatur, 880-Pixel-Fenster, große Schrift, Light/Dark, DE/EN, leere und fehlerhafte Zustände | UI-Testziel |

**Freigabekriterium:** Keine automatische Mutation, solange Vorschau, Ergebnisprüfung, Abbruch und dokumentierte Rücknahmegrenze fehlen.

## Phase 1 — aus Werkzeugen wird ein zusammenhängendes Produkt

| Integration | Konkreter Nutzen | Abnahme |
|---|---|---|
| Gemeinsame Modulregistrierung | Titel, Suche, Voraussetzungen, Risiko, Zielansicht und Aktionen an einer Stelle | Kein natives Modul fällt unbemerkt in die CLI-Ansicht zurück |
| Favoriten und zuletzt genutzte Werkzeuge | Häufige Aufgaben mit zwei Tastendrücken | Persistenz, zurücksetzbare Historie, vollständige Tastaturbedienung |
| Problembasierter Einstieg | „Langsam“, „Speicher voll“, „Internet kaputt“, „Akku leer“, „App startet nicht“ | Jeder Ablauf liefert Belege und explizite nächste Schritte |
| Diagnoseverlauf und Vergleiche | Änderungen seit gestern / seit Update erkennen | Zeitstempel, Rechner-/OS-Kontext, Aufbewahrungsgrenze |
| Lokaler Supportbericht | Reproduzierbare Hilfe ohne manuelles Kopieren aus zehn Ansichten | Vorschau und Schwärzung von Nutzernamen, Pfaden, SSIDs, IPs und Tokens |
| Globale Auftragsübersicht | Laufende Scans, Warteschlange, Abbruch und Ergebnis | Keine konkurrierenden Bereinigungen derselben Dateien |
| Menüleistenstatus | Nur relevante Veränderungen anzeigen | Keine vollständigen Dateisystemscans alle paar Sekunden |

**Freigabekriterium:** Fünf typische Probleme lassen sich vom Dashboard bis zum verifizierten Ergebnis ohne Terminal lösen; privilegierte Schritte dürfen noch als korrekt zitierte Befehle vorbereitet werden.

## Phase 2 — Speicher, Apps und Entwickleralltag

| Integration | Umfang | Besondere Grenze |
|---|---|---|
| Speicheranalyse 2.0 | Treemap, größte Ordner, Eigentümer-App, Änderungsverlauf | APFS-Freigabe und logische Größe getrennt |
| Duplikate 2.0 | Größenfilter → Teilhash → Vollhash, Gruppenvergleich, Original schützen | Keine automatische Löschung; Hardlinks/Klone unterscheiden |
| Uninstaller 2.0 | App schließen, Bundle-ID-Zuordnung, gemeinsam genutzte Container erklären | Keine fremden App-Daten allein aufgrund ähnlicher Namen entfernen |
| Download-Assistent | Alte DMGs/ZIPs/Installer, Duplikate, große Downloads | Benutzerdateien nur nach Auswahl |
| Homebrew-Zentrale | Formulae/Casks, veraltet, Abhängigkeiten, Pinning, Doctor, geplante Updates | Keine pauschalen Upgrades laufender Dienste |
| Xcode-/Simulator-Zentrale | Xcode-Versionen, Runtime-Größen, DerivedData pro Projekt, unbenutzte Simulatoren | Archives erhalten; aktive Builds und Simulatoren erkennen |
| Container-Zentrale | Docker, optional Colima/OrbStack: Images, Container, Volumes, Build-Cache | Volumes separat bestätigen; Vorschau pro Objekt |
| Entwicklungsumgebungen | Node/Python/Ruby/Java-Versionen, doppelte Toolchains, PATH-Konflikte | Erkennen vor Verändern; keine Shell-Konfiguration blind überschreiben |
| Git-Arbeitsplatz | Große Repositories, Worktrees, Build-Artefakte, Git-LFS-Größe | Uncommitted Work, Stashes und lokale Branches schützen |
| Zertifikate/SSH | Ablauf, Fingerprints, Rechte, Agent-Status | Private Schlüssel und Passphrasen nie in Berichte |

## Phase 3 — Netzwerk, Hardware und Systemzustand

| Integration | Umfang | Abnahme |
|---|---|---|
| Netzwerkdiagnose als Ablauf | Interface → Gateway → DNS → TLS → Zielhost | Konkrete Fehlerstelle statt allgemeinem „offline“ |
| WLAN-Assistent | Signal-/Verbindungsdaten soweit erlaubt, Roaming-/DNS-Verlauf, bekannte Netze | Fehlende Berechtigungen und OS-Limits sichtbar |
| Port- und Verbindungsinspektor | Prozess → Socket → Remote-Ziel, TCP/UDP, IPv4/IPv6 | Kein aus Adressen erfundener Sicherheitsstatus |
| DNS-/Hosts-Profile | Vorschau, Konfliktprüfung, atomare Änderung, Rücknahme | Validierung + berechtigter Helper |
| VPN-/Proxy-Diagnose | Routen, DNS, Split-Tunnel-Hinweise, Systemeinstellungen | Keine automatische Abschaltung von Schutzdiensten |
| Akku und Energie | Zustand, Ladeverlauf, Prozessverbrauch, Schlaf-Assertions | Langzeittrends statt Momentaufnahme als Ursache auszugeben |
| Speicher- und CPU-Trends | Memory Pressure, Swap, CPU, thermischer Zustand | Kein „RAM-Booster“-Versprechen |
| Externe Geräte | USB/Thunderbolt/Bluetooth, Verbindungshistorie, Datenträger | SMART nur ausgeben, wenn tatsächlich verfügbar |
| Crash-/Hang-Triage | Wiederkehrende Signaturen, App-/OS-Version, zeitliche Korrelation | Absturzberichte lokal; Export redigiert |
| Systemupdate-Assistent | Verfügbarkeit, Voraussetzungen, Neustartplanung, Verlauf | Nutzer steuert Installation und Neustart |

## Phase 4 — Automatisierung mit begrenzten Rechten

- App Intents für Diagnose starten, Modul öffnen und Bericht vorbereiten; gleiche Aktionen wie in der Oberfläche.
- Zeitpläne mit Ruhezeiten, Netzstrom-/Akkubedingung, Laufzeitlimit und verständlichen Ergebnissen.
- Zunächst ausschließlich Diagnosen planen. Änderungen später einzeln freischalten und erlaubte Objekte begrenzen.
- Privilegierten Helper mit eng definierten Operationen untersuchen: DNS-Responder, Hosts, ausgewählte `launchctl`-/`xcode-select`-Aktionen. Keine allgemeine Root-Shell.
- ServiceManagement/SMAppService zur Registrierung und Statusanzeige prüfen. Benutzerzustimmung und OS-Verfügbarkeit gehören in den Ablauf.
- Benachrichtigungen bei neuen relevanten Befunden; deduplizieren, pausieren und pro Regel deaktivieren.
- Shortcuts, AppleScript und dokumentierte URL-Navigation; `meister://run/...` darf nicht ungefragt zerstörerische Aktionen ausführen.
- Optionaler Bericht an eingerichtete Ziele erst nach lokaler Vorschau und definierter Datenfreigabe.

Apple beschreibt App Intents als strukturierte Integration von App-Aktionen mit Systemfunktionen. SMAppService ist die vorgesehene API-Familie für registrierte Dienste; die konkrete Helper-Architektur braucht einen eigenen Prototyp. [App Intents](https://developer.apple.com/documentation/appintents), [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice).

**Freigabekriterium:** Jede Automatisierung besitzt Umfang, Trigger, letzte Ausführung, verifiziertes Ergebnis, Abschaltmöglichkeit und getestete Fehlerbehandlung.

## Phase 5 — smarter Assistent auf belegten Daten

| Funktion | Umsetzung | Abnahme |
|---|---|---|
| Natürliche Sprache | „Warum ist mein Mac langsam?“ wird auf freigegebene Diagnoseabläufe abgebildet | Kein frei erfundener Shell-Befehl |
| Befunde erklären | Lokale Zusammenfassung mit Quelle, Zeit und Unsicherheit | Aussagen auf vorhandene Messwerte zurückführbar |
| Ursachen vergleichen | Vorher/Nachher, Update-/App-/Konfigurationsänderungen korrelieren | Korrelation wird nicht als bewiesene Ursache dargestellt |
| Personalisierte Empfehlungen | Ignorierte Befunde und bevorzugte Werkzeuge lokal merken | Einsicht, Rücksetzen und Abschalten möglich |
| Reparaturwissen | Nur erfolgreich verifizierte Maßnahmen mit OS-/Tool-Kontext speichern | Kein Lernstatus allein wegen Exit 0 oder bestandenem Mock-Test |
| Optionale Modelle | Foundation Models bei verfügbarer Unterstützung; regelbasierter Fallback; externe Modelle separat aktivieren | Vollständige Kernfunktion ohne Modell/Account |

Apple verlangt eine Verfügbarkeitsprüfung für die Nutzung des lokalen Foundation-Models-Modells auf unterstützten Geräten. Das ist eine optionale Erweiterung, keine neue Mindestvoraussetzung für Meister. [Apple: Foundation Models](https://developer.apple.com/videos/play/wwdc2025/286/).

## Phase 6 — zusätzliche Werkzeuge als optionale Module

| Paket | Denkbare Integrationen | Priorität |
|---|---|---|
| Dateiwerkzeuge | Batch-Umbenennen mit Vorschau, Prüfsummen, Archive testen, sichere Metadateninspektion, Finder-Schnellaktionen | Hoch nach Phase 2 |
| Arbeitsumgebung | Temporär wach halten, Bildschirm-/Audio-Geräteübersicht, Displayprofile, Fokus-Startabläufe | Mittel |
| Apple Mail / Kalender | Lokale Diagnose und Export, Regel-/Sync-Status soweit öffentliche APIs reichen | Mittel; Standard-Apps bleiben Apple Mail und iCal |
| Kontakte | Duplikatvorschau, Feldervergleich, vCard-Sicherung, Zusammenführung | Hoch bei Bedarf, geteilter MeisterKit-Kern |
| Fotos/Medien | Metadaten, große Videos, ähnliche Fotos, Export | Eigenständiges Modul; keine automatische Mediathekbereinigung |
| Backup-Werkzeuge | Eingerichtete Ziele, Wiederherstellbarkeit, verifizierte Test-Restores | Hoch; keine Aufforderung wegen fehlender Ziele |
| Netzwerk-Experten | DNS-Abfragen, TLS-Kette, HTTP-Prüfung, lokale Erreichbarkeitstests | Hoch |
| Mehrere Macs | Nur lesender Bericht, Vergleich von Inventar/Versionen; SSH explizit einrichten | Später |
| Endpoint-Security | Prozess-/Dateiereignisse als Expertenmodul | Später; Apple-Entitlement erforderlich |
| Erweiterungsschnittstelle | Signierte deklarative Module mit Berechtigungen und festem Ergebnisformat | Erst nach stabiler Modul-API |

Endpoint Security benötigt ein eigenes Entitlement; es ist keine einfache zusätzliche Ansicht und gehört nicht in die erste Ausbaustufe. [Apple: Endpoint Security](https://developer.apple.com/documentation/endpointsecurity).

Zwischenablage-Historie, Fensterverwaltung und ein eigener Passwortmanager sind vorerst zurückgestellt: hoher zusätzlicher Datenschutz-/Berechtigungsumfang bei geringem Beitrag zur Kernaufgabe Diagnose und Wartung. Kleine, klar abgegrenzte Hilfswerkzeuge können später ergänzt werden.

## Empfohlene Reihenfolge der nächsten Arbeitspakete

1. **P0-01:** Strukturierte Reader-Ergebnisse + überall sichtbare Teilfehler.
2. **P0-02:** CLI-Cancel/Streaming + Kindprozess-Tests.
3. **P0-03:** Einheitliches Aktionsjournal und Rücknahme inklusive Browser-/Uninstaller-Aktionen.
4. **P0-04:** Reproduzierbare Paketabhängigkeiten und echte macOS-CI.
5. **P1-01:** Favoriten, Problemsuche und fünf geführte Diagnoseabläufe.
6. **P1-02:** Diagnosehistorie, Vergleich und redigierter Supportbericht.
7. **P2-01:** Speicher-/App-/Homebrew-Zentrale.
8. **P3-01:** Netzwerkablauf und Energie-/Crash-Triage.
9. **P4-01:** App Intents und ausschließlich lesende Zeitpläne.
10. **P5-01:** Optionaler erklärender Assistent auf dem stabilen Diagnosemodell.

Keine festen Termine, bevor Abhängigkeiten und Abnahmetests des jeweiligen Pakets geklärt sind. Jede Phase soll einzeln nutzbar und freigabefähig sein.

## Erfolg messen

- Zeit bis zur ersten belastbaren Diagnose und bis zum verifizierten Ergebnis.
- Anteil fälschlich positiver Warnungen und unbegründeter Empfehlungen.
- Anteil der Aktionen mit vollständigem Journal und erfolgreichem Wiederherstellungstest.
- CPU/RAM/I/O der App bei Leerlauf und Diagnose, gemessen auf realen Testgeräten.
- Kernabläufe vollständig per Tastatur und VoiceOver bedienbar.
- Keine ungefragte externe Datenübertragung und keine automatische irreversible Bereinigung.
