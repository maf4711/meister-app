#!/bin/bash
# Archive + upload MeisterIOS to App Store Connect TestFlight.
#
# Prerequisites (one-time setup):
#   1. Signed in to Xcode with foellmer@mac.com (Xcode > Settings > Accounts).
#   2. Either:
#        a) App-specific password from https://appleid.apple.com/account/manage
#           → stored in keychain:  xcrun altool --store-password-in-keychain-item "MEISTER_ASC" -u foellmer@mac.com -p <password>
#      OR b) App Store Connect API key (.p8, Key ID, Issuer ID)
#           → ~/.appstoreconnect/private_keys/AuthKey_<KEYID>.p8
#
# Usage:   ./scripts/deploy_testflight.sh [build_number]

set -euo pipefail

cd "$(dirname "$0")/.."

BUILD="${1:-$(date +%Y%m%d%H%M)}"
SCHEME="MeisterIOS"
ARCHIVE_PATH="build/MeisterIOS.xcarchive"
IPA_PATH="build/ipa"
APPLE_ID="foellmer@mac.com"
TEAM_ID="K63X3ZTV3Q"

echo "══ 1/4  Bumping build number to $BUILD"
/usr/libexec/PlistBuddy -c "Set :CURRENT_PROJECT_VERSION $BUILD" project.yml 2>/dev/null || \
    sed -i '' "s/CURRENT_PROJECT_VERSION: \".*\"/CURRENT_PROJECT_VERSION: \"$BUILD\"/" project.yml
xcodegen generate

echo "══ 2/4  Archiving"
rm -rf "$ARCHIVE_PATH" "$IPA_PATH"
xcodebuild \
    -project MeisterIOS.xcodeproj \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination "generic/platform=iOS" \
    -archivePath "$ARCHIVE_PATH" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    archive | xcbeautify --quieter 2>/dev/null || \
xcodebuild \
    -project MeisterIOS.xcodeproj \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination "generic/platform=iOS" \
    -archivePath "$ARCHIVE_PATH" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    archive

echo "══ 3/4  Exporting IPA"
xcodebuild \
    -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$IPA_PATH" \
    -exportOptionsPlist ExportOptions.plist

echo "══ 4/4  Upload to App Store Connect"
IPA_FILE=$(find "$IPA_PATH" -name "*.ipa" -print -quit)
if [ -z "$IPA_FILE" ]; then
    echo "ERROR: IPA not found"; exit 1
fi

if [ -n "${ASC_API_KEY_ID:-}" ] && [ -n "${ASC_API_ISSUER_ID:-}" ]; then
    xcrun altool --upload-app -f "$IPA_FILE" -t ios \
        --apiKey "$ASC_API_KEY_ID" --apiIssuer "$ASC_API_ISSUER_ID"
else
    xcrun altool --upload-app -f "$IPA_FILE" -t ios \
        -u "$APPLE_ID" -p "@keychain:MEISTER_ASC"
fi

echo "══ Done. Build $BUILD uploaded. Processing on App Store Connect takes 5-15 min."
echo "  Watch: https://appstoreconnect.apple.com/apps"
