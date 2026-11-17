#!/bin/bash
# Installs MacServer (root service + menu bar icon).
set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
cd "$SCRIPT_DIR"
PROJECT_DIR="$SCRIPT_DIR"
APP_SRC="$PROJECT_DIR/build/MacServer.app"

# 1. As the user: build, then request sudo.
if [[ $EUID -ne 0 ]]; then
    echo "== Building MacServer =="
    "$PROJECT_DIR/build.sh"
    echo
    echo "== Installing (administrator password) =="
    exec sudo "$PROJECT_DIR/install.sh" "$@"
fi

# 2. As root: find the logged-in user.
if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    TARGET_USER="$SUDO_USER"
else
    TARGET_USER=$(stat -f%Su /dev/console 2>/dev/null || true)
fi

if [[ -z "${TARGET_USER:-}" || "$TARGET_USER" == "root" ]]; then
    echo "Could not find the logged-in user."
    echo "Run the script from your session: ./install.sh"
    exit 1
fi

TARGET_UID=$(id -u "$TARGET_USER")
TARGET_HOME=$(dscl . -read "/Users/$TARGET_USER" NFSHomeDirectory 2>/dev/null | awk '{print $2}')

if [[ -z "${TARGET_HOME:-}" || ! -d "$TARGET_HOME" ]]; then
    echo "Home directory not found for $TARGET_USER."
    exit 1
fi

if [[ ! -d "$APP_SRC" ]]; then
    echo "The application is not built."
    echo "Run ./build.sh then retry the installation."
    exit 1
fi

echo "User: $TARGET_USER"
echo "Application: $APP_SRC"
echo

echo "== Stopping previous version =="
launchctl bootout system/com.am1ne.macserver.daemon 2>/dev/null || true
launchctl bootout "gui/$TARGET_UID/com.am1ne.macserver.app" 2>/dev/null || true
launchctl asuser "$TARGET_UID" osascript -e 'tell application "MacServer" to quit' 2>/dev/null || true
pkill -x MacServer 2>/dev/null || true
pmset -a disablesleep 0 2>/dev/null || true

rm -rf /Applications/MacServer.app
rm -f /usr/local/bin/macserver
rm -f /usr/local/libexec/macserver-uninstall
rm -f /Library/LaunchDaemons/com.am1ne.macserver.daemon.plist

echo "== Installing application =="
ditto "$APP_SRC" /Applications/MacServer.app
chown -R root:wheel /Applications/MacServer.app
xattr -dr com.apple.quarantine /Applications/MacServer.app 2>/dev/null || true
if ! codesign --verify --deep --strict /Applications/MacServer.app >/dev/null 2>&1; then
    codesign --force --deep --sign - /Applications/MacServer.app
fi

echo "== Installing service =="
mkdir -p /usr/local/bin /usr/local/libexec
install -m 0755 -o root -g wheel "$PROJECT_DIR/daemon/macserver" /usr/local/bin/macserver
install -m 0755 -o root -g wheel "$PROJECT_DIR/daemon/macserver-uninstall" /usr/local/libexec/macserver-uninstall
install -m 0644 -o root -g wheel "$PROJECT_DIR/daemon/com.am1ne.macserver.daemon.plist" /Library/LaunchDaemons/com.am1ne.macserver.daemon.plist

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
# Wait for the previous service to unload completely.
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
    echo "Check /var/log/macserver.log then retry the installation."
    exit 1
fi

launchctl enable system/com.am1ne.macserver.daemon 2>/dev/null || true
launchctl kickstart -k system/com.am1ne.macserver.daemon 2>/dev/null || true

echo "== Installing menu bar icon =="
mkdir -p "$TARGET_HOME/Library/LaunchAgents"
install -m 0644 -o "$TARGET_USER" -g staff \
    "$PROJECT_DIR/app/com.am1ne.macserver.app.plist" \
    "$TARGET_HOME/Library/LaunchAgents/com.am1ne.macserver.app.plist"
chown "$TARGET_USER":staff "$TARGET_HOME/Library/LaunchAgents/com.am1ne.macserver.app.plist" 2>/dev/null || true

launchctl asuser "$TARGET_UID" launchctl bootstrap "gui/$TARGET_UID" \
    "$TARGET_HOME/Library/LaunchAgents/com.am1ne.macserver.app.plist" 2>/dev/null || true
launchctl asuser "$TARGET_UID" launchctl enable "gui/$TARGET_UID/com.am1ne.macserver.app" 2>/dev/null || true

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
if pmset -g ps | head -1 | grep -q "AC Power"; then
    if [[ "$(pmset -g | awk '/SleepDisabled/ {print $2; exit}')" == "1" ]]; then
        echo "OK: server mode active, sleep disabled on AC power."
    else
        echo "WARNING: sleep is not disabled yet."
        echo "Check /var/log/macserver.log for details."
    fi
else
    echo "OK: on battery, normal sleep."
fi

echo
echo "Notes:"
echo "  - On normal battery, the MacServer icon shows pause; on AC power, it turns green."
echo "  - macOS may ask you to allow MacServer in System Settings > General > Login Items & Extensions."
echo "  - Do not leave the Mac awake in a bag or on a bed."
echo "  - Uninstall: MacServer icon > Uninstall, or sudo /usr/local/libexec/macserver-uninstall"
echo
echo "MacServer is installed."
