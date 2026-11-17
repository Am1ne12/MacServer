# Changelog

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
