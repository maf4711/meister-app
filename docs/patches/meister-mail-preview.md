# Meister Mail Preview: Status und FM-Bündelung

## Stand

Am 26.09.2026 lokal in der Homebrew-Installation der CLI-Version 6.34 installiert und geprüft. Wirksam beim nächsten Meister-Aufruf. Ein Homebrew-Upgrade kann den lokalen Fix ersetzen. Die Ausgabe stammt aus `/opt/homebrew/Cellar/meister/6.34/libexec/scripts/megasmart.mjs`; das aktuelle Repository enthält die Swift-App, nicht diesen Mail-Ablauf.

Die Installation wurde für Entwicklung und Tests nach `/private/tmp/meister-preview-fix/updated` kopiert. PID 9124 wurde als Statusleisten-Daemon identifiziert und nicht verändert.

Installation mit `node scripts/install-mail-preview-fix.mjs`: Patch-Kompatibilität, Syntax und CLI-Hilfe geprüft; alle neun Tests vor und nach Installation bestanden. Die Installation erfolgte unter der Mail-Sperre der CLI. Es wurde kein Mail-Auftrag gestartet. Originaldateien und SHA-256-Manifest liegen unter `/Users/a321/.meister/patch-backups/mail-preview-2026-09-26T14-28-42.177Z-eb2223b1-aaf5-46f0-bbf0-ef48b5066703`.

## Änderungen

- Terminal: eine aktualisierte Zeile, maximal einmal pro Sekunde; sauberes Zeilenende auch bei Fehlern.
- Umgeleitete Logs: maximal alle zehn Sekunden plus Phasenwechsel und Abschluss; keine ANSI-Sequenzen.
- Während Mail/FM-Anfragen zeigt ein Timer weiterhin die verstrichene Laufzeit und zuletzt gemeldete Tätigkeit. Abgeschlossene Nachrichten werden dabei nicht hochgezählt.
- Vorschauseiten bündeln bis zu 100 Nachrichten statt 25, um wenige FM-Kandidaten über mehrere Leseblöcke zu sammeln. Native Leseaufrufe bleiben auf 25 Nachrichten begrenzt; höchstens eine Seite wird vorausgelesen. Das erhöht den maximalen Speicherbedarf der beiden Seiten von 50 auf 200 Nachrichtenkörper.
- Modellantworten mit fremden Nachrichten-IDs werden zusätzlich direkt in der Engine abgewiesen.
- Unvollständige lokale Inhalte bleiben geschützt. Jeder Verschiebekandidat braucht weiterhin native Bestätigung. Modellfreigaben werden nicht aus dem Fortschritt abgeleitet.

## Prüfung

Neun Node-Tests bestanden, einschließlich Abbruch bei fremden IDs, nativer Bestätigung, Erhalt unvollständiger Inhalte, Timer-Aufräumen und Ausgabebegrenzung. JavaScript-Syntaxprüfung und CLI-Hilfe ebenfalls erfolgreich.

Ein reproduzierbarer Test mit vier über 100 Nachrichten verteilten FM-Kandidaten benötigt zwei statt vier Modellprozess-Starts und liefert identische Entscheidungen. Das ist eine Messung der Aufrufzahl mit simuliertem Modell, keine Messung der realen Apple-FM-Laufzeit. Auf persönliche Maildaten wurde für Tests nicht zugegriffen.

## Patch prüfen und übernehmen

`meister-mail-preview.patch` enthält Implementierung und Tests. Im passenden CLI-Quellstand mit derselben Dateistruktur:

```sh
git apply --check /Users/a321/Developer/meister/docs/patches/meister-mail-preview.patch
git apply /Users/a321/Developer/meister/docs/patches/meister-mail-preview.patch
node --test tests/mail-preview-performance.test.mjs
```

Der Patch wurde zusätzlich auf einer unveränderten Kopie der installierten CLI angewendet; dort bestehen dieselben neun Tests. Ein späterer CLI-Release muss den regulären Homebrew-Installationsweg verwenden. Die Swift-App erhält den neuen Ablauf über ihre CLI-Anbindung.
