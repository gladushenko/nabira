#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
CONFIGURATION="${1:-release}"
SCRATCH="${NABIRA_BUILD_DIR:-/tmp/nabira-spm-build}"
swift build --package-path "$ROOT" --scratch-path "$SCRATCH" -c "$CONFIGURATION"

STAGE="$(mktemp -d /tmp/nabira-app.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT
APP="$STAGE/Nabira.app"
FINAL_APP="$ROOT/dist/Nabira.app"
BIN="$SCRATCH/$CONFIGURATION/Nabira"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Nabira"
/usr/libexec/PlistBuddy -c "Clear dict" "$APP/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string Nabira" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string com.nabira.app" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleName string Nabira" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string Nabira" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string APPL" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string 1.0.0" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleVersion string 1" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :LSMinimumSystemVersion string 14.0" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :LSUIElement bool true" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :NSHumanReadableCopyright string 'Copyright © 2026 Nabira'" "$APP/Contents/Info.plist"
xattr -cr "$APP"
SIGNING_IDENTITY="${CODE_SIGN_IDENTITY:--}"
if [[ "$SIGNING_IDENTITY" == "-" ]]; then
    # Keep the local development build recognizable to macOS privacy services
    # after its executable changes. A certificate-signed release gets its
    # normal designated requirement from the signing identity instead.
    codesign --force --deep --sign - \
        --identifier com.nabira.app \
        --requirements '=designated => identifier "com.nabira.app"' \
        "$APP"
else
    codesign --force --deep --sign "$SIGNING_IDENTITY" "$APP"
fi
mkdir -p "$ROOT/dist"
rm -rf "$FINAL_APP"
ditto --noextattr --noqtn "$APP" "$FINAL_APP"
echo "$FINAL_APP"
