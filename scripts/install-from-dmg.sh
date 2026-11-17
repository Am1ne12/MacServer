#!/bin/bash
# Installs MacServer from the DMG.
# This script is copied to .installer/install.sh inside the DMG.
set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
DMG_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
APP_SRC="$DMG_ROOT/MacServer.app"

if [[ $EUID -ne 0 ]]; then
    exec sudo "$0" "$@"
fi

if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    TARGET_USER="$SUDO_USER"
else
    TARGET_USER=$(stat -f%Su /dev/console 2>/dev/null || true)
fi

if [[ -z "${TARGET_USER:-}" || "$TARGET_USER" == "root" ]]; then
    echo "Could not find the logged-in user."
    echo "Log in to a macOS session, then run the installer again."
    exit 1
fi

TARGET_UID=$(id -u "$TARGET_USER")
TARGET_HOME=$(dscl . -read "/Users/$TARGET_USER" NFSHomeDirectory 2>/dev/null | awk '{print $2}')

if [[ -z "${TARGET_HOME:-}" || ! -d "$TARGET_HOME" ]]; then
    echo "Home directory not found for $TARGET_USER."
    exit 1
fi

if [[ ! -d "$APP_SRC" ]]; then
    echo "MacServer.app was not found in the DMG."
    exit 1
fi

echo "User: $TARGET_USER"
echo

echo "== Stopping previous version =="
launchctl bootout system/com.am1ne.macserver.daemon 2>/dev/null || true
launchctl bootout "gui/$TARGET_UID/com.am1ne.macserver.app" 2>/dev/null || true
launchctl asuser "$TARGET_UID" osascript -e 'tell application "MacServer" to quit' 2>/dev/null || true
pkill -x MacServer 2>/dev/null || true
pmset -a disablesleep 0 2>/dev/null || true

echo "== Installing application =="
rm -rf /Applications/MacServer.app
ditto "$APP_SRC" /Applications/MacServer.app
chown -R root:wheel /Applications/MacServer.app
xattr -dr com.apple.quarantine /Applications/MacServer.app 2>/dev/null || true
if ! codesign --verify --deep --strict /Applications/MacServer.app >/dev/null 2>&1; then
    codesign --force --deep --sign - /Applications/MacServer.app
fi

echo "== Installing service =="
mkdir -p /usr/local/bin /usr/local/libexec
install -m 0755 -o root -g wheel "$SCRIPT_DIR/macserver" /usr/local/bin/macserver
install -m 0755 -o root -g wheel "$SCRIPT_DIR/macserver-uninstall" /usr/local/libexec/macserver-uninstall
install -m 0644 -o root -g wheel \
    "$SCRIPT_DIR/com.am1ne.macserver.daemon.plist" \
    /Library/LaunchDaemons/com.am1ne.macserver.daemon.plist

mkdir -p /Users/Shared/MacServer
chown root:staff /Users/Shared/MacServer
chmod 2775 /Users/Shared/MacServer

touch /var/log/macserver.log
chown root:wheel /var/log/macserver.log
chmod 644 /var/log/macserver.log

echo "== Enabling wake on charger =="
if pmset -a acwake 1 >> /var/log/macserver.log 2>&1; then
    echo "  acwake enabled."
else
    echo "  acwake refused by this Mac (wake on charger may not work)."
fi

echo "== Starting service =="
for _ in {1..20}; do
    if ! launchctl print system/com.am1ne.macserver.daemon >/dev/null 2>&1; then
        break
    fi
    sleep 0.2
done
sleep 1

BOOTSTRAPPED=0
for attempt in 1 2 3; do
    if launchctl bootstrap system /Library/LaunchDaemons/com.am1ne.macserver.daemon.plist 2>/dev/null; then
        BOOTSTRAPPED=1
        break
    fi
    echo "  loading service: attempt $attempt failed, retrying..."
    sleep 2
done

if [[ "$BOOTSTRAPPED" -ne 1 ]]; then
    echo "ERROR: could not load service."
    echo "Check /var/log/macserver.log."
    exit 1
fi

launchctl enable system/com.am1ne.macserver.daemon 2>/dev/null || true
launchctl kickstart -k system/com.am1ne.macserver.daemon 2>/dev/null || true

echo "== Installing menu bar icon =="
mkdir -p "$TARGET_HOME/Library/LaunchAgents"
install -m 0644 -o "$TARGET_USER" -g staff \
    "$SCRIPT_DIR/com.am1ne.macserver.app.plist" \
    "$TARGET_HOME/Library/LaunchAgents/com.am1ne.macserver.app.plist"
chown "$TARGET_USER":staff \
    "$TARGET_HOME/Library/LaunchAgents/com.am1ne.macserver.app.plist" 2>/dev/null || true

launchctl asuser "$TARGET_UID" launchctl bootstrap "gui/$TARGET_UID" \
    "$TARGET_HOME/Library/LaunchAgents/com.am1ne.macserver.app.plist" 2>/dev/null || true
launchctl asuser "$TARGET_UID" launchctl enable \
    "gui/$TARGET_UID/com.am1ne.macserver.app" 2>/dev/null || true

sleep 1
if ! pgrep -x MacServer >/dev/null 2>&1; then
    launchctl asuser "$TARGET_UID" open -a /Applications/MacServer.app 2>/dev/null || \
        sudo -u "$TARGET_USER" open -a /Applications/MacServer.app 2>/dev/null || true
fi

sleep 2

echo
echo "== Verification =="
/usr/local/bin/macserver status 2>&1 | sed 's/^/  /'

echo
echo "Notes:"
echo "  - On AC power, the icon is green; on normal battery, it shows pause."
echo "  - If the icon does not appear, your menu bar may be full."
echo "    Hide a few icons or use a menu bar manager."
echo "  - macOS may ask you to allow MacServer in System Settings > General >"
echo "    Login Items & Extensions."
echo "  - Do not leave the Mac awake in a bag or on a bed."
echo
echo "MacServer is installed."
