#!/bin/bash
# verify-no-build-artifacts.sh
# Meister Track 5.3 (P2) — minimal CI/build guard.
# Fails if any Xcode build artifacts (.app, .ipa, dSYM, xcarchive, etc.)
# appear anywhere in the working tree.
#
# Usage: scripts/verify-no-build-artifacts.sh
# Exit 0 = clean, Exit 1 = artifacts found (prints them).
#
# Intentionally tiny. No dependencies. Run manually or from CI.
# See docs/repo-hygiene.md

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Patterns from plan + common Xcode outputs
FOUND=$(find . \
  -type d \( -name '*.app' -o -name '*.dSYM' -o -name '*.xcarchive' \) \
  -o -type f -name '*.ipa' \
  2>/dev/null | grep -v '^./.git/' || true)

if [ -n "$FOUND" ]; then
  echo "❌ Build artifacts detected in tree (forbidden by repo hygiene policy):" >&2
  echo "$FOUND" >&2
  echo "Fix: clean your build dirs or add proper ignores. See .gitignore and docs/repo-hygiene.md" >&2
  exit 1
fi

echo "✅ OK: no build artifacts (.app/.ipa/dSYM/xcarchive) in tree."
exit 0
