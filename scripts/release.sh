#!/bin/bash
# Construit un DMG installable pour MacServer.
# Usage: ./scripts/release.sh [version]
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

VERSION="${1:-1.0.0}"
STAGE="$ROOT/dist/dmg"
DMG="$ROOT/dist/MacServer-$VERSION.dmg"

echo "== 1. Compilation =="
"$ROOT/build.sh"

echo
echo "== 2. Préparation du DMG $VERSION =="
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
    echo "Installation terminée."
else
    echo "L'installation a échoué (code $STATUS)."
fi
echo
read -n 1 -s -r -p "Appuie sur une touche pour fermer cette fenêtre..."
echo
EOF
chmod 0755 "$STAGE/Install MacServer.command"

cat > "$STAGE/Lisez-moi.txt" <<'EOF'
MacServer — installation
========================

1. Double-clique sur « Install MacServer.command ».
2. Entre ton mot de passe administrateur.
3. L'icône MacServer apparaît dans la barre des menus.

Si macOS bloque l'ouverture :
- Clic droit sur « Install MacServer.command » > Ouvrir.
- Ou Réglages Système > Confidentialité et sécurité > « Ouvrir quand même ».

MacServer installe :
- /Applications/MacServer.app
- un service d'arrière-plan (LaunchDaemon)
- la commande /usr/local/bin/macserver

Désinstallation :
- Menu de l'icône > « Désinstaller MacServer… »
- ou : sudo /usr/local/libexec/macserver-uninstall

Attention : ne laisse pas un MacBook éveillé, capot fermé, dans une housse.
EOF

echo
echo "== 3. Création du DMG =="
rm -f "$DMG"
hdiutil create \
    -volname "MacServer $VERSION" \
    -srcfolder "$STAGE" \
    -ov \
    -format UDZO \
    "$DMG"

echo
echo "DMG : $DMG"
shasum -a 256 "$DMG"
echo
echo "Pour tester :"
echo "  hdiutil attach \"$DMG\""
