#!/bin/bash
# Builds Nibbo.app (universal: Apple Silicon + Intel) from the Swift package.
# Requires Xcode Command Line Tools (xcode-select --install).
#   ./build.sh          build Nibbo.app
#   ./build.sh --zip    also package dist/Nibbo.zip for a GitHub release
set -euo pipefail
cd "$(dirname "$0")"

APP="Nibbo.app"
VERSION="0.2.0"

# One build per architecture, then merge (multi-arch `swift build` needs full Xcode).
for arch in arm64 x86_64; do
    swift build -c release --triple "$arch-apple-macosx13.0"
done

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create -output "$APP/Contents/MacOS/Nibbo" \
    .build/arm64-apple-macosx/release/Nibbo \
    .build/x86_64-apple-macosx/release/Nibbo
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Nibbo</string>
    <key>CFBundleDisplayName</key><string>Nibbo</string>
    <key>CFBundleIdentifier</key><string>io.github.jasonzamp.nibbo</string>
    <key>CFBundleExecutable</key><string>Nibbo</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>Nibbo listens to how loud the room is so it can pause scrolling when you stop talking. Audio is never recorded or sent anywhere.</string>
</dict>
</plist>
PLIST

# Ad-hoc signature so macOS remembers the microphone permission between launches.
codesign --force --deep --sign - "$APP"

echo "Built $APP $VERSION — start it with: open $APP"

if [[ "${1:-}" == "--zip" ]]; then
    mkdir -p dist
    rm -f dist/Nibbo.zip
    ditto -c -k --keepParent "$APP" dist/Nibbo.zip
    echo "Packaged dist/Nibbo.zip (upload it to a GitHub release as Nibbo.zip)"
fi
