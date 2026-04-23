#!/bin/bash
# Manually build a distribution-signed IPA from the xcarchive, bypassing
# xcodebuild -exportArchive (broken in Xcode-beta 26.x due to rsync 3.4 flag).

set -euo pipefail
cd "$(dirname "$0")/.."

ARCHIVE=build/MeisterIOS.xcarchive
APP="$ARCHIVE/Products/Applications/MeisterIOS.app"
APPEX="$APP/PlugIns/MeisterWidget.appex"
STAGE=build/stage
IPA_PATH=build/ipa/MeisterIOS.ipa
PROF_DIR="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
DIST_IDENT="Apple Distribution: Marco Foellmer (K63X3ZTV3Q)"
APP_PROF="$PROF_DIR/cd8a9e93-68d4-4fff-a09f-2ff3b1485849.mobileprovision"
EXT_PROF="$PROF_DIR/24e692da-bd73-4eaf-8dc8-25a44afc6e85.mobileprovision"

[ -d "$APP" ] || { echo "archive missing — run xcodebuild archive first"; exit 1; }

echo "══ 1/4  Staging"
rm -rf "$STAGE" build/ipa
mkdir -p "$STAGE/Payload"
ditto "$APP" "$STAGE/Payload/MeisterIOS.app"

echo "══ 2/4  Embedding profiles"
cp "$APP_PROF" "$STAGE/Payload/MeisterIOS.app/embedded.mobileprovision"
cp "$EXT_PROF" "$STAGE/Payload/MeisterIOS.app/PlugIns/MeisterWidget.appex/embedded.mobileprovision"

echo "══ 3/4  Re-signing with Distribution cert"
# Extract entitlements from provisioning profile into temp file
APP_ENT=$(mktemp -t app-ent).plist
EXT_ENT=$(mktemp -t ext-ent).plist
security cms -D -i "$APP_PROF" 2>/dev/null \
    | plutil -extract Entitlements xml1 -o "$APP_ENT" -
security cms -D -i "$EXT_PROF" 2>/dev/null \
    | plutil -extract Entitlements xml1 -o "$EXT_ENT" -

# Sign extension first, then outer app
/usr/bin/codesign --force --sign "$DIST_IDENT" \
    --entitlements "$EXT_ENT" \
    --preserve-metadata=identifier,flags,runtime \
    --generate-entitlement-der \
    "$STAGE/Payload/MeisterIOS.app/PlugIns/MeisterWidget.appex"

/usr/bin/codesign --force --sign "$DIST_IDENT" \
    --entitlements "$APP_ENT" \
    --preserve-metadata=identifier,flags,runtime \
    --generate-entitlement-der \
    "$STAGE/Payload/MeisterIOS.app"

rm -f "$APP_ENT" "$EXT_ENT"

# Verify
codesign --verify --deep --strict "$STAGE/Payload/MeisterIOS.app" 2>&1 | head -3 || true
codesign -dv --verbose=1 "$STAGE/Payload/MeisterIOS.app" 2>&1 | grep -E "TeamIdentifier|Authority" | head -3

echo "══ 4/4  Zipping IPA"
mkdir -p build/ipa
(cd "$STAGE" && /usr/bin/zip -qr "../../$IPA_PATH" Payload)
ls -lh "$IPA_PATH"
echo "Ready: $IPA_PATH"
