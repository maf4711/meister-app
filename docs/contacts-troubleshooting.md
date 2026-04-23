# Contacts Troubleshooting — Apr 22–23, 2026

Complete record of the AddressBook bloat + iCloud sync loop incident and its resolution.

## TL;DR

- **Problem:** AddressBook grew to 2.8 GB. iCloud sync was in a destructive loop, about to delete 2337 contacts from the server.
- **Fix:** Disabled iCloud Contacts sync, exported contacts as vCard, deleted the bloated source from disk, let macOS recreate a clean source, reimported the vCard.
- **Result:** AddressBook 85 MB (−2.7 GB). Contacts intact on Mac (2577) and server (2587). Sync running sauber again.

## Timeline

| Date / Time | Event |
|---|---|
| **2026-04-22 18:32** | iCloud sync ran migration/merge. migration.log: "Local People: 2580, Server People: 2375, Merged 2375, **Removed People: 2337**, Local People Upload: 2580" → "UPLOAD TO https://foellmer%40mac.com@p102-contacts.icloud.com/132400407/carddavhome/card/". The destructive UPLOAD pushed local contacts to server, overwriting the 2337 server-only entries. |
| **2026-04-22 (later)** | User noticed AddressBook bloat (~1 GB at that point, per memory note). |
| **2026-04-23 morning** | User disabled iCloud Contacts sync in System Settings (`Enabled = 0` in MobileMeAccounts). |
| **2026-04-23 ~09:58** | First cleanup attempt — source moved to Trash → Contacts.app showed "Keine Kontakte" → source restored from Trash. |
| **2026-04-23 ~10:15** | Discovered orphan source `7E7C3705` existed separately. `C5B29763` (foellmer iCloud) had grown further to 2.4 GB. |
| **2026-04-23 ~10:25** | User exported all contacts: vCard (107 MB, 2603 contacts) + .abbu archive (2.8 GB — contains full AddressBook dir incl. bloat). |
| **2026-04-23 ~10:32** | `contactsd` killed, `C5B29763` + `ABAssistantChangelog.*` moved to Trash. AddressBook shrunk to 108 MB. |
| **2026-04-23 ~10:35** | Contacts.app opened → macOS auto-recreated `C5B29763` as fresh (76 MB) empty iCloud source. |
| **2026-04-23 ~10:37** | vCard reimported via Finder double-click → "2603 duplicates will be updated" → photos embedded back into contacts. |
| **2026-04-23 ~10:41** | Orphan source `7E7C3705` moved to Trash. |
| **2026-04-23 ~10:50** | macOS silently reactivated `Enabled = 1` for CONTACTS service (automatic behavior after source recreation). Server 2611 → 2587 contacts; Mac 2605 → 2577 (sync converging). |
| **2026-04-23 ~11:00** | Final verification: AddressBook 85 MB, sync running cleanly, no destructive loop. User decided to leave sync enabled. |

## Root cause

Two Apple IDs in play:
- **foellmer@mac.com** — old Apple ID, still logged in as iCloud account on this Mac (can NOT be signed out due to attached services: Mail, Notes, Calendar, Reminders, Bookmarks, Keychain Sync, Find My Mac).
- **marco@merados.com** — primary email, NOT a separate iCloud account.

Over time `C5B29763` (foellmer's iCloud CardDAV source) accumulated:
- **729 MB ACHANGE-History** in the DB (change log never pruned)
- **1.4 GB `_EXTERNAL_DATA`** (4204 contact photo files, many orphaned)
- **1 GB abcddb** file

A sync divergence developed (2580 local vs 2375 server). When sync ran on Apr 22, the merge logic decided to UPLOAD the full local state to the server, overwriting the 2337 server-side contacts that weren't present locally.

## What the constraints ruled out

- **Signing out the Apple ID** — rejected by user ("kann den account nicht abmelden, das ist kein spielzeug") because too many services attached.
- **Importing the .abbu archive** — would restore the entire AddressBook folder including all bloat; it's a 1:1 archive, not a contact-only export. Must use .vcf for clean reimport.
- **Deleting `_EXTERNAL_DATA` files directly** — risk of losing legitimate contact photos. Better to rebuild the source.

## The working recipe

For future reference if this happens again:

```bash
# 1. Disable iCloud Contacts in System Settings → Apple Account → iCloud
#    (Do this first, don't skip — stops any active sync from interfering)

# 2. Export contacts from Contacts.app:
#    Cmd+A to select all → Ablage → Exportieren → vCard
#    Save as contacts-backup-YYYY-MM-DD.vcf
#    Also export Kontaktarchiv (.abbu) as nuclear fallback

# 3. Quit Contacts.app, kill contactsd
osascript -e 'tell application "Contacts" to quit'
sleep 2
kill $(pgrep contactsd)

# 4. Move bloated source + changelog to Trash (not rm — keep 30-day rollback)
TS=$(date +%Y%m%d-%H%M%S)
mv ~/Library/Application\ Support/AddressBook/Sources/<BLOATED_UUID> \
   ~/.Trash/AddressBook-Source-bloat-$TS
mv ~/Library/Application\ Support/AddressBook/ABAssistantChangelog.aclcddb* \
   ~/.Trash/

# 5. Reopen Contacts.app → macOS recreates the source (empty, ~76 MB)
open -a Contacts

# 6. Double-click the .vcf in Finder → "Duplicates will be updated" → confirm
#    (Do NOT re-import the .abbu — it contains the bloat)

# 7. Verify
du -sh ~/Library/Application\ Support/AddressBook/
defaults read MobileMeAccounts Accounts | grep -B 1 "Name = CONTACTS"
```

### Important gotcha

macOS will automatically reactivate `Enabled = 1` for the CONTACTS service after recreating the source. If you want to keep sync disabled, check after the process completes and toggle off again in System Settings.

## Diagnostic commands

Identify which source is bloated:
```bash
for dir in ~/Library/Application\ Support/AddressBook/Sources/*/; do
  du -sh "$dir"
done
```

Find out which Apple ID owns a source:
```bash
tail -5 ~/Library/Application\ Support/AddressBook/Sources/<UUID>/migration.log
# Look for "UPLOAD TO https://..." — the email is in the URL
```

Count contacts in a source DB:
```bash
sqlite3 ~/Library/Application\ Support/AddressBook/Sources/<UUID>/AddressBook-v22.abcddb \
  "SELECT COUNT(*) FROM ZABCDRECORD;"
```

Check sync-enabled state:
```bash
defaults read MobileMeAccounts Accounts | grep -B 1 "Name = CONTACTS"
# Enabled = 0 → sync off
# Enabled = 1 → sync on
```

Spot CPU-hog during reindex:
```bash
ps aux | sort -k3 -rn | head -5
# If corespotlightd at 80%+ → it's reindexing AddressBook after a large change
```

## File inventory (this folder)

| File | Size | What it is |
|---|---|---|
| `contacts-backup-2026-04-23.vcf` | 107 MB | The working backup. 2603 contacts with embedded photos. Use this to reimport if anything breaks. |
| `contacts-backup-2026-04-23.abbu` | 2.8 GB | Nuclear fallback. Full 1:1 snapshot of the AddressBook folder at the moment of export, **including the 2.4 GB of bloat**. Don't reimport unless desperate — it would restore the bloat. |
| `foellmer-migration.log` | 5.6 MB | The full migration log from source `C5B29763`. Ends with the destructive "UPLOAD TO carddavhome" that caused the issue. Evidence of what happened. |
| `final-state-snapshot.txt` | small | Disk sizes and sync state at 2026-04-23 ~11:01. |
| `README.md` | this file | This documentation. |

## Final state (2026-04-23 ~11:01)

- AddressBook total: **85 MB** (was 2.8 GB)
- Active source: `C5B29763` (76 MB, freshly recreated by macOS after deletion)
- Mac contacts: 2577
- iCloud server contacts: 2587 (verified via icloud.com/contacts)
- iCloud Contacts sync: **Enabled = 1** (auto-reactivated by macOS, user chose to keep)
- Apple ID foellmer@mac.com: **unchanged**, all services intact
- Rollback available 30 days: `~/.Trash/AddressBook-Source-foellmer-20260423-103253/` and `~/.Trash/AddressBook-Source-orphan-20260423-104146/`

## If something breaks later

1. **Contacts disappear on Mac:** Double-click `contacts-backup-2026-04-23.vcf` in Finder → reimports everything.
2. **iCloud sync starts looping destructively again:** Disable iCloud Contacts sync immediately in System Settings. Server data on icloud.com is the source of truth until fixed.
3. **Need the exact pre-cleanup state:** Restore `contacts-backup-2026-04-23.abbu` — but you'll be back at 2.8 GB.
4. **Source folder corrupted:** Drag contents from Trash folders (within 30 days) back to `~/Library/Application Support/AddressBook/Sources/`.

## Cleanup deadlines

- **Trash auto-empties after 30 days**: `AddressBook-Source-foellmer-*` and `AddressBook-Source-orphan-*` in `~/.Trash/` disappear around **2026-05-23**. If you want longer recovery, move them to this folder.
- **`.abbu` nuclear backup**: Safe to delete after 1-2 weeks of stable operation if Mac + iPhone + iPad all sync normally. Deleting frees 2.8 GB.
- **`.vcf` backup**: Keep indefinitely — small (107 MB) and the only clean reimport path.
