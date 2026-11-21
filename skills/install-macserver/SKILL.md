---
name: install-macserver
description: Install or upgrade MacServer, the macOS menu bar app that keeps a MacBook awake only while plugged in, from a GitHub release. Use when the user asks to install, update, or reinstall MacServer.
---

# Install MacServer

Read https://github.com/Am1ne12/MacServer#readme first. MacServer requires macOS 13 or later and administrator access.

Never run `sudo` yourself and never pass a password to it. When a step needs the administrator password, give the user the exact command to run in Terminal and wait for them to confirm it finished.

## 1. Check the Mac

```bash
sw_vers -productVersion
uname -m
```

macOS 13+ is required. Apple Silicon and Intel are supported.

## 2. Download the latest stable release

Use `gh` if available:

```bash
rm -rf /tmp/macserver-install
mkdir -p /tmp/macserver-install
cd /tmp/macserver-install
gh release download --repo Am1ne12/MacServer --pattern 'MacServer-*.dmg' --pattern SHA256SUMS
```

If `gh` is missing, open https://github.com/Am1ne12/MacServer/releases/latest and download the DMG and `SHA256SUMS` manually. Do not download a different file to bypass a failed check.

## 3. Verify the download

```bash
cd /tmp/macserver-install
shasum -a 256 -c SHA256SUMS
```

Stop if the check fails.

## 4. Mount and install

```bash
hdiutil attach -nobrowse -readonly "$(ls MacServer-*.dmg | tail -1)"
ls /Volumes
```

Find the `MacServer X.Y.Z` volume. **Do not double-click `Install MacServer.command`**: Gatekeeper may block it. Give the user this command to run in Terminal:

```bash
sudo "/Volumes/MacServer X.Y.Z/.installer/install.sh"
```

Replace `X.Y.Z` with the actual volume name. Wait for the user to confirm that it finished.

## 5. Detach the DMG

```bash
hdiutil detach "/Volumes/MacServer X.Y.Z"
```

## 6. Verify the installation

```bash
macserver status
pgrep -fl MacServer
launchctl print system/com.am1ne.macserver.daemon
launchctl print system/com.am1ne.macserver.watchdog
```

You should see the power source, `Sleep disabled`, `Service: active`, and the watchdog job loaded (it runs every 30 seconds, so it is not always in a running state).

If the menu bar icon is hard to see, enable the compact icon:

```bash
macserver compact on
```

## 7. Gatekeeper

The installer runs from Terminal and removes the quarantine from the app. If macOS still blocks the first launch of `MacServer.app`, tell the user:

- Open **System Settings > Privacy & Security**.
- Click **Open Anyway** next to the MacServer message.
- Enter the administrator password, then click **Open**.

Alternatively:

```bash
xattr -dr com.apple.quarantine /Applications/MacServer.app
open -a /Applications/MacServer.app
```

Do not disable Gatekeeper globally.

## 8. Upgrade

Repeat steps 2-6. The installer stops the old daemon, app, and watchdog, replaces them, and starts the new versions. Settings in `/Users/Shared/MacServer` are kept.

## 9. Uninstall

```bash
sudo /usr/local/libexec/macserver-uninstall
```

Tell the user that this restores normal sleep and removes the app, both LaunchDaemons, the watchdog, the LaunchAgent, the state, and the logs.
