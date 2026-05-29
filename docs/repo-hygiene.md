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

## fixtures/ Decision (Task 5.2)

**Decision: Option B — Keep in-repo with documentation.**

Rationale (after investigation):

- Total size: 22 MiB (dominated by two generated MP4s: `largevideo_0.mp4` ~8.8 MiB, `RPReplay_Final_20260419_031500.mp4` ~11 MiB). Remaining ~20 JPG/PNG files are small (<200 KiB each).
- "Small" threshold for LFS or separate test-fixtures repo **not met** (22 MiB is material relative to the entire ~20 MiB pack).
- All content is *generated* deterministically by `scripts/seed_photos.py` (fixed random.seed(42), ffmpeg testsrc, PIL). It can be regenerated on demand for iOS simulator seeding (`xcrun simctl addmedia`).
- Moving to LFS would add operational complexity (LFS tracking, every dev/CI setup, pointer files) with little gain for regeneratable test data.
- A separate fixtures repo would fragment the project and add clone/fetch steps for a tiny test set.
- Per plan rule: "Do the move only if small."

**Action taken:** No files moved. No LFS. Added `.gitattributes` containing a clear comment block documenting the decision and usage (see `.gitattributes`).

Future: If fixtures grow substantially or the generator is removed, prefer deleting the large media + on-demand regeneration (in test/CI setup) over introducing LFS.

## CI/Build Guard (Task 5.3 — Stretch)

Minimal guard script: `scripts/verify-no-build-artifacts.sh`

- Fails (exit 1) if any `.app`, `.ipa`, `*.dSYM`, `*.xcarchive` appear in the tree.
- Zero dependencies, ~30 lines, POSIX-ish bash.
- Run manually: `scripts/verify-no-build-artifacts.sh`
- Intent: local safety net + ready for CI wiring. (Stretch — not wired into any workflow yet.)
- Follows "minimal guard" preference: documentation first, tiny automation second.

## Related Files

- `.gitignore`
- `.gitattributes` (fixtures policy + decision comment)
- `scripts/seed_photos.py` (the fixture generator — source of truth)
- `scripts/verify-no-build-artifacts.sh` (this guard)
- `README.md` (mentions fixtures/ for iOS test images)
