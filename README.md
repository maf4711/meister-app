# Meister for iPhone

On-device iOS maintenance app — photo dedup, contact cleanup, calendar archive,
storage dashboard. Zero upload, zero account, 100% local.

## Build

```bash
brew install xcodegen      # one-time
xcodegen                    # produces MeisterIOS.xcodeproj
open MeisterIOS.xcodeproj
```

Set your signing team in Xcode, then **Run** on device or simulator (iOS 17+).

## Feature map

| Area | Module | What it does |
|---|---|---|
| Photos | `PhotoScanner` | Fetches library metadata, no iCloud downloads |
|  | `DuplicateDetector` | pHash-based near-duplicate clustering |
|  | `ScreenshotDetector` | Screenshots + screen recordings (stock app) |
|  | `BlurDetector` | Laplacian variance over thumbnails |
|  | `LargeMediaFinder` | Top-N / >100 MB filter |
| Contacts | `PhoneNormalizer` | E.164 normalization (DE default, overrideable) |
|  | `FuzzyMatcher` | Jaccard + Levenshtein name similarity |
|  | `ContactDeduplicator` | 3-way union-find dedup (phone / email / name) |
|  | `ContactBackup` | vCard export to Documents/backups |
|  | `ContactScanner.merge` | Best-quality winner, phones/emails moved, losers deleted |
| Calendar | `CalendarScanner` | Old events + empty calendars + completed reminders |
| Storage | `StorageReader` | Device free/total + app cache size |
| Diagnostics | `HardwareInfo` | Device/OS/thermal/battery |
|  | `NetworkMonitor` | Path status + Cloudflare speed test |
| Widget | `MeisterStorageWidget` | Home Screen + Lock Screen gauge |
| Siri | `CleanPhotosIntent` | "Hey Siri, clean my photos in Meister" |

## Design principles

- **Backup before destruction.** Every delete path has a backup or uses
  iOS's "Recently Deleted" — never silent destruction.
- **Quality-score wins merges.** For contacts we keep the most complete
  record and transplant phone/email from duplicates before deleting them.
- **No ML upload.** pHash + Core Image + Vision (when added) run locally.
- **iCloud-aware.** Uses `PHPhotoLibrary.performChanges` so deletes sync
  to iCloud Photos and respect the user's choice there.

## What's intentionally not here (iOS sandbox)

- No "RAM booster" (iOS manages memory; the buttons in other apps are theater).
- No system cache cleanup (not accessible from a regular app).
- No battery cycle count (private API, App Store rejection).
- No access to other apps' data.

## Next up (Post-MVP)

- **Vision-based similarity**: cluster by feature-print for truly similar (not just pHash-close) images.
- **Video compression**: AVFoundation export session, HEVC, preserves metadata.
- **Live Activity** during long scans (Dynamic Island).
- **Shortcuts**: `Clean Screenshots`, `Backup Contacts`, `Free Up Space` intents.
- **Gamification**: streaks for daily cleanup.
- **Undo**: 30-day trash for contact deletes.
