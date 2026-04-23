#!/bin/bash
# Ship a new build to TestFlight end-to-end:
#   1. Auto-bump build number to (latest_on_asc + 1)
#   2. Regenerate Xcode project
#   3. Archive (Release, iOS device)
#   4. Build distribution-signed IPA (manual, bypasses the Xcode-beta rsync bug)
#   5. Upload via altool
#   6. Wait for Apple processing, set export compliance, attach to Internal group
#   7. Optionally set "What to Test" release notes

set -euo pipefail
cd "$(dirname "$0")/.."

NOTES="${1:-}"   # First arg: release notes (optional). Empty skips.

echo "══ 0/6  Resolving next build number"
NEXT=$(python3 scripts/asc_client.py next-build-number)
echo "   → build $NEXT"

echo "══ 1/6  Updating project.yml"
sed -i '' "s/CURRENT_PROJECT_VERSION: \".*\"/CURRENT_PROJECT_VERSION: \"$NEXT\"/" project.yml
xcodegen generate | tail -2

echo "══ 2/6  Archiving"
rm -rf build
xcodebuild \
    -project Meister.xcodeproj \
    -scheme MeisterIOS \
    -configuration Release \
    -destination "generic/platform=iOS" \
    -archivePath build/MeisterIOS.xcarchive \
    -allowProvisioningUpdates \
    DEVELOPMENT_TEAM=K63X3ZTV3Q \
    archive 2>&1 | grep -E "ARCHIVE (SUCCEEDED|FAILED)|error:"

echo "══ 3/6  Building IPA"
./scripts/build_ipa.sh | tail -3

echo "══ 4/6  Uploading to App Store Connect"
xcrun altool --upload-app \
    -f build/ipa/MeisterIOS.ipa -t ios \
    -u foellmer@mac.com -p '@keychain:MEISTER_ASC' \
    --asc-provider K63X3ZTV3Q 2>&1 | tail -5

echo "══ 5/6  Activating"
if [ -n "$NOTES" ]; then
    python3 scripts/asc_client.py activate --version "$NEXT" --notes "$NOTES"
else
    python3 scripts/asc_client.py activate --version "$NEXT"
fi

echo "══ Done. Build $NEXT live on TestFlight."
