#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
: "${CODE_SIGN_IDENTITY:?Set CODE_SIGN_IDENTITY to your Developer ID Application certificate}"
"$ROOT/scripts/build-app.sh" release

APP="$ROOT/dist/Nabira.app"
NABIRA_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="$ROOT/dist/Nabira-$NABIRA_VERSION.dmg"
codesign --verify --deep --strict --verbose=2 "$APP"
rm -f "$DMG"
hdiutil create -volname Nabira -srcfolder "$APP" -ov -format UDZO "$DMG"
codesign --force --sign "$CODE_SIGN_IDENTITY" --timestamp "$DMG"

if [[ -n "${NOTARYTOOL_PROFILE:-}" ]]; then
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARYTOOL_PROFILE" --wait
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
else
  echo "DMG signed but not notarized. Set NOTARYTOOL_PROFILE to submit and staple it."
fi

echo "$DMG"
