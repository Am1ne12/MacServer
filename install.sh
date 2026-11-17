#!/bin/bash
# Installe MacServer (service root + icone dans la barre des menus).
set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
cd "$SCRIPT_DIR"
PROJECT_DIR="$SCRIPT_DIR"
APP_SRC="$PROJECT_DIR/build/MacServer.app"

# 1. En tant qu'utilisateur : compiler puis demander sudo.
if [[ $EUID -ne 0 ]]; then
    echo "== Construction de MacServer =="
    "$PROJECT_DIR/build.sh"
    echo
    echo "== Installation (mot de passe administrateur) =="
    exec sudo "$PROJECT_DIR/install.sh" "$@"
fi

# 2. En root : trouver l'utilisateur connecte.
if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    TARGET_USER="$SUDO_USER"
else
    TARGET_USER=$(stat -f%Su /dev/console 2>/dev/null || true)
fi

if [[ -z "${TARGET_USER:-}" || "$TARGET_USER" == "root" ]]; then
    echo "Impossible de trouver l'utilisateur connecte."
    echo "Lance le script depuis ta session : ./install.sh"
    exit 1
fi

TARGET_UID=$(id -u "$TARGET_USER")
TARGET_HOME=$(dscl . -read "/Users/$TARGET_USER" NFSHomeDirectory 2>/dev/null | awk '{print $2}')

if [[ -z "${TARGET_HOME:-}" || ! -d "$TARGET_HOME" ]]; then
    echo "Dossier personnel introuvable pour $TARGET_USER."
    exit 1
fi

if [[ ! -d "$APP_SRC" ]]; then
    echo "L'application n'est pas compilee."
    echo "Lance ./build.sh puis relance l'installation."
    exit 1
fi

echo "Utilisateur : $TARGET_USER"
echo "Application : $APP_SRC"
echo

echo "== Arret de l'ancienne version =="
launchctl bootout system/com.am1ne.macserver.daemon 2>/dev/null || true
launchctl bootout "gui/$TARGET_UID/com.am1ne.macserver.app" 2>/dev/null || true
launchctl asuser "$TARGET_UID" osascript -e 'tell application "MacServer" to quit' 2>/dev/null || true
pkill -x MacServer 2>/dev/null || true
pmset -a disablesleep 0 2>/dev/null || true

rm -rf /Applications/MacServer.app
rm -f /usr/local/bin/macserver
rm -f /usr/local/libexec/macserver-uninstall
rm -f /Library/LaunchDaemons/com.am1ne.macserver.daemon.plist

echo "== Installation de l'application =="
ditto "$APP_SRC" /Applications/MacServer.app
chown -R root:wheel /Applications/MacServer.app
xattr -dr com.apple.quarantine /Applications/MacServer.app 2>/dev/null || true
if ! codesign --verify --deep --strict /Applications/MacServer.app >/dev/null 2>&1; then
    codesign --force --deep --sign - /Applications/MacServer.app
fi

echo "== Installation du service =="
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

echo "== Activation du reveil au branchement =="
if pmset -a acwake 1 >> /var/log/macserver.log 2>&1; then
    echo "  acwake active."
else
    echo "  acwake refuse par ce Mac (le reveil au branchement peut ne pas marcher)."
fi

echo "== Demarrage du service =="
# Attendre que l'ancien service soit completement decharge.
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
    echo "  chargement du service : tentative $attempt echouee, nouvel essai..."
    sleep 2
done

if [[ "$BOOTSTRAPPED" -ne 1 ]]; then
    echo "ERREUR : impossible de charger le service."
    echo "Verifie /var/log/macserver.log puis relance l'installation."
    exit 1
fi

launchctl enable system/com.am1ne.macserver.daemon 2>/dev/null || true
launchctl kickstart -k system/com.am1ne.macserver.daemon 2>/dev/null || true

echo "== Installation de l'icone =="
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
        echo "OK : mode serveur actif, la veille est desactivee sur secteur."
    else
        echo "ATTENTION : la veille n'est pas encore desactivee."
        echo "Regarde /var/log/macserver.log pour comprendre."
    fi
else
    echo "OK : sur batterie, la veille reste normale."
fi

echo
echo "Notes :"
echo "  - Sur batterie normale, l'icone MacServer affiche pause ; sur secteur, elle passe au vert."
echo "  - macOS peut demander d'autoriser MacServer dans Reglages > General > Ouverture de session."
echo "  - Ne laisse pas le Mac eveille dans une housse ou sur un lit."
echo "  - Desinstallation : icone MacServer > Desinstaller, ou sudo /usr/local/libexec/macserver-uninstall"
echo
echo "MacServer est installe."
