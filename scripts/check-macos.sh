#!/bin/bash
# Local, non-destructive validation. Mutation tests use temporary fixtures.
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/ensure-design-system.sh
xcodegen generate
swift test --package-path Packages/MeisterKit
xcodebuild -project Meister.xcodeproj -scheme MeisterMacOS \
  -destination 'platform=macOS' \
  -derivedDataPath "${MEISTER_DERIVED_DATA:-build/validation}" \
  test CODE_SIGNING_ALLOWED=NO
git diff --check
