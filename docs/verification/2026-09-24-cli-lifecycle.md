# CLI-Lebenszyklus – 24. September 2026

## Implementiert

- `Shell` startet absolute Programmdateien mit `posix_spawn` in einer eigenen Prozessgruppe. Argumente werden ohne zusätzliche Shell ausgewertet. Nicht benötigte Dateideskriptoren werden geschlossen.
- Nicht blockierende stdin/stdout/stderr-Pipes verhindern gegenseitige Blockaden bei großen Ein- und Ausgaben. Ohne Eingabe wird stdin geschlossen.
- Standardzeitlimit: 300 Sekunden für CLI-Aufrufe, 60 Sekunden für native Diagnosen. Ausgabegrenze: 16 MiB pro Ausgabekanal. Zeitlimits und Überschreitungen liefern Fehler statt vermeintlich vollständiger Ergebnisse.
- Abbruch und Fehler senden SIGTERM an die eigene Gruppe, nach 250 ms SIGKILL. Auch ein bereits beendeter Elternprozess mit weiterlaufenden Kindern wird behandelt. Kinder, die absichtlich eine neue Sitzung oder Prozessgruppe erstellen, sind außerhalb dieser Grenze; offen gehaltene Pipes blockieren die Rückgabe nach beendetem Elternprozess höchstens eine weitere Sekunde.
- Live-Ausgabe erscheint höchstens alle 100 ms plus Abschlussausgabe. Die CLI-Ansicht besitzt einen Abbrechen-Knopf und bricht beim Verlassen ab. Bereits vorgenommene Änderungen werden nicht zurückgerollt.
- Native Diagnosen verwenden denselben Runner. Exit-Codes und Signalabbrüche bleiben unterscheidbar.

## Verifikation

10 MeisterKit-Tests und 123 macOS-XCTest-Tests bestanden. Enthalten sind große Unicode-Eingabe, große stdout-/stderr-Ausgaben, geschlossene Eingabe, ungültige Aufrufe, fehlendes Programm, Abbruch vor Start, Live-Ausgabe, Abbruch mit Kindprozess, Zeitlimit mit ignoriertem SIGTERM und bereits beendetem Elternprozess sowie Ausgabegrenze. Nur synthetische Prozesse und temporäre Markerdateien; keine Wartungsaktionen ausgeführt.

Release-Build und Ad-hoc-Signatur geprüft. Artefakt: `build/cli-lifecycle-20260924/Meister.app`. Laufende App unverändert. Manuelle UI-Abnahme und Tests mit allen externen Meister-CLI-Modulen stehen aus.

## Screenshot aus AufRaum

Der eingereichte Screenshot zeigt AufRaum/Megasmart. Dessen vorhandener Quellstand enthält bereits eine deutsche Timeout-Erklärung und lokale Indexsuche. 53 vorhandene Megasmart-Backend-Tests und 5 Swift-Client-/Modelltests bestanden bei erneuter Ausführung; der aktuelle AufRaum-Debug-Build kompiliert. Der Screenshot allein belegt weder die aktuell gestartete Binärversion noch eine behobene Apple-Mail-Laufzeitstörung. Keine Mail-Nachrichten verschoben und keine Automatik gestartet.
