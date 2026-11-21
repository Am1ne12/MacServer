# Changelog

## 1.2.0 — 2026-11-21

- Added lid actions: turn off the display, turn off the keyboard backlight, and mute audio when the lid closes; restore them when it opens.
- Added external display detection: a MacBook closed at a desk with an external display is left alone.
- Added a Lid Actions submenu with independent toggles for the keyboard backlight and audio.
- Added a small app log at `/Users/Shared/MacServer/app.log`.
- The daemon now delegates display sleep and the other lid actions to the menu bar app, so an external display is never turned off by mistake.
- The keyboard backlight uses a guarded private CoreBrightness API; it is skipped if the API changes.
- Quit and Uninstall restore any active lid action first.

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
