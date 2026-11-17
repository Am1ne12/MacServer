#!/bin/bash
# Builds an installable MacServer DMG.
# Usage: ./scripts/release.sh [version]
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

VERSION="${1:-1.0.0}"
STAGE="$ROOT/dist/dmg"
DMG="$ROOT/dist/MacServer-$VERSION.dmg"

echo "== 1. Building =="
"$ROOT/build.sh"

echo
echo "== 2. Preparing DMG $VERSION =="
rm -rf "$STAGE"
mkdir -p "$STAGE/.installer"

ditto "$ROOT/build/MacServer.app" "$STAGE/MacServer.app"
cp "$ROOT/daemon/macserver" "$STAGE/.installer/macserver"
cp "$ROOT/daemon/macserver-uninstall" "$STAGE/.installer/macserver-uninstall"
cp "$ROOT/daemon/com.am1ne.macserver.daemon.plist" "$STAGE/.installer/"
cp "$ROOT/app/com.am1ne.macserver.app.plist" "$STAGE/.installer/"
cp "$ROOT/scripts/install-from-dmg.sh" "$STAGE/.installer/install.sh"
chmod 0755 "$STAGE/.installer/install.sh" \
    "$STAGE/.installer/macserver" \
    "$STAGE/.installer/macserver-uninstall"

cat > "$STAGE/Install MacServer.command" <<'EOF'
#!/bin/bash
cd "$(dirname "$0")"
sudo "$PWD/.installer/install.sh"
STATUS=$?
echo
if [[ $STATUS -eq 0 ]]; then
    echo "Installation complete."
else
    echo "Installation failed (code $STATUS)."
fi
echo
read -n 1 -s -r -p "Press any key to close this window..."
echo
EOF
chmod 0755 "$STAGE/Install MacServer.command"

cat > "$STAGE/Read Me.txt" <<'EOF'
MacServer — Installation
========================

1. Double-click "Install MacServer.command".
2. Enter your administrator password.
3. The MacServer icon appears in the menu bar.

If macOS blocks the installer:
- Right-click "Install MacServer.command" > Open.
- Or System Settings > Privacy & Security > "Open Anyway".

MacServer installs:
- /Applications/MacServer.app
- a background service (LaunchDaemon)
- the /usr/local/bin/macserver command

Uninstall:
- Icon menu > "Uninstall MacServer…"
- or: sudo /usr/local/libexec/macserver-uninstall

Warning: do not leave a MacBook awake with the lid closed in a bag.
EOF

echo
echo "== 3. Creating DMG =="
rm -f "$DMG"
hdiutil create \
    -volname "MacServer $VERSION" \
    -srcfolder "$STAGE" \
    -ov \
    -format UDZO \
    "$DMG"

echo
echo "DMG: $DMG"
shasum -a 256 "$DMG"
echo
echo "To test:"
echo "  hdiutil attach \"$DMG\""
