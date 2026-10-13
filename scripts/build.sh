#!/usr/bin/env bash
# Builds Rattle.app (release) with SwiftPM and ad-hoc signs it. No Xcode needed.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP=build/Rattle.app
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Rattle "$APP/Contents/MacOS/Rattle"

# App icon (.icns) so Finder, Dock and System Settings privacy lists show it.
swift scripts/make-icon.swift build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
cp scripts/lucide-LICENSE.txt "$APP/Contents/Resources/lucide-LICENSE.txt"   # icon set licence notice
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Rattle</string>
  <key>CFBundleDisplayName</key><string>Rattle</string>
  <key>CFBundleIdentifier</key><string>com.rattle.app</string>
  <key>CFBundleExecutable</key><string>Rattle</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.4</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAudioCaptureUsageDescription</key><string>Rattle records the audio playing on your Mac (the other side of a call) so Notetaker can transcribe meetings.</string>
  <key>NSMicrophoneUsageDescription</key><string>Rattle listens while you hold the shortcut so it can turn your speech into text.</string>
</dict></plist>
PLIST
IDENTITY="Rattle Local Signing"
if security find-identity -p codesigning | grep -q "$IDENTITY"; then
  codesign --force --deep --sign "$IDENTITY" "$APP"
else
  echo "warning: '$IDENTITY' not found (run scripts/setup-signing.sh); falling back to ad-hoc signing" >&2
  codesign --force --deep --sign - "$APP"
fi
echo "Built $APP"
