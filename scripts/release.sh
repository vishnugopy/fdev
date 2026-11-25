#!/bin/bash
# Build, sign with Developer ID, notarize with Apple, staple, and package fdev.dmg.
#
# One-time setup (stores an app-specific password in your keychain):
#   xcrun notarytool store-credentials fdev-notary --apple-id YOUR_APPLE_ID --team-id 35B5AAV8X8
#   (create the app-specific password at https://account.apple.com → Sign-In and Security)
set -euo pipefail
cd "$(dirname "$0")/.."

PROFILE="${NOTARY_PROFILE:-fdev-notary}"
APP="build/fdev.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist" 2>/dev/null || echo "")

IDENTITY=$(security find-identity -v -p codesigning | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"')
[ -n "$IDENTITY" ] || { echo "No 'Developer ID Application' certificate in the keychain."; exit 1; }

./build.sh
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")

echo "→ Signing with $IDENTITY (hardened runtime + secure timestamp)"
codesign --force --deep --options runtime --timestamp --sign "$IDENTITY" "$APP"
codesign --verify --strict --verbose=2 "$APP"

echo "→ Notarizing the app"
ditto -c -k --keepParent "$APP" build/fdev-notarize.zip
xcrun notarytool submit build/fdev-notarize.zip --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP"
rm build/fdev-notarize.zip

echo "→ Building the disk image"
STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
DMG="build/fdev-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "fdev $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"

echo "→ Notarizing the disk image"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"

spctl --assess --type open --context context:primary-signature -v "$DMG"
spctl --assess --type execute -v "$APP"
echo "✓ Ready: $DMG"
