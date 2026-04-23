# Meister v1.0.0

**First public multi-platform release.**

## Highlights

- **bash-meister CLI** v5.6 is the feature master (via `maf4711/homebrew-meister` tap).
- **Native macOS app** (`Meister.app`) shells out to bash-meister for every maintenance module, plus native Swift for AddressBook cleanup.
- **iOS + iPadOS universal app** (MeisterIOS) with Mac Catalyst support — 1 codebase, 3 Apple platforms.
- **Shared Swift engine** in `Packages/MeisterKit` (AddressBookScanner, AddressBookCleanup, ContactExporter, SyncStateInspector).
- 36 bash-backed modules surfaced in the Mac GUI (Health, Heal, Disk, Battery, Thermal, Wi-Fi, Ports, DNS, Certs, Simfix, Dotfiles, Large Files, Caches, Rosetta, …).

## Architecture

```
     maf4711/homebrew-meister (bash v5.6)  ◄── feature master
                │
          shell-out
                │
     ┌──────────▼──────────┐    ┌────────────────────┐
     │   Meister for Mac   │    │  Meister for iOS   │
     │   Meister.app       │    │  + iPadOS + CT     │
     └─────────────────────┘    └────────────────────┘
```

## Install

### Terminal (required — apps shell out to it)

```bash
brew tap maf4711/meister
brew install meister
```

### macOS app

```bash
# once cask is tapped:
brew tap maf4711/meister
brew install --cask meister-mac
```

### iOS + iPadOS

Via TestFlight once the build clears Apple review. Public link will be added to repo after first successful upload.

## Known limitations in v1.0.0

- **Binary signed with Apple Development cert**, not "Developer ID Application". That means the included `.zip` will only launch on the build machine. External distribution requires re-signing with a Developer ID cert and Apple notarization. See `docs/release-process.md` (to be added in v1.0.1) for the full notarization flow.
- **No iOS TestFlight upload yet.** `./scripts/ship.sh` is ready; needs App Store Connect credentials in the `MEISTER_ASC` keychain entry.
- **Cask formula uses placeholder sha256** — gets updated when the notarized zip is attached to a later release.

## Repository

- `maf4711/meister-app` — this repo (Mac/iOS/iPad apps + shared Swift library)
- `maf4711/homebrew-meister` — bash CLI + tap, where the Cask formula lives

## Changelog from the pre-restructure baseline

- multi-platform monorepo: iOS+iPad+macOS+CLI (commit `ca3ccfd`)
- bash-meister v5.6 confirmed as feature master; Swift-CLI experiment removed (commit `4087652`)
- full 36-module bash coverage in Mac GUI + destructive guards (commit `8ba2409`)
- macOS target decoupled from iOS sources + v1.0.0 bump (commit `39307b0`)
