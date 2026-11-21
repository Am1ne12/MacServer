# Changelog

## 1.1.0 — 2026-11-21

- Added an install skill for coding agents and SHA-256 verification for releases.
- Added a recovery watchdog LaunchDaemon that restores normal sleep and restarts the service if the main daemon dies or its status becomes stale.
- Added Low Power Mode below 40% in battery server mode, with automatic restoration.
- Added best-effort thermal protection: if macOS reports critical thermal pressure, sleep is re-enabled.
- Added a compact menu bar icon mode and `macserver compact on|off`.
- Added a "Thermal Protection" icon state and low-power status in the menu.

## 1.0.0 — 2026-11-17

First public release.

- Automatic server mode on AC power: system sleep disabled, including with the lid closed.
- Normal battery behavior: the Mac sleeps when the lid is closed.
- Wake on charger connection via `acwake`, then kept awake by the service.
- Optional "server on battery" mode with an automatic stop at 20%.
- Screen lock when the lid is closed.
- Menu bar icon states: server on AC, laptop/paused, server on battery, alert.
- Menu: pause/resume, battery mode, lock screen now, log, uninstall.
- `macserver` CLI: `status`, `pause`, `resume`, `battery on|off`.
- Root LaunchDaemon, starts at boot, automatically restarts if it exits.
- Universal app for Apple Silicon and Intel.
- DMG installer with instructions and clean uninstall.
