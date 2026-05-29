# Repo Hygiene & Artifact Policy

**Track 5 (P2) — Meister Remediation Program**

## Build Artifact History Problem

`build/` artifacts (Xcode `.xcarchive`, `.ipa` packages, `.app` bundles, `dSYM` debug symbols, staging dirs) were once committed during early development.

This caused:

- Bloated repository size and slow clones/fetches.
- Irrelevant binary noise in `git log` and diffs.
- Risk of accidentally checking in local machine-specific or secret-containing build products.

## Current .gitignore Rules (Prevention)

The following patterns in `.gitignore` block build outputs:

```
# Xcode
*.xcodeproj
xcuserdata/
DerivedData/
*.xcuserstate
build/

# Swift Package Manager
Packages/
.build/
.swiftpm/
Package.resolved

# ... (plus Python caches, .claude/, .worktrees/ etc.)
```

Local build scripts (`scripts/build_ipa.sh`, `scripts/ship.sh`, `scripts/deploy_testflight.sh`) intentionally write to `build/` — this directory must never be committed.

## Recommendation: Do Not Rewrite History

**Never run `git filter-branch`, `git filter-repo`, or BFG Repo-Cleaner** to purge historical build artifacts unless the repository is still this small (~20 MiB pack).

Reasons:

- The pack is already tiny; the benefit is negligible.
- Rewrites invalidate every existing clone and fork.
- Force-pushes after filter-branch are destructive and error-prone.
- Prevention via .gitignore + this policy is sufficient and cheaper.

If the repo ever grows significantly *and* build binaries are discovered in deep history, re-evaluate only then — and only with full team consensus and backup.

---

*This document will be extended for fixtures/ policy (Task 5.2) and guard (Task 5.3) in subsequent commits.*
