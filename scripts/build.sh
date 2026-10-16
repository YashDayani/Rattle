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
# macOS 26 draws the glass rim and lighting itself for icons built from an Icon Composer .icon file.
# That needs actool (full Xcode); without it the flat .icns above is used instead.
ICON_NAME=""
if xcrun --find actool >/dev/null 2>&1; then
  if xcrun actool Icon/Rattle.icon --compile "$APP/Contents/Resources" --output-format human-readable-text --notices --warnings --errors \
       --output-partial-info-plist build/icon-partial.plist --app-icon Rattle --include-all-app-icons \
       --target-device mac --minimum-deployment-target 26.0 --platform macosx >/dev/null; then
    ICON_NAME="Rattle"
  else
    echo "warning: actool failed to build Icon/Rattle.icon; using the flat icon" >&2
  fi
else
  echo "note: Xcode's actool not found; using the flat .icns (install Xcode for the macOS 26 glass icon)" >&2
fi
ICON_FILE_KEY="  <key>CFBundleIconFile</key><string>AppIcon</string>"
[ -n "$ICON_NAME" ] && { ICON_FILE_KEY="  <key>CFBundleIconFile</key><string>Rattle</string>"; rm -f "$APP/Contents/Resources/AppIcon.icns"; }   # actool emits Rattle.icns next to Assets.car; the system styles the .icon
cp scripts/lucide-LICENSE.txt "$APP/Contents/Resources/lucide-LICENSE.txt"   # icon set licence notice
mkdir -p "$APP/Contents/Resources/Fonts" && cp Fonts/* "$APP/Contents/Resources/Fonts/"   # Figtree + EB Garamond with their OFL notices
mkdir -p "$APP/Contents/Resources/Onboarding" && cp Onboarding/*.svg "$APP/Contents/Resources/Onboarding/"   # onboarding illustrations (Open Doodles, CC0)
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Rattle</string>
  <key>CFBundleDisplayName</key><string>Rattle</string>
  <key>CFBundleIdentifier</key><string>com.rattle.app</string>
  <key>CFBundleExecutable</key><string>Rattle</string>
${ICON_FILE_KEY}
${ICON_NAME:+  <key>CFBundleIconName</key><string>$ICON_NAME</string>}
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.4</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAudioCaptureUsageDescription</key><string>Rattle records the audio playing on your Mac (the other side of a call) so Rattle can transcribe meetings.</string>
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
