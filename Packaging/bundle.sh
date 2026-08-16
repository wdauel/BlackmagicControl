#!/bin/zsh
# Packages BlackmagicControl as a shareable macOS .app bundle (ad-hoc signed).
#
#   ./Packaging/bundle.sh
#
# Output:
#   build/BlackmagicControl.app          — the app bundle
#   build/BlackmagicControl-<ver>.zip    — zip to send to others
#
# Recipients: because this is not notarized, the first launch needs a
# right-click → Open (see README "Sharing").
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="BlackmagicControl"
DISPLAY_NAME="Blackmagic Control"
BUNDLE_ID="com.dauel.blackmagiccontrol"
VERSION="3.8"
BUILD="1"
MIN_MACOS="14.0"

OUT="build"
APP="$OUT/$APP_NAME.app"
CONTENTS="$APP/Contents"

echo "▸ Building release binary…"
swift build -c release --disable-sandbox
BIN=".build/release/$APP_NAME"

echo "▸ Assembling bundle at $APP"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$BIN" "$CONTENTS/MacOS/$APP_NAME"

echo "▸ Rendering icon…"
swift Packaging/icon.swift >/dev/null
ICONSET="$OUT/AppIcon.iconset"
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
SRC="Packaging/icon_1024.png"
for pair in "16 16x16" "32 16x16@2x" "32 32x32" "64 32x32@2x" \
            "128 128x128" "256 128x128@2x" "256 256x256" "512 256x256@2x" \
            "512 512x512" "1024 512x512@2x"; do
  set -- ${=pair}
  sips -z "$1" "$1" "$SRC" --out "$ICONSET/icon_$2.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$CONTENTS/Resources/AppIcon.icns"
rm -rf "$ICONSET"

echo "▸ Writing Info.plist"
cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$DISPLAY_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD</string>
  <key>LSMinimumSystemVersion</key><string>$MIN_MACOS</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.video</string>
  <key>NSLocalNetworkUsageDescription</key><string>Connects to the Blackmagic Camera app on your iPhone over the local network.</string>
</dict>
</plist>
PLIST

echo "▸ Ad-hoc signing"
codesign --force --deep --sign - "$APP"

echo "▸ Zipping"
ZIP="$OUT/$APP_NAME-$VERSION.zip"
rm -f "$ZIP"
# ditto preserves the bundle + resource forks correctly for sharing.
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

echo "✓ Done"
echo "  App:  $APP"
echo "  Zip:  $ZIP"
