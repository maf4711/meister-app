# Meister CLI — GOALs 1–3 (2026-11-15)

Three code-verified GOALs for a coding agent. Target repo: `~/Developer/homebrew-meister`, base `origin/main` at v6.44. Roadmap and context: [meister-cli-2026-11-15.md](meister-cli-2026-11-15.md).

Review status: two red-team rounds; round 2 ended with 0 blockers and 9 fixes, all applied. The GOAL linter still reports 33 form errors, all of one kind: its grammar does not know `bats` or `bash scripts/check.sh` as test runners. The repo tests with exactly those, so the commands stay.

```
Recommended order: GOAL 1 (repairs the cask failures every run reports today) → GOAL 2 (run-end pass; needs the repair helper from GOAL 1) → GOAL 3 (independent; preview safety and exit codes)
Contract 1→2: shell function `brew_cask_repair <cask> <capture-file> <greedy:true|false>` in lib/core/brew_upgrade.sh; exit 0 only when the cask is absent from `brew outdated --cask` (with `--greedy` when the third argument is true) after one forced reinstall. With an empty or unreadable capture file no path is removed. A second call for the same cask in one process runs no reinstall, only the readback, and returns 0 when the cask is not listed and 1 when it is listed or the readback fails.

GOAL 1

Goal: Make the Homebrew cask repair in module_homebrew (MeisterAI.sh) and ai_update_brew (lib/core/ai_updates.sh) match the failure text Homebrew 7 prints, so a cask blocked by a stale Caskroom artifact is reinstalled once and reported as a fix only after a `brew outdated` readback no longer lists it; otherwise the existing warning stays.

Context:
- Current behaviour: MeisterAI.sh:2194-2195 extracts broken casks with patterns anchored as `^[[:space:]]*<cask>: It seems there is already an App`. Homebrew prints `Error: <cask>: It seems there is already an App at '…'`. On a TTY, run_verbose_live (MeisterAI.sh:859-860) records through `script -qF`, so the capture carries ANSI colour codes and CRLF line ends; without a TTY it records plain text. Both patterns return nothing in either case, and the repair block at MeisterAI.sh:2197-2217 never runs. MeisterAI.sh:2211-2216 counts a cask as healed from the exit status of `brew reinstall --cask --force` alone. ai_update_brew runs the upgrade through ai_update_attempt (lib/core/ai_updates.sh:20-36, output to /dev/null) at lib/core/ai_updates.sh:129 and reports an ERROR at :134 with no repair. brew_upgrade_each calls brew_record_upgrade_failure at MeisterAI.sh:924, which appends `Homebrew: <name> upgrade failed` at lib/core/brew_upgrade.sh:24 for any non-zero exit; MeisterAI.sh:2091-2112 never retracts it.
- Problem / motivation: observed 2026-11-15 15:46 (run_id 20261115T144602Z-40466-29857, ~/.meister/last.json): errors "AI Updates: chatgpt update/verification failed" and "AI Updates failed"; warnings for ada-url, antigravity-cli and hp-easy-start. ~/.meister/update-failures/cask-hp-easy-start.rjvWeO contains `Error: hp-easy-start: It seems there is already an App at '/opt/homebrew/Caskroom/hp-easy-start/2.16.7,260722/HP Easy Start.app'.`; the anchored pattern has 0 matches in that file, the unanchored text has 1 match. ~/.meister/update-failures holds 71 files; 7 casks fail with the stale-artifact text (App: raycast, ledger-wallet, iterm2, hp-easy-start, google-chrome, chatgpt; Command Wrapper and Binary: antigravity-cli). ada-url was upgraded (transcript: "Upgraded 1 requested outdated package") yet is reported as failed because the dependent node failed to link.
- Why now: the same failures repeat on every maintenance run; the run-end log analysis of 2026-11-15 15:50:29 lists them as recurring in 3 of the last 5 runs, and they keep the process exit status at 1 (MeisterAI.sh:10612-10613).
- Related requirement: MEISTER-RELIABILITY-DASHBOARD criterion 2 (implemented, docs/requirements/MEISTER-RELIABILITY-DASHBOARD.md) — the dashboard separates repairs from verified repairs; it does not cover cask repairs that never start.
- Prior art in repo: the repair block at MeisterAI.sh:2197-2217 (remove stale path, forced reinstall); brew_record_upgrade_failure at lib/core/brew_upgrade.sh:13-25 (private 0600 evidence file); the post-upgrade readback at MeisterAI.sh:2221-2226.

Impact:
- Callers of changed code (non-test): module_homebrew is dispatched at MeisterAI.sh:10542; brew_upgrade_each is called at MeisterAI.sh:2064 (formulae) and MeisterAI.sh:2184 (casks); ai_update_brew is called at lib/core/ai_updates.sh:310 by module_ai_updates. meister.sh is generated from MeisterAI.sh by scripts/sync-twins.sh and carries the same code.
- Test callers: 3 files under tests/ — brew_retry_reporting.bats (4 tests), ai_updates.bats (31 tests), brew_upgrade.bats.
- Upstream (where input comes from): Homebrew output captured in RUN_VERBOSE_OUT (MeisterAI.sh:832-878) and `brew outdated` output.
- Downstream (where output goes): report ledger via report_add (MeisterAI.sh:769-789) → ~/.meister/last.json through write_last_json (lib/core/last_json.sh:43) → read by app/MeisterAI/Sources/Models/RunReport.swift:78-125; process exit status at MeisterAI.sh:10612-10613.
- Deploy unit: Homebrew formula maf4711/meister/meister (Formula/meister.rb installs MeisterAI.sh, meister.sh and lib/ into libexec).
- Deploy needed: yes — formula release through ./release.sh plus scripts/install-release.sh (AGENTS.md "Nach jedem Release IMMER lokal installieren"); the orchestrator runs it after merge, the implementing agent does not.

Scope:
- In scope: MeisterAI.sh (module_homebrew cask and formula sections, brew_upgrade_each), lib/core/brew_upgrade.sh, lib/core/ai_updates.sh (ai_update_brew only), meister.sh (regenerated with scripts/sync-twins.sh, never hand-edited), tests/brew_retry_reporting.bats, tests/ai_updates.bats.
- Out of scope — do NOT move module_homebrew or any other module body out of MeisterAI.sh into lib/modules/ — because lib/modules/README.md:11-19 plans that extraction as separate work and it would bury a 60-line fix in a 400-line move.
- Out of scope — do NOT change ai_update_attempt or ai_update_native (lib/core/ai_updates.sh:20-60) — because ai_update_attempt is shared with native and npm updaters whose output can contain account information (comment at lib/core/ai_updates.sh:19); ai_update_brew captures the cask `brew upgrade` output itself, only into the 0600 file written by brew_record_upgrade_failure.
- Out of scope — do NOT edit release.sh, scripts/release-lib.sh or scripts/check.sh — because open PR #7 (fix/release-resume-codeload) changes those files.
- Out of scope — do NOT add BREW_CASK_SKIP entries or uninstall casks to silence failures — because a cask must end the run either current or named in a warning.
- Out of scope — do NOT handle upgrade timeouts (`Error: SIGTERM`, for example docker-desktop with 9 failure files) — because they are a different failure class with no stale artifact to remove.
- Prefer: one shared helper in lib/core/brew_upgrade.sh (sourced at MeisterAI.sh:428) used by both module_homebrew and ai_update_brew, over a second copy of the repair logic in lib/core/ai_updates.sh.

Acceptance criteria:
1. A cask upgrade whose output contains `Error: <cask>: It seems there is already an App at '<path>'.`, `… a Command Wrapper at '<path>'.` or `… a Binary at '<path>'.` — with or without ANSI colour codes and with LF or CRLF line ends — triggers exactly one forced reinstall of that cask in the same module_homebrew run.
   Fails today: MeisterAI.sh:2195 anchors the pattern at line start before the cask name and has no Command Wrapper or Binary pattern, so the observed line `Error: hp-easy-start: It seems there is already an App` has 0 matches (observed 2026-11-15 on ~/.meister/update-failures/cask-hp-easy-start.rjvWeO).
   Verify: `bats --tap tests/brew_retry_reporting.bats --filter "stale artifact failures trigger one forced reinstall"` → exit 0
2. A repaired cask is reported as a fix only when the readback no longer lists it — `brew outdated --cask --greedy <cask>` when the failed upgrade used `--greedy`, `brew outdated --cask <cask>` otherwise — and its earlier `Homebrew: <cask> upgrade failed` warning is then absent from the report.
   Fails today: MeisterAI.sh:2211-2216 increments the healed counter from the reinstall exit status and never reads `brew outdated`; the warning appended through MeisterAI.sh:924 is never removed.
   Verify: `bats --tap tests/brew_retry_reporting.bats --filter "verified cask repair retracts its failure warning"` → exit 0
3. Error path: when the forced reinstall exits non-zero, or the readback still lists the cask, or the readback command itself fails, no fix is reported for that cask, its warning stays in the report, and the reinstall was attempted exactly once.
   Fails today: no test covers a failing or ineffective cask reinstall (rg -n "reinstall" tests/brew_retry_reporting.bats: 0 matches).
   Verify: `bats --tap tests/brew_retry_reporting.bats --filter "failed cask repair keeps the warning and runs once"` → exit 0
4. ai_update_brew returns 0, adds no ERROR entry and adds `AI Updates: <cask> current in Homebrew` when an AI client cask fails its first upgrade with the stale-artifact text and the greedy readback is empty after one forced reinstall.
   Fails today: lib/core/ai_updates.sh:129-135 retries the identical upgrade through ai_update_attempt and has no repair branch; observed "AI Updates: chatgpt update/verification failed" on 2026-11-15.
   Verify: `bats --tap tests/ai_updates.bats --filter "stale artifact cask is repaired and verified for AI clients"` → exit 0
5. A formula whose `brew upgrade --formula <name>` exits non-zero is not reported as `upgrade failed` when `brew outdated --formula` exits 0 and no longer lists it at the end of module_homebrew; when that readback exits non-zero the warning stays.
   Fails today: MeisterAI.sh:2091 discards the readback exit status and MeisterAI.sh:2092-2112 never retracts the warning; observed 2026-11-15 for ada-url (4.0.0_2 installed, warning kept).
   Verify: `bats --tap tests/brew_retry_reporting.bats --filter "upgraded formula with failing post-step is not reported failed"` → exit 0
6. No test is skipped or removed; the collected count in tests/brew_retry_reporting.bats grows by 4.
   Fails today: N/A — guard
   Verify: `bats --count tests/brew_retry_reporting.bats` → "8"
7. Existing tests still pass
   Verify: `bash scripts/check.sh` → exit 0

Edge cases:
  - failure line preceded by ANSI colour codes and `Error:` and ended by `\r` → matched (criterion 1, test (a))
  - Command Wrapper and Binary conflicts (`antigravity-cli`, `/opt/homebrew/bin/agy`) → same single forced reinstall (criterion 1, test (a))
  - stale path named by Homebrew lies outside `$(brew --prefix)/Caskroom/` → the path is left in place and only the forced reinstall runs (test (b))
  - auto-updating cask listed only by `brew outdated --cask --greedy` → not reported as repaired after a non-greedy readback (criterion 2, test (b))
  - reinstall exits 0 but the cask is still outdated → warning kept, no fix (criterion 3, test (c))
  - the same cask fails in AI Updates and again in Homebrew within one process → the second failure triggers no second reinstall (test (e))
  - `DRY_RUN=true` → no reinstall call and no path removal (test (b))

Tests to add (in tests/brew_retry_reporting.bats and tests/ai_updates.bats):
  (a) "stale artifact failures trigger one forced reinstall": run_verbose_live stub writes `\033[31mError:\033[0m hp-easy-start: It seems there is already an App at '<tmp>/Caskroom/hp-easy-start/2.16.7,260722/HP Easy Start.app'.\r\n`, `Error: antigravity-cli: It seems there is already a Command Wrapper at '<tmp>/bin/agy'.` and, for a third cask, `Error: tool-x: It seems there is already a Binary at '<tmp>/bin/tool-x'.` → brew-calls holds exactly 1 `reinstall --cask --force` line per cask (3 lines)
  (b) "verified cask repair retracts its failure warning": brew stub answers `--prefix` with `<tmp>`, lists the cask as outdated before and not after the reinstall; the message names a path outside `<tmp>/Caskroom` → report holds 1 line `FIX Homebrew: repaired cask hp-easy-start (stale artifact; reinstalled and verified current)`, 0 lines matching `WARN.*hp-easy-start.*failed`, the outside path still exists; with BREW_UPGRADE_GREEDY=true and a stub that lists the cask only under `outdated --cask --greedy` → 0 FIX lines; with DRY_RUN=true → 0 `reinstall` lines in brew-calls
  (c) "failed cask repair keeps the warning and runs once": casks cask-a and cask-b; reinstall stub returns 1 for cask-a and 0 for cask-b while the readback still lists cask-b; in a third sub-case the readback exits 2 → exactly 2 report lines matching `^WARN Homebrew: (cask-a|cask-b) upgrade failed`, 0 lines matching `^FIX Homebrew: repaired cask`, 1 reinstall call per cask
  (d) "upgraded formula with failing post-step is not reported failed": run_verbose_live returns 1 for formula ada-url; `outdated --formula` prints nothing and exits 0 → 0 lines matching `WARN.*ada-url.*failed`; sub-case `outdated --formula` exits 2 → 1 line matching `WARN.*ada-url.*failed`
  (e) in tests/ai_updates.bats, "stale artifact cask is repaired and verified for AI clients": brew stub fails the first `upgrade --cask --greedy chatgpt` with the stale-app text, succeeds on `reinstall --cask --force chatgpt`, then `outdated --cask --greedy chatgpt` prints nothing → status 0, 0 output lines containing `ERROR`, 1 `upgrade` call, 1 `reinstall --cask --force chatgpt` call, 1 line `SUCCESS AI Updates: chatgpt current in Homebrew`; a second call of the repair helper for chatgpt in the same shell adds 0 reinstall calls

Example:
  - Input: `MeisterAI --auto` on a Mac where `brew upgrade --cask hp-easy-start` prints `Error: hp-easy-start: It seems there is already an App at '/opt/homebrew/Caskroom/hp-easy-start/2.16.7,260722/HP Easy Start.app'.` and exits 1.
  - Output: the log shows `Homebrew: repaired cask hp-easy-start (stale artifact; reinstalled and verified current)`; ~/.meister/last.json lists that string under `fixes` and has no `Homebrew: hp-easy-start upgrade failed` entry under `warnings`.

Interface:
- New names: shell functions `brew_cask_conflict_names` (stdin: captured Homebrew output; stdout: one cask token per line) and `brew_cask_repair` ($1 = cask token, $2 = capture file, $3 = `true` when the failed upgrade used `--greedy`; exit 0 only when the readback no longer lists the cask; with an empty or unreadable $2 no path is removed; a second call for the same cask in one process runs no reinstall, only the readback, and returns 0 when the cask is not listed and 1 when it is listed or the readback fails) in lib/core/brew_upgrade.sh — named after the siblings brew_cask_is_skipped, brew_cask_tokens and brew_filter_skipped_casks at lib/core/brew_upgrade.sh:42-71.
- Signatures / schema: fix string in module_homebrew `Homebrew: repaired cask <name> (stale artifact; reinstalled and verified current)`; ai_update_brew reports a verified repair with its existing success string `AI Updates: <token> current in Homebrew` (lib/core/ai_updates.sh:132); warning string `Homebrew: <name> upgrade failed (exit <rc>); log: <path>` from lib/core/brew_upgrade.sh:24 stays byte-identical.
- Unchanged: ~/.meister/last.json schema `meister.last/v1` (lib/core/last_json.sh:70); CLI flags; BREW_CASK_SKIP semantics; ai_update_attempt. The summary string `Auto-healed <n> broken cask(s)` at MeisterAI.sh:2216 is replaced by the per-cask fix string.

Constraints:
- Reuse: brew_record_upgrade_failure at lib/core/brew_upgrade.sh:13 for evidence files; ensure_sudo as used at MeisterAI.sh:2210; the function-extraction harness at tests/brew_retry_reporting.bats:18-21.
- Dependencies: no new dependencies.
- Limits: 1 attempt of the forced reinstall per cask per process, shared by AI Updates and Homebrew; each reinstall bounded by 180 s in module_homebrew (`cask_timeout`, MeisterAI.sh:2149) and by 300 s in ai_update_brew (the bound used at lib/core/ai_updates.sh:23); in ai_update_brew the repair runs after the first failed upgrade, with 0 retries of the identical upgrade; path removal only for paths under `$(brew --prefix)/Caskroom/`.
- Workflow: base origin/main; fresh worktree (the main checkout is on fix/release-resume-codeload with untracked .claude-flow/ and .swarm/); no env bootstrap beyond the tools scripts/check.sh:7 requires (shellcheck, bats, python3, node — installed on this Mac); edit MeisterAI.sh, then run `bash scripts/sync-twins.sh` to regenerate meister.sh; one PR for this GOAL; one commit per green criterion.
- Test command: `bash scripts/check.sh`
- Forbidden actions: no push, no PR, no ./release.sh, no `brew` call against the real system (tests use the stubbed `brew` function), no writes under ~/.meister.
- Style: new shared logic goes into lib/core (MeisterAI.sh has 10614 lines; the repo rule is files under 500 lines, so MeisterAI.sh gains call sites only); lib/core/*.sh stays clean under `shellcheck -S warning` (scripts/check.sh:16).

Risk & rollback:
- What breaks if wrong: a pattern that matches too broadly forces a reinstall of a healthy cask; a path removal outside the Caskroom deletes an app bundle; a readback without `--greedy` reports auto-updating casks (chatgpt, raycast, iterm2, google-chrome, ledger-wallet) as repaired while they stay outdated.
- Rollback: git revert of the merge commit and a formula release of the reverted script; no state migration.
- Proof in production: after the next `MeisterAI --auto`, ~/.meister/last.json has no `warnings` entry matching `Homebrew: (hp-easy-start|antigravity-cli) upgrade failed` and no `errors` entry containing `chatgpt`, and `HOMEBREW_NO_AUTO_UPDATE=1 brew outdated --cask --greedy` lists neither hp-easy-start nor chatgpt.

Open questions / assumptions:
- Assume `brew reinstall --cask --force <cask>` clears all three conflict classes on Homebrew 7.0.13; criterion 2 makes the `brew outdated` readback the only source of a fix claim and criterion 3 keeps the warning when the assumption does not hold.
- Assume Caskroom directories with repeated `.upgrading` suffixes (observed: /opt/homebrew/Caskroom/chatgpt/26.928.21956.upgrading) are leftovers of the same failure and need no separate handling once the forced reinstall succeeds.

Report back:
  - per acceptance criterion: the Verify command run and its quoted output
  - the RED run: the five new tests failing before the change (quoted bats lines)
  - `git diff origin/main...HEAD --stat` and the branch name; no push, no PR, no release

GOAL 2

Goal: Add a run-end heal pass to MeisterAI.sh that reviews the report warnings and errors of the finished run (the findings), counts that run's WARN and ERROR log lines for a review line (log lines are not findings), gives every finding that has a registered repairer exactly one repair attempt before the report is printed, removes a finding from the report only when its repairer verifies the repair, and records attempted, verified, unresolved, skipped and unrepairable counts in the report and in ~/.meister/last.json.

Context:
- Current behaviour: run_module_safe returns at MeisterAI.sh:1711-1715 as soon as the module function exits 0, so no heal step runs for a module that ends with warnings. log_analysis (MeisterAI.sh:6302-6349), called at MeisterAI.sh:10598, reads the log after all modules and only prints recurring messages (MeisterAI.sh:6338-6341); it starts no repair. report_add (MeisterAI.sh:786-787) only appends to REPORT_WARNINGS and REPORT_ERRORS. write_last_json (lib/core/last_json.sh:43-99) writes no field about run-end work. The only commands AI-Heal may execute are `/usr/bin/qlmanage -r cache`, `/usr/bin/killall Finder` and `/usr/bin/killall Dock` (lib/core/heal_guards.sh:92).
- Problem / motivation: user request 2026-11-15: "schau dir die logs genau immer an und mach dann im selben run einen autoheal lauf und fix alles in runtime". Observed in the run of 2026-11-15 15:46 (~/.meister/runs/20261115T144602Z-40466-29857.json): module Homebrew ended with status WARN after 3 failed upgrades, exit 0, and received no repair attempt; `heal` is 1 for the whole run (AI Updates only). At 15:50:29 the log analysis printed 7 recurring problems and the run ended. The log of that run holds 4 `ERROR … Spotlight-Index with errors` lines that have no entry under `errors` in last.json.
- Why now: user request of 2026-11-15; that day's run ended with 9 warnings and 2 errors still open and no code path acted on them.
- Related requirement: MEISTER-RELIABILITY-DASHBOARD criterion 4 (implemented, docs/requirements/MEISTER-RELIABILITY-DASHBOARD.md) — "Only verified successes are eligible for reuse, repeated failures suspend a candidate"; it covers learned repairs of failed modules, not findings left open at run end.
- Prior art in repo: brew_cask_repair in lib/core/brew_upgrade.sh (delivered by GOAL 1; exit 0 only after a `brew outdated` readback); the three-consecutive-failures suspension at lib/core/learned_fixes.sh:81; soft run budget RUN_MAX_SEC at MeisterAI.sh:503 and its check at MeisterAI.sh:10473-10477; log_heal_event at MeisterAI.sh:1385.

Impact:
- Callers of changed code (non-test): the new pass is called once between MeisterAI.sh:10596 and the log_analysis call at MeisterAI.sh:10598; write_last_json is called by save_history (MeisterAI.sh:10608); print_report (MeisterAI.sh:6106) gains one summary line. run_module_safe, known_fix, ai_heal and heal_verify_module are not called and not changed.
- Test callers: 2 files under tests/ — last_json.bats (10 tests of write_last_json), cli_contract.bats (7 whole-script tests that read last.json).
- Upstream (where input comes from): the report arrays REPORT_WARNINGS and REPORT_ERRORS (MeisterAI.sh:769-789); $LOGFILE (~/.meister/meister.log) from the line `… started (` of the current run onward.
- Downstream (where output goes): ~/.meister/last.json and ~/.meister/runs/<run_id>.json, read by app/MeisterAI/Sources/Models/RunReport.swift:78-125 (keyed decoding; keys outside its CodingKeys are ignored); the terminal report; ~/.meister/heal.log through log_heal_event.
- Deploy unit: Homebrew formula maf4711/meister/meister.
- Deploy needed: yes — formula release through ./release.sh plus scripts/install-release.sh, run by the orchestrator after merge.

Scope:
- In scope: new file lib/core/run_end_heal.sh; MeisterAI.sh (source line next to MeisterAI.sh:428, call site before :10598, defaults next to :503, config key lists at :590-592, one summary line in print_report); lib/core/last_json.sh (one added field); config.fast.example (documented keys); meister.sh (regenerated with scripts/sync-twins.sh); new file tests/run_end_heal.bats; tests/last_json.bats.
- Out of scope — do NOT call known_fix (MeisterAI.sh:1576-1630), ai_heal (MeisterAI.sh:1400) or heal_verify_module (MeisterAI.sh:1637) from the pass — because known_fix patterns such as `*"kill"*` (MeisterAI.sh:1624) match ordinary warning text like `Skill-Suite: 30 uncommitted changes` and `*"No space left on device"*` deletes ~/Library/Caches (MeisterAI.sh:1592-1597); ai_heal can only restart Finder or Dock; heal_verify_module treats exit 0 as verified (MeisterAI.sh:1668), which is always true for a module that ended with warnings.
- Out of scope — do NOT re-run module functions from the pass — because modules repeat side effects on a second run (Spotlight reindex with sudo at MeisterAI.sh:3846-3851, git commit and push in module_git_repos).
- Out of scope — do NOT rewrite log_analysis or its recurrence rule (MeisterAI.sh:6302-6349) — because tests/log_review.bats:22-44 pin that rule.
- Out of scope — do NOT run the pass when DRY_RUN is true — because MeisterAI.sh:10604 promises "no scans, repairs or measurements executed" for a preview and tests/cli_contract.bats:69-93 pin it.
- Out of scope — do NOT remove or rename the fields written by lib/core/last_json.sh:70-99 — because RunReport.swift:89 rejects reports whose schema differs and two apps read these files.
- Prefer: a repairer that verifies by readback like brew_cask_repair (lib/core/brew_upgrade.sh, GOAL 1) over trusting a command's exit status as in MeisterAI.sh:2211-2216.

Acceptance criteria:
1. A report warning `Homebrew: <cask> upgrade failed …; log: <path>` whose evidence file is a cask capture containing a stale-artifact conflict for that cask, and that is still present when the modules have finished, receives exactly one call of its registered repairer in the same run, before the report is printed; a finding that matches no registered repairer triggers no command and is counted as unrepairable with one log line `Run-end heal: no automatic repair — <finding>`.
   Fails today: MeisterAI.sh:10598 calls only log_analysis after the modules and no run-end repair code exists (rg -n "run_end_heal" MeisterAI.sh lib: 0 matches).
   Verify: `bats --tap tests/run_end_heal.bats --filter "finding with a repairer gets exactly one attempt"` → exit 0
2. When the repairer exits 0, the finding is absent from the report, one fix `Run-end heal: verified — <finding>` is recorded, and the verified repair count grows by 1.
   Fails today: MeisterAI.sh:786-787 only appends to REPORT_WARNINGS and REPORT_ERRORS and no code removes entries (rg -n "Run-end heal" MeisterAI.sh lib: 0 matches).
   Verify: `bats --tap tests/run_end_heal.bats --filter "verified repair retracts the finding and counts once"` → exit 0
3. Error path: when the repairer exits non-zero, the finding stays in the report, no fix is recorded and one warning `Run-end heal: unresolved — <finding>` is added; after 2 consecutive runs in which the same finding stayed unresolved, the finding is counted as skipped and its repairer is not called for 7 days.
   Fails today: no test covers an unresolved run-end repair (rg -n "unresolved" tests/last_json.bats tests/cli_contract.bats: 0 matches; tests/run_end_heal.bats is absent).
   Verify: `bats --tap tests/run_end_heal.bats --filter "unresolved repair keeps the finding and suspends after two runs"` → exit 0
4. Boundary: the pass starts no further repairer once RUN_END_HEAL_MAX_SEC seconds have passed or RUN_END_HEAL_MAX_ATTEMPTS attempts are used, counts each remaining repairable finding as skipped, and performs zero attempts when DRY_RUN is true, when RUN_END_HEAL is false, or when RUN_STATUS is not `completed`.
   Fails today: MeisterAI.sh:503-504 defines only RUN_MAX_SEC and MODULE_SLOW_SEC; no run-end budget or opt-out setting exists (rg -n "RUN_END_HEAL" MeisterAI.sh lib config.fast.example: 0 matches).
   Verify: `bats --tap tests/run_end_heal.bats --filter "budget, dry run, opt-out and partial runs stop attempts"` → exit 0
5. The pass logs one line `Run-end review: <r> report findings, <l> WARN/ERROR log lines this run` whose two numbers equal the report entries and the log lines of the current run, and returns 0 with all counts 0 and one WARN line when the log file is missing.
   Fails today: MeisterAI.sh:6338-6341 prints only messages that recur across runs; no line reports the current run's totals (rg -n "Run-end review" MeisterAI.sh lib: 0 matches).
   Verify: `bats --tap tests/run_end_heal.bats --filter "review counts report findings and log lines of this run"` → exit 0
6. ~/.meister/last.json carries a `run_end_heal` object with the integer fields attempted, verified, unresolved, skipped and unrepairable, and every field written before this change keeps its name and value.
   Fails today: lib/core/last_json.sh:70-99 writes no `run_end_heal` key (rg -n "run_end_heal" lib/core/last_json.sh: 0 matches).
   Verify: `bats --tap tests/last_json.bats --filter "run-end heal counts are written as integers"` → exit 0
7. No test is skipped or removed; the collected count in tests/last_json.bats grows by 1.
   Fails today: N/A — guard
   Verify: `bats --count tests/last_json.bats` → "11"
8. Existing tests still pass
   Verify: `bash scripts/check.sh` → exit 0

Edge cases:
  - report holds no warning and no error → 0 attempts, review line with `0 report findings` (criterion 5, test (e))
  - finding with a run-varying number (`Homebrew: x upgrade failed (exit 1); log: /…/cask-x.AbC123`) → treated as the same finding across runs for the suspension count (criterion 3, test (c))
  - two findings name the same cask → 1 repairer call for that cask (test (a))
  - formula failure (`log: …/formula-ada-url.*`) or cask timeout (`Error: SIGTERM` in the evidence file) → no repairer call, counted unrepairable (criterion 1, test (a))
  - repairer function is not defined (GOAL 1 helper missing) → the finding is counted unrepairable, no command runs (test (a))
  - time budget used up between two attempts → remaining repairable findings skipped (criterion 4, test (d))
  - run interrupted or without internet (RUN_STATUS `interrupted` or `partial`, MeisterAI.sh:10595) → 0 attempts (criterion 4, test (d))
  - log file missing or unreadable → one WARN line, exit status 0, all counts 0 (criterion 5, test (e))

Tests to add (in tests/run_end_heal.bats and tests/last_json.bats):
  (a) "finding with a repairer gets exactly one attempt": REPORT_WARNINGS holds `Homebrew: hp-easy-start upgrade failed (exit 1); log: <tmp>/cask-hp-easy-start.AbC` (file with the stale-app text), the same finding a second time, `Homebrew: docker-desktop upgrade failed (exit 124); log: <tmp>/cask-docker-desktop.XyZ` (file with `Error: SIGTERM`), `Homebrew: ada-url upgrade failed (exit 1); log: <tmp>/formula-ada-url.WL6` and `6 new entries in Documents root`; brew_cask_repair is a stub that logs its arguments → the stub log holds exactly 1 line, starting with `hp-easy-start`; the output holds 1 line `Run-end heal: no automatic repair — ` for each of docker-desktop, ada-url and the Documents finding, and RUN_END_HEAL_UNREPAIRABLE equals 3; with the stub function unset → 0 stub calls and RUN_END_HEAL_UNREPAIRABLE equals 5
  (b) "verified repair retracts the finding and counts once": repairer stub returns 0 → REPORT_WARNINGS holds 0 entries containing `hp-easy-start`, REPORT_FIXED holds 1 entry `Run-end heal: verified — Homebrew: hp-easy-start upgrade failed`, VERIFIED_REPAIR_COUNT equals 1, RUN_END_HEAL_VERIFIED equals 1, and MODULE_LEDGER is byte-identical before and after the pass
  (c) "unresolved repair keeps the finding and suspends after two runs": repairer stub returns 1; the pass is invoked 3 times with the same MEISTER_DIR and a different log-file suffix in the finding each time → runs 1 and 2 each add 1 warning `Run-end heal: unresolved — Homebrew: hp-easy-start upgrade failed` and 0 FIX entries; run 3 makes 0 stub calls and RUN_END_HEAL_SKIPPED equals 1; with the state file's timestamp set 8 days back, a fourth run makes 1 stub call
  (d) "budget, dry run, opt-out and partial runs stop attempts": 4 findings for 4 casks with RUN_END_HEAL_MAX_ATTEMPTS=2 → 2 stub calls and skipped equals 2; RUN_END_HEAL_MAX_SEC=0 → 0 calls; DRY_RUN=true → 0 calls; RUN_END_HEAL=false → 0 calls; RUN_STATUS=partial → 0 calls
  (e) "review counts report findings and log lines of this run": a log with 2 runs, the current one holding 3 WARN and 1 ERROR line, and a report with 2 warnings → 1 line `Run-end review: 2 report findings, 4 WARN/ERROR log lines this run`; empty report → `0 report findings`; LOGFILE pointing to an absent file → exit status 0, 1 WARN line, all five counts 0
  (f) in tests/last_json.bats, "run-end heal counts are written as integers": RUN_END_HEAL_ATTEMPTED=2, RUN_END_HEAL_VERIFIED=1, RUN_END_HEAL_UNRESOLVED=1, RUN_END_HEAL_SKIPPED=3, RUN_END_HEAL_UNREPAIRABLE=4 → parsed JSON has `run_end_heal == {"attempted": 2, "verified": 1, "unresolved": 1, "skipped": 3, "unrepairable": 4}` and schema `meister.last/v1`

Example:
  - Input (synthetic, two findings): `MeisterAI --auto`; when the modules have finished, the report holds `Homebrew: hp-easy-start upgrade failed (exit 1); log: …/cask-hp-easy-start.AbC` and `6 new entries in Documents root`, and the run's log holds 9 WARN/ERROR lines; the repairer's readback no longer lists the cask.
  - Output: the log shows `Run-end review: 2 report findings, 9 WARN/ERROR log lines this run`, `Run-end heal: verified — Homebrew: hp-easy-start upgrade failed`, `Run-end heal: no automatic repair — 6 new entries in Documents root`; the report prints `Run-end heal: 1 attempted, 1 verified, 0 unresolved, 0 skipped, 1 without automatic repair`; ~/.meister/last.json contains `"run_end_heal": {"attempted": 1, "verified": 1, "unresolved": 0, "skipped": 0, "unrepairable": 1}` and no hp-easy-start entry under `warnings`.

Interface:
- New names: file lib/core/run_end_heal.sh with shell functions `run_end_heal` (no arguments, the pass) and `run_end_heal_repairer <finding>` (stdout: the repair command line for a finding, empty when none is registered); the first and only registered repairer maps `Homebrew: <cask> upgrade failed …; log: <path>` to `brew_cask_repair <cask> <path> true`, and only when the basename of `<path>` starts with `cask-` and `brew_cask_conflict_names < <path>` prints `<cask>`; every other finding (formula failures, timeouts with `Error: SIGTERM`, findings without a log path) has no repairer; counters RUN_END_HEAL_ATTEMPTED, RUN_END_HEAL_VERIFIED, RUN_END_HEAL_UNRESOLVED, RUN_END_HEAL_SKIPPED, RUN_END_HEAL_UNREPAIRABLE; config keys RUN_END_HEAL (boolean, default true), RUN_END_HEAL_MAX_SEC (number, default 300), RUN_END_HEAL_MAX_ATTEMPTS (number, default 5) — spelled like the siblings RUN_MAX_SEC and MODULE_SLOW_SEC at MeisterAI.sh:503-504; state file `$MEISTER_DIR/run_end_heal.tsv`; heal-log type `run-end` for log_heal_event.
- Signatures / schema: last.json gains `"run_end_heal": {"attempted": <int>, "verified": <int>, "unresolved": <int>, "skipped": <int>, "unrepairable": <int>}` placed before `"ai_heal_mode"`; log and report strings `Run-end review: <r> report findings, <l> WARN/ERROR log lines this run`, `Run-end heal: verified — <finding>`, `Run-end heal: unresolved — <finding>`, `Run-end heal: no automatic repair — <finding>`, `Run-end heal: <a> attempted, <v> verified, <u> unresolved, <s> skipped, <n> without automatic repair`; in these strings `<finding>` is the report entry cut before ` (exit`.
- Unchanged: schema id `meister.last/v1`; all existing last.json fields; exit status rule at MeisterAI.sh:10612-10613; the AI-Heal allowlist; run_module_safe; CLI flags; MODULE_LEDGER — a module's status stays as observed when the module ended (MeisterAI.sh:736-748), so `modules` in last.json can show WARN for a module whose warning the pass retracted; the `run_end_heal` object explains the difference.

Constraints:
- Reuse: brew_cask_repair (lib/core/brew_upgrade.sh, GOAL 1); meister_json_number (lib/core/last_json.sh:16); log_heal_event (MeisterAI.sh:1385); the sourcing pattern at MeisterAI.sh:426-428; the standalone lib test setup of tests/learned_fixes.bats:3-14.
- Dependencies: no new dependencies.
- Limits: RUN_END_HEAL_MAX_SEC default 300 s for starting attempts; each run-end repair is bounded by 180 s (BREW_CASK_TIMEOUT_SEC, MeisterAI.sh:2149), so the pass adds at most 300 s + 180 s to a run; RUN_END_HEAL_MAX_ATTEMPTS default 5 attempts per run; 1 attempt per finding subject per run; suspension after 2 consecutive unresolved runs, lifted after 7 days; the suspension key is the finding with every digit run replaced by `N` and the `log:` path removed; lib/core/run_end_heal.sh stays under 500 lines.
- Workflow: base origin/main after GOAL 1 is merged; fresh worktree; no env bootstrap beyond the tools scripts/check.sh:7 requires; edit MeisterAI.sh, then run `bash scripts/sync-twins.sh`; one PR for this GOAL; one commit per green criterion.
- Test command: `bash scripts/check.sh`
- Forbidden actions: no push, no PR, no ./release.sh, no run of the installed `meister` or `MeisterAI` against the real system, no `brew` call against the real system, no writes under ~/.meister.
- Style: lib/core/run_end_heal.sh starts with `# shellcheck shell=bash` like lib/core/learned_fixes.sh:1 and passes `shellcheck -S warning` (scripts/check.sh:16); RUN_END_HEAL_MAX_SEC and RUN_END_HEAL_MAX_ATTEMPTS are added to `_NUM_KEYS` at MeisterAI.sh:591 and RUN_END_HEAL to `_BOOL_KEYS` at MeisterAI.sh:590; the pass runs only when RUN_STATUS is `completed` (MeisterAI.sh:10591) and INTERRUPTED is false.

Risk & rollback:
- What breaks if wrong: a daily run grows by up to 480 s (300 s budget plus one 180 s repair in flight); a finding removed without a verified readback hides a real failure from the report and both apps.
- Rollback: set `RUN_END_HEAL=false` in ~/.meister/config (takes effect on the next run), or git revert of the merge commit plus a formula release.
- Proof in production: after the next `MeisterAI --auto`, `rg -c ' - [A-Z-]+ - +Run-end review: ' ~/.meister/meister.log` is at least 1 and ~/.meister/last.json contains the key `run_end_heal` with five integer fields.

Open questions / assumptions:
- Assume the defaults 300 s, 5 attempts and suspension after 2 unresolved runs for 7 days; they are product decisions taken here from the measured run of 2026-11-15 (270 s total, 3 failed casks).
- Assume one registered repairer (failed cask upgrades) is the complete first delivery; every other finding class stays visible as "no automatic repair" and receives a repairer through a later GOAL, one class at a time.
- Assume a cask that GOAL 1 repaired and verified inside module_homebrew is no longer in the report at run end; for a cask whose first repair did not verify, brew_cask_repair's limit of 1 reinstall per cask per process makes the run-end call a second readback, which catches upgrades that completed late.

Report back:
  - per acceptance criterion: the Verify command run and its quoted output
  - the RED run: the six new tests failing before the change (quoted bats lines)
  - `git diff origin/main...HEAD --stat` and the branch name; no push, no PR, no release

GOAL 3

Goal: Make the subcommands heal, simfix, autofix and free in MeisterAI.sh honour `-n` and `--dry-run` in any argument position, make unknown options exit 64 on stderr like unknown commands, and stop module_spotlight_fix from reindexing read-only cryptex mounts.

Context:
- Current behaviour: MeisterAI.sh:9942-9943 (heal) and MeisterAI.sh:8001-8002 (simfix) set DRY_RUN=true only when the second argument is exactly `--dry-run`; MeisterAI.sh:8901 (autofix) checks only the second argument for `--dry-run` or `-n`; MeisterAI.sh:9917-9935 (free) has no preview branch and runs `ensure_sudo` and `sudo -n purge` for any arguments. An unknown long option prints to stdout and exits 1 at MeisterAI.sh:10042; an unknown short option exits 1 at MeisterAI.sh:10198; an unknown command exits 64 on stderr at MeisterAI.sh:10205-10206. module_spotlight_fix skips ten volume prefixes at MeisterAI.sh:3829-3840, none of them `/private/var/run/com.apple.security.cryptexd/`, and at MeisterAI.sh:3846-3851 runs `sudo -n mdutil -E` on a volume whose status contains "error" and records a fix without a readback.
- Problem / motivation: `MeisterAI heal -n` and `MeisterAI simfix -n` perform real repairs (simfix kills the Simulator and deletes CoreSimulator caches); `MeisterAI free --dry-run` runs `sudo purge`. Observed 2026-11-15 15:50 in ~/.meister/meister.log: 4 lines `ERROR … /private/var/run/com.apple.security.cryptexd/mnt/… Spotlight-Index with errors`, and ~/.meister/last.json lists 4 fixes `Spotlight: … reindexiert` plus `Spotlight Fix: 4 repairs` for the same mounts; `mount` reports all 4 as sealed and read-only.
- Why now: preview flags that execute are a safety defect for terminal users; the false Spotlight fixes add 5 to `fix` in every run report.
- Related requirement: MEISTER-RELIABILITY-DASHBOARD criterion 1 (implemented, docs/requirements/MEISTER-RELIABILITY-DASHBOARD.md) — "Commands with a proven preview implementation use it; other mutations are blocked"; it covers the app's command policy, not preview flags typed in a terminal.
- Prior art in repo: the unknown-command rejection at MeisterAI.sh:10202-10207; the preview contract test at tests/cli_contract.bats:20-41 (`autofix --dry-run`, `ai --dry-run`); the prefix skip list at MeisterAI.sh:3829-3840 with its comment at :3826-3828; run_or_dry at MeisterAI.sh:947.

Impact:
- Callers of changed code (non-test): app/MeisterAI/Sources/Services/CommandPolicy.swift:66 sends `autofix|heal|orphans|simfix` with `--dry-run` as second argument and :68/:76 treat `free` as system-changing; /Users/a321/Developer/meister/Packages/MeisterKit/Sources/MeisterKit/Bash/MeisterBash.swift:108 sends `heal --dry-run` or `heal`; /Users/a321/Developer/meister/MeisterMacOS/BashModule.swift:46-138 sends `heal`, `free`, `simfix` and 9 legacy single-dash flags the CLI does not know (for example `-clearrecent`, `-moncon`), which change from exit 1 on stdout to exit 64 on stderr; /Users/a321/Developer/meister/MeisterMacOS/BashOutputView.swift:103 distinguishes only exit 0 from non-zero. `--capabilities-json` (MeisterAI.sh:616-618) keeps its `preview_commands` list unchanged.
- Test callers: 1 file, tests/cli_contract.bats (7 whole-script tests).
- Upstream (where input comes from): command-line arguments; `df -Hl` volume list at MeisterAI.sh:3871; `mdutil -s` output.
- Downstream (where output goes): process exit status and stderr; report ledger and ~/.meister/last.json (`fixes`, `fix`).
- Deploy unit: Homebrew formula maf4711/meister/meister.
- Deploy needed: yes — formula release through ./release.sh plus scripts/install-release.sh, run by the orchestrator after merge.

Scope:
- In scope: MeisterAI.sh (the heal, simfix, autofix and free dispatch blocks; the two unknown-option exits at :10042 and :10198; the skip list in module_spotlight_fix), meister.sh (regenerated with scripts/sync-twins.sh), tests/cli_contract.bats, new file tests/spotlight_fix.bats.
- Out of scope — do NOT replace the per-subcommand `if [ "${1:-}" = … ]` dispatch (MeisterAI.sh:455-9962) with a new argument parser — because 55 subcommands depend on it and tests/cli_contract.bats covers only 7 of their paths.
- Out of scope — do NOT change `remove`, `orphans`, `bloatware` or `tcc-clean` — because their confirmation and matching defects (MeisterAI.sh:7600-7643, :7773) need their own GOAL with their own tests.
- Out of scope — do NOT change the exit status 1 that a maintenance run returns when the report holds errors (MeisterAI.sh:10612-10613) or the exit status 69 of `ai` without a backend — because tests/cli_contract.bats:43-67 and both apps rely on them.
- Out of scope — do NOT edit scripts/homebrew-launcher.sh or the `--capabilities-json` output — because tests/test_startup_update.py pins the launcher's argument pass-through and app/MeisterAI/Sources/Services/CLIRunner.swift:49-54 reads the capability list; advertising new previews to the apps is a separate change.
- Out of scope — do NOT run `heal`, `simfix`, `autofix` or `free` without a preview flag in any test — because module_healer deletes files and moves LaunchAgent plists on the host through commands that PATH stubs do not intercept (MeisterAI.sh:4852-4887).
- Prefer: the message format and exit status of MeisterAI.sh:10205-10206 for every rejected argument over a new error format.

Acceptance criteria:
1. `heal`, `simfix` and `autofix` run as a preview when `-n` or `--dry-run` appears anywhere after the subcommand (for example `heal -n`, `simfix -n`, `autofix -y --dry-run`): the run invokes none of the mutating commands recorded by the stubs, and heal and autofix write a last.json with `dry_run` true and `profile` equal to the subcommand.
   Fails today: MeisterAI.sh:9943 and MeisterAI.sh:8002 accept only `--dry-run` as the second argument and MeisterAI.sh:8901 inspects only the second argument, so `heal -n` leaves DRY_RUN=false.
   Verify: `bats --tap tests/cli_contract.bats --filter "heal simfix autofix accept preview flags in any position"` → exit 0
2. `free -n` and `free --dry-run` print `[DRY-RUN] sudo purge` (and `[DRY-RUN] killall Finder Dock SystemUIServer` with `--restart-ui`), invoke neither sudo nor purge nor killall, and exit 0.
   Fails today: MeisterAI.sh:9917-9935 has no preview branch and never inspects arguments other than `--restart-ui`.
   Verify: `bats --tap tests/cli_contract.bats --filter "free preview runs no privileged command"` → exit 0
3. Error path: an unknown long option (`--bogus`), an unknown short option (`-Z`), and any argument of heal, simfix, autofix or free other than `-n`, `--dry-run`, `-y`, `--yes` and (free only) `--restart-ui` each exit 64, write `Unknown command or argument:` to stderr, write nothing to stdout, and leave last.json, history.log and the run lock untouched.
   Fails today: MeisterAI.sh:10042 writes to stdout and exits 1; MeisterAI.sh:10198 exits 1; MeisterAI.sh:9942-9944 ignores unknown heal arguments and acquires the run lock.
   Verify: `bats --tap tests/cli_contract.bats --filter "unknown options exit 64 on stderr"` → exit 0
4. module_spotlight_fix skips every volume under `/private/var/run/com.apple.security.cryptexd/`: no ERROR line, no `mdutil -E` call and no fix entry for such a volume, while a writable volume whose status contains "error" is still reindexed.
   Fails today: MeisterAI.sh:3829-3840 has no cryptexd prefix; observed 2026-11-15: 4 false fixes `Spotlight: /private/var/run/com.apple.security.cryptexd/mnt/… reindexiert` in ~/.meister/last.json.
   Verify: `bats --tap tests/spotlight_fix.bats --filter "cryptex mounts are skipped and real volumes still repaired"` → exit 0
5. No test is skipped or removed; the collected count in tests/cli_contract.bats grows by 3.
   Fails today: N/A — guard
   Verify: `bats --count tests/cli_contract.bats` → "10"
6. Existing tests still pass
   Verify: `bash scripts/check.sh` → exit 0

Edge cases:
  - `heal --dry-run` and `autofix --dry-run` as sent by both apps → still a preview (criterion 1, test (a))
  - a preview that prints DRY-RUN and exits before scanning → rejected: the test requires the scan output and the last.json of the preview (criterion 1, test (a))
  - `heal --bogus` → exit 64 before the run lock is acquired (criterion 3, test (c))
  - `free --restart-ui -n` → preview lists the UI restart, runs no killall (criterion 2, test (b))
  - `MeisterAI -n heal` → stays exit 64 as today (MeisterAI.sh:10203-10207; test (c))
  - `MEISTER_DIR` holding a live lock of another process → unknown options leave the lock file byte-identical (criterion 3, test (c))
  - `df` lists both a cryptexd mount and `/Volumes/Data` with an index error → 0 `mdutil -E` calls for the first, 1 for the second (criterion 4, test (d))

Tests to add (in tests/cli_contract.bats and tests/spotlight_fix.bats):
  (a) "heal simfix autofix accept preview flags in any position": for both twins and the argument lists `heal -n`, `heal --dry-run`, `heal -y --dry-run`, `simfix -n`, `simfix --dry-run`, `autofix -n`, `autofix -y --dry-run`, with PATH stubs that append to `$MEISTER_DIR/unexpected` and exit 99 only for mutating calls (`brew upgrade|reinstall|uninstall|cleanup|link`, every `sudo`, every `killall`, `launchctl unload|bootout|load`, `xcrun simctl shutdown|delete|erase`) and exit 0 with empty output for read-only calls each argument list in a fresh MEISTER_DIR → the file `unexpected` is absent; for heal and autofix `$MEISTER_DIR/last.json` has `dry_run` true and `profile` equal to the subcommand; stdout of `heal -n` contains `symlinks tally:`; stdout of `simfix -n` contains `DRY-RUN MODE` (simfix writes no last.json today, MeisterAI.sh:7998-8010, and keeps that)
  (b) "free preview runs no privileged command": `free -n`, `free --dry-run`, `free --restart-ui -n` with stubs for sudo, purge and killall → exit 0, `unexpected` absent, stdout contains `[DRY-RUN] sudo purge`; the third call also contains `[DRY-RUN] killall Finder Dock SystemUIServer`
  (c) "unknown options exit 64 on stderr": `--bogus`, `-Z`, `heal --bogus`, `simfix --bogus`, `autofix --bogus`, `free --bogus`, `-n heal` for both twins with a pre-seeded last.json, history.log and lock file → return code 64, stdout empty, stderr contains `Unknown command or argument:`, the three files byte-identical
  (d) in tests/spotlight_fix.bats, "cryptex mounts are skipped and real volumes still repaired": module_spotlight_fix extracted with the harness of tests/brew_retry_reporting.bats:18-21; `ps`, `df`, `mdutil`, `du`, `find`, `defaults` and `sudo` stubbed as shell functions; `df` lists `/private/var/run/com.apple.security.cryptexd/mnt/iOS_24A5370g` and `/Volumes/Data`; `mdutil -s` prints an error status for both; SPOTLIGHT_FIX_ENABLED=true, SPOTLIGHT_REINDEX_ON_ERROR=true, NEEDS_SUDO=true, SPOTLIGHT_MDS_CPU_THRESHOLD=999 → the sudo call log holds 0 lines containing `cryptexd` and exactly 1 line containing `mdutil -E /Volumes/Data`; the report holds 0 lines containing `cryptexd`

Example:
  - Input: `MeisterAI heal -n` in a terminal.
  - Output: stdout shows `[DRY-RUN MODE — no changes]` and the healer's scan lines; no sudo prompt appears; nothing changes outside ~/.meister; ~/.meister/last.json has `"dry_run": true`. Input `MeisterAI --bogus` → stderr `[ERROR] Unknown command or argument: --bogus (see MeisterAI -h)`, stdout empty, exit status 64.

Interface:
- New names: none, behaviour change only.
- Signatures / schema: rejected arguments use the existing message `[ERROR] Unknown command or argument: <arg> (see MeisterAI -h)` on stderr with exit status 64; accepted arguments after heal, simfix and autofix are `-n`, `--dry-run`, `-y`, `--yes`; after free additionally `--restart-ui`; preview lines of free are `[DRY-RUN] sudo purge` and `[DRY-RUN] killall Finder Dock SystemUIServer`; skip-list entry `/private/var/run/com.apple.security.cryptexd|/private/var/run/com.apple.security.cryptexd/*` in the style of MeisterAI.sh:3830.
- Unchanged: the meaning of `-n`, `--dry-run`, `--restart-ui`, `-y`; exit status 0 of a successful subcommand; exit status 69 and 2 pinned in tests/cli_contract.bats:43-67 and :121-127; the last.json schema; the `--capabilities-json` output.

Constraints:
- Reuse: the whole-script harness with PATH stubs at tests/cli_contract.bats:95-112; run_or_dry (MeisterAI.sh:947) for guarded commands; the function-extraction harness at tests/brew_retry_reporting.bats:18-21.
- Dependencies: no new dependencies.
- Limits: each whole-script test call uses a subprocess timeout of 20 s like tests/cli_contract.bats:81; the three new contract tests together add at most 120 s to the bats suite.
- Workflow: base origin/main; fresh worktree; no env bootstrap beyond the tools scripts/check.sh:7 requires; edit MeisterAI.sh, then run `bash scripts/sync-twins.sh`; one PR for this GOAL; one commit per green criterion.
- Test command: `bash scripts/check.sh`
- Forbidden actions: no push, no PR, no ./release.sh, no run of `heal`, `simfix`, `autofix` or `free` without a preview flag (neither in tests nor by hand), no writes under ~/.meister.
- Style: the argument checks stay inside the four dispatch blocks; no new file besides tests/spotlight_fix.bats.

Risk & rollback:
- What breaks if wrong: a preview flag matched too broadly turns a real `heal` into a preview and the user believes repairs ran; the native app's 9 unknown legacy flags (BashModule.swift) change from exit 1 on stdout to exit 64 on stderr and its output pane then shows the message from stderr.
- Rollback: git revert of the merge commit plus a formula release; no state migration.
- Proof in production: `MeisterAI heal -n` prints `[DRY-RUN MODE — no changes]`; after the next `MeisterAI --auto`, ~/.meister/last.json has 0 `fixes` entries containing `cryptexd`.

Open questions / assumptions:
- Assume exit status 64 for unknown options suits both apps: BashOutputView.swift:103 and LogView.swift:22-27 only distinguish 0 from non-zero, and no script, LaunchAgent or test in either repo relies on exit status 1 for an unknown option.
- Assume every mount under /private/var/run/com.apple.security.cryptexd/ is a sealed read-only system cryptex (observed with `mount`: SimulatorRuntime, iOS_24A5370g, tvOS_24J5315h) for which a Spotlight index is not expected.

Report back:
  - per acceptance criterion: the Verify command run and its quoted output
  - the RED run: the four new tests failing before the change (quoted bats lines)
  - `git diff origin/main...HEAD --stat` and the branch name; no push, no PR, no release
```

## Recap

GOAL 1 repairs cask upgrades blocked by stale Caskroom artifacts and reports a fix only after a readback. GOAL 2 adds a run-end pass that reviews the open findings and repairs those with a registered repairer. GOAL 3 makes preview flags and unknown options behave as documented and stops false Spotlight fixes.
