#!/bin/bash
# Builds MacServer.app into build/
set -euo pipefail

cd "$(dirname "$0")"

APP="build/MacServer.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

SOURCES=(app/main.swift app/KeyboardBacklight.swift app/SystemAudio.swift)

echo "Building arm64..."
xcrun swiftc -O -target arm64-apple-macos13.0 -framework AppKit \
    -o build/MacServer-arm64 "${SOURCES[@]}"

echo "Building x86_64..."
if xcrun swiftc -O -target x86_64-apple-macos13.0 -framework AppKit \
    -o build/MacServer-x86_64 "${SOURCES[@]}"; then
    lipo -create -output "$APP/Contents/MacOS/MacServer" \
        build/MacServer-arm64 build/MacServer-x86_64
    echo "Universal binary (arm64 + x86_64)."
else
    cp build/MacServer-arm64 "$APP/Contents/MacOS/MacServer"
    echo "Warning: x86_64 build failed, arm64-only binary."
fi

cp app/Info.plist "$APP/Contents/Info.plist"
cp app/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
plutil -lint "$APP/Contents/Info.plist" >/dev/null

echo "Ad-hoc signing..."
codesign --force --deep --sign - "$APP"

echo "Architecture:"
lipo -info "$APP/Contents/MacOS/MacServer"
echo "OK: $APP"
