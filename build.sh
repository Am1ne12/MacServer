#!/bin/bash
# Compile l'application MacServer.app dans build/
set -euo pipefail

cd "$(dirname "$0")"

APP="build/MacServer.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "Compilation arm64..."
xcrun swiftc -O -target arm64-apple-macos13.0 -framework AppKit \
    -o build/MacServer-arm64 app/main.swift

echo "Compilation x86_64..."
if xcrun swiftc -O -target x86_64-apple-macos13.0 -framework AppKit \
    -o build/MacServer-x86_64 app/main.swift; then
    lipo -create -output "$APP/Contents/MacOS/MacServer" \
        build/MacServer-arm64 build/MacServer-x86_64
    echo "Binaire universel (arm64 + x86_64)."
else
    cp build/MacServer-arm64 "$APP/Contents/MacOS/MacServer"
    echo "Attention : compilation x86_64 impossible, binaire arm64 seulement."
fi

cp app/Info.plist "$APP/Contents/Info.plist"
cp app/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
plutil -lint "$APP/Contents/Info.plist" >/dev/null

echo "Signature ad hoc..."
codesign --force --deep --sign - "$APP"

echo "Architecture :"
lipo -info "$APP/Contents/MacOS/MacServer"
echo "OK: $APP"
