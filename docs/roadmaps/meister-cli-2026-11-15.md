# Meister- und MeisterAI-CLI: Befund und Roadmap (2026-11-15)

Ziel: die beiden CLIs fehlerfrei machen, benennen, was genau fehlt, und die Reihenfolge für Performance und Features festlegen. Der CLI-Code liegt in `~/Developer/homebrew-meister` (`MeisterAI.sh` ist die Quelle, `meister.sh` wird daraus erzeugt). Stand: `origin/main` mit Version 6.44.

Die drei ausgearbeiteten Aufträge für Phase 1 stehen in [meister-cli-2026-11-15-goals.md](meister-cli-2026-11-15-goals.md).

## Ausgangslage

- Die Prüfung `bash scripts/check.sh` ist grün: 278 Bats-Tests, Laufzeit 57 s.
- Der Wartungslauf vom 2026-11-15 15:46 endete trotzdem mit 2 Fehlern, 9 Warnungen und Score 57. Dieselben Fehler stehen seit mindestens drei der letzten fünf Läufe im Log.
- Getestet ist wenig vom Verhalten: Nur 7 Tests starten das ganze Skript, 31 von 40 Modulen haben keinen Test, `lib/commands/bloatware.sh` (423 Zeilen) hat keinen einzigen, und 17 Tests durchsuchen nur den Quelltext.
- `shellcheck` prüft nur `lib/` und `scripts/`. Die beiden Hauptskripte mit je rund 10.600 Zeilen laufen nicht durch; dort stehen 21 Warnungen.
- Laufzeiten sind nicht gemessen. Die Angaben „1–4 min“ und „5–15 min“ in `AGENTS.md` sind Schätzungen.

## Heute erledigt

- Meister 6.44 ist veröffentlicht und lokal installiert. `purge --do` bittet jetzt als letzten Schritt den macOS-Purge-Dienst, allen löschbaren Speicher freizugeben; `--no-system` überspringt das.
- PR #5 (Purge-Hinweis nennt die aufgerufene CLI) ist gemergt. Damit ist der Linux-Job der CI wieder grün.

- Die drei GOALs aus Phase 1 sind umgesetzt, je zweimal bzw. einmal unabhängig reviewt und liegen als PRs in `homebrew-meister` vor: #10 (GOAL 1), #11 (GOAL 2, baut auf #10 auf) und #9 (GOAL 3). Die CI ist bei allen grün.
- 2026-11-16: #10 und #9 sind gemergt, Meister 6.45 ist veröffentlicht und lokal installiert. #11 (Run-End-Autoheal) ist weiter offen und braucht ein Rebase auf `main`.

## Phase 1 — Fehler, die jeder Lauf zeigt

Drei fertig spezifizierte GOALs, in dieser Reihenfolge:

| GOAL | Inhalt | Beleg |
|---|---|---|
| 1 | Cask-Reparatur greift wieder: Das Suchmuster passt nie auf die echte Homebrew-Ausgabe, deshalb scheitern ChatGPT, hp-easy-start und fünf weitere Casks in jedem Lauf. Ein Fix zählt künftig erst nach Kontrolle mit `brew outdated`. | `MeisterAI.sh:2195`, 71 Fehlerdateien unter `~/.meister/update-failures` |
| 2 | Run-End-Autoheal: Nach den Modulen sieht Meister die offenen Befunde durch und repariert im selben Lauf, wofür ein Reparierer registriert ist. Alles andere wird als „keine automatische Reparatur“ ausgewiesen. | `MeisterAI.sh:10598`, `MeisterAI.sh:1711-1715` |
| 3 | Vorschau-Schalter halten, was sie versprechen: `heal -n`, `simfix -n` und `free --dry-run` führen heute echte Änderungen aus. Unbekannte Optionen enden einheitlich mit Exit 64. Spotlight meldet keine Scheinreparaturen auf schreibgeschützten Systemvolumes mehr. | `MeisterAI.sh:9943`, `:8002`, `:9917-9935`, `:3829-3840` |

Dazu gehört PR #7 (`release.sh` wird fortsetzbar). Sie ist offen und unabhängig von den GOALs.

GOAL 2 erfüllt „alles fixen“ bewusst nur schrittweise. Die vorhandene Heal-Leiter eignet sich dafür nicht: Sie kann bei gewöhnlichen Warnungen `~/Library/Caches` leeren, und das Modell darf nur drei Befehle ausführen (QuickLook-Cache, Finder, Dock). Jede weitere Befundklasse bekommt deshalb einen eigenen, geprüften Reparierer.

## Phase 2 — Weitere belegte Fehler

Jeder Punkt braucht einen eigenen GOAL mit eigenen Tests.

| Fehler | Stelle |
|---|---|
| `remove` beendet die App, bevor nach Bestätigung gefragt wird, und meldet Exit 0, obwohl Teile nicht entfernt wurden | `MeisterAI.sh:7600-7643`, `:7773` |
| `remove` ordnet launchd-Jobs per Teilstring zu; kurze App-Namen treffen fremde Jobs | `MeisterAI.sh:7495-7499`, `:7683` |
| `RUN_MAX_SEC`, `MODULE_SLOW_SEC` und `MEISTER_NOTIFY` in der Config werden ignoriert, obwohl die Hilfe sie dokumentiert | `MeisterAI.sh:503-505`, `:590-592` |
| Der iCloud-Stub-Scan läuft nie, weil der Pfad „Mobile Documents“ am Leerzeichen zerfällt | `MeisterAI.sh:3957`, `:4001-4004` |
| Die Liste großer Dateien schneidet Namen am ersten Leerzeichen ab | `MeisterAI.sh:3363` |
| Autofix verschiebt LaunchDaemons in Quarantäne, deren Programmpfad relativ ist oder auf einem ausgehängten Volume liegt | `MeisterAI.sh:8796-8810` |
| Die Known-Fix-Regel „No space left on device“ löscht alle Benutzer-Caches ohne Rückfrage | `MeisterAI.sh:1592-1597` |
| Die native App sendet neun Schalter, die die CLI nicht mehr kennt; diese Schaltflächen sind tot | `meister/MeisterMacOS/BashModule.swift:46-138` |

Absicherung, damit neue Fehler auffallen:

- `shellcheck` auf beide Hauptskripte ausdehnen (21 Warnungen abarbeiten, die dateiweite Ausnahme für SC2155 entfernen).
- Tests für `bloatware.sh` und für die riskanten Unterbefehle `remove`, `orphans`, `bloatware kill`.
- Die 17 Quelltext-Suchen durch Verhaltenstests ersetzen.

## Phase 3 — Performance

Erst messen, dann ändern. Die Dauer pro Modul steht bereits in `~/.meister/runs/*.json`; ausgewertet wird sie nirgends.

| Schritt | Beleg |
|---|---|
| Messbasis: Laufzeit je Profil und Modul aus den vorhandenen Laufberichten auswerten und als Referenz festhalten | Lauf vom 2026-11-15: 270 s, davon Homebrew 65 s, AI Updates 49 s, Healer 38 s |
| Homebrew-Aufrufe wiederholen sich in einem Lauf: `brew outdated` je zweimal für Formeln und Casks, `brew doctor` und `brew cleanup` an mehreren Stellen in Homebrew-Modul und Healer | `MeisterAI.sh:2031`, `:2091`, `:2122`, `:2223`, `:2284`, `:4949` |
| Start: 72 ms für `--version`, davon rund 15 ms für einen unbedingten Aufruf von `brew --prefix` | `MeisterAI.sh:393` |
| Obergrenze je Modul: Module laufen ohne eigenes Zeitlimit; einzelne Netzaufrufe haben keines | `MeisterAI.sh:1694-1712`, `:4232`, `:4501`, `:3266` |
| Verfügbarkeitsprüfung des KI-Backends wird an rund neun Stellen wiederholt statt einmal gemerkt | `MeisterAI.sh:1293-1296` |
| Reine Prüfmodule parallel ausführen — erst nach der Messbasis entscheiden | 36 Module laufen nacheinander, `MeisterAI.sh:10541-10576` |

Eine Entscheidung liegt bei dir: Der Starter führt bei abgelaufenem 12-Stunden-Stempel vor jedem Aufruf `brew update` und `brew upgrade` aus, ohne Zeitlimit, und bricht ohne Netz mit Exit 1 ab — auch bei `--version`. Das ist so gewollt und per Test festgeschrieben (`tests/test_startup_update.py:117`). Für die Performance und den Betrieb ohne Netz wäre ein Start mit der installierten Version und einer Warnung besser.

## Phase 4 — Features

- Weitere Reparierer für den Run-End-Autoheal, je einer pro Befundklasse: Formel-Linkkonflikte, verbleibende `brew doctor`-Warnungen, Cask-Zeitüberschreitungen.
- Software-Updates aus allen Quellen mit `updates --apply`. Ein Entwurf liegt im Branch `feat/software-updates-all-sources`, 62 Commits hinter `main`; er muss gegen `MeisterAI.sh` neu geschrieben werden.
- Lücken aus dem Paritäts-Tracker (meister-Issue #3), die in der CLI ganz fehlen: `clean --browser`, `files --large`, `dups`, `keychain --weak`, `hardware --json`, `hosts`, `defaults --uti`, `quarantine --strip`.
- Module aus `MeisterAI.sh` nach `lib/modules/` auslagern, wie in `lib/modules/README.md` geplant. Bisher ist nichts ausgelagert; ohne das bleibt die Datei bei 10.600 Zeilen.

## Aufräumen

- Veraltete Arbeitskopien und Branches in `homebrew-meister`: fünf Worktrees vom 2026-09-14, `feat/dual-ai-backend-twins`, `feat/fm-macos27`, `feat/siri-close-loops` und acht `codex/*`-Branches sind inhaltlich in `main` oder überholt. Der Worktree `meister-macos-repair-20260923` enthält uncommittete Änderungen und sollte vor dem Löschen angesehen werden.
- Veraltete Aussagen in der Doku: `docs/PRODUCT.md:53` nennt `AI_HEAL_EXECUTE=false`, der Code setzt `true`; `docs/requirements/MEISTER-CLOSE-LOOPS.md:3` steht auf „in progress“, ist aber fertig.

## Recap

Die CLI besteht ihre Tests, zeigt im echten Lauf aber wiederkehrende Fehler, weil Reparaturen nicht greifen und wenig Verhalten getestet ist. Phase 1 mit drei fertigen GOALs behebt die Fehler aus dem Log und führt den Autoheal am Laufende ein. Danach folgen die übrigen belegten Fehler, eine Messbasis für die Performance und erst dann neue Features.
