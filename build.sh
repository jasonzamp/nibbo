#!/bin/bash
# Builds Cue.app (universal: Apple Silicon + Intel) from the Swift package.
# Requires Xcode Command Line Tools (xcode-select --install).
#   ./build.sh          build Cue.app
#   ./build.sh --zip    also package dist/Cue.zip for a GitHub release
set -euo pipefail
cd "$(dirname "$0")"

APP="Cue.app"
VERSION="0.2.0"

# One build per architecture, then merge (multi-arch `swift build` needs full Xcode).
for arch in arm64 x86_64; do
    swift build -c release --triple "$arch-apple-macosx13.0"
done

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create -output "$APP/Contents/MacOS/Cue" \
    .build/arm64-apple-macosx/release/Cue \
    .build/x86_64-apple-macosx/release/Cue
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Cue</string>
    <key>CFBundleDisplayName</key><string>Cue</string>
    <key>CFBundleIdentifier</key><string>io.github.jasonzamp.cue</string>
    <key>CFBundleExecutable</key><string>Cue</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
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

echo "Built $APP $VERSION — start it with: open $APP"

if [[ "${1:-}" == "--zip" ]]; then
    mkdir -p dist
    rm -f dist/Cue.zip
    ditto -c -k --keepParent "$APP" dist/Cue.zip
    echo "Packaged dist/Cue.zip (upload it to a GitHub release as Cue.zip)"
fi
