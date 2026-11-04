#!/bin/bash
# Builds Cue.app from the Swift package. Requires Xcode Command Line Tools (xcode-select --install).
set -euo pipefail
cd "$(dirname "$0")"

APP="Cue.app"
swift build -c release

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Cue "$APP/Contents/MacOS/Cue"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Cue</string>
    <key>CFBundleDisplayName</key><string>Cue</string>
    <key>CFBundleIdentifier</key><string>io.github.jasonzamp.cue</string>
    <key>CFBundleExecutable</key><string>Cue</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>Cue listens to how loud the room is so it can pause scrolling when you stop talking. Audio is never recorded or sent anywhere.</string>
</dict>
</plist>
PLIST

# Ad-hoc signature so macOS remembers the microphone permission between launches.
codesign --force --deep --sign - "$APP"

echo "Built $APP — start it with: open $APP"
