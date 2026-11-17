#!/bin/bash
# Wrapper de desinstallation depuis le dossier du projet.
set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

if [[ -f /usr/local/libexec/macserver-uninstall ]]; then
    exec sudo /usr/local/libexec/macserver-uninstall
fi

exec sudo "$SCRIPT_DIR/daemon/macserver-uninstall"
