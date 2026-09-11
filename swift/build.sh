#!/bin/bash
# Compiles the sources into "Red Wedge Timer.app" next to this script.
set -euo pipefail
cd "$(dirname "$0")"

APP="Red Wedge Timer.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Red Wedge Timer</string>
  <key>CFBundleDisplayName</key><string>Red Wedge Timer</string>
  <key>CFBundleExecutable</key><string>RedWedgeTimer</string>
  <key>CFBundleIdentifier</key><string>com.bersling.redwedgetimer</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSSupportsAutomaticTermination</key><false/>
</dict>
</plist>
PLIST

swiftc -O -parse-as-library \
  -target arm64-apple-macos14.0 \
  -framework SwiftUI -framework AppKit -framework AVFoundation \
  -o "$APP/Contents/MacOS/RedWedgeTimer" \
  Sources/*.swift

codesign --force --sign - "$APP" >/dev/null 2>&1 || echo "note: ad-hoc signing skipped"
echo "built $PWD/$APP"
