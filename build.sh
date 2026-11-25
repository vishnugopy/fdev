#!/bin/zsh
# Builds fdev.app (menu-bar app, no Dock icon) into ./build
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP=build/fdev.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/fdev "$APP/Contents/MacOS/fdev"

# App icon
ICONSET=build/AppIcon.iconset
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
"$APP/Contents/MacOS/fdev" --render-icon build/icon_1024.png
for s in 16 32 128 256 512; do
  sips -z $s $s build/icon_1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) build/icon_1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>fdev</string>
  <key>CFBundleDisplayName</key><string>fdev</string>
  <key>CFBundleIdentifier</key><string>local.frontkit.app</string>
  <key>CFBundleExecutable</key><string>fdev</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.4</string>
  <key>CFBundleVersion</key><string>5</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Prefer the Apple Developer ID (stable identity → Accessibility permission survives rebuilds,
# and it's what notarization needs). Fall back to the local self-signed identity, then ad-hoc.
DEVID=$(security find-identity -v -p codesigning | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"')
if [ -n "$DEVID" ]; then
  codesign --force --options runtime --sign "$DEVID" "$APP"
  echo "Signed with $DEVID (hardened runtime)"
elif security find-identity -v -p codesigning | grep -q "fdev Local Signing"; then
  codesign --force --sign "fdev Local Signing" "$APP"
  echo "Signed with 'fdev Local Signing'"
else
  codesign --force --sign - "$APP"
  echo "Ad-hoc signed. Run scripts/setup-signing.sh once so Accessibility permission survives rebuilds."
fi
echo "Built $PWD/$APP"
