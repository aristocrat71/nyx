# Nyx

Screen-share privacy for macOS. Share your entire screen; when you switch to a protected app, you see and use it normally while viewers see a black "Nyx is protecting this window" placeholder.

Requires macOS 14+ and Screen Recording permission.

## Build

```sh
make run      # build and run from the terminal
make release  # optimized build
make app      # assemble build/Nyx.app (tray app, bundled fonts, icon)
make icon     # regenerate assets/AppIcon.icns from scripts/render-icon.swift
make clean    # remove build artifacts
```

Run `./scripts/make-dev-cert.sh` once to create a self-signed "Nyx Dev" signing identity; `make app` picks it up automatically and the Screen Recording grant then survives rebuilds. Without it the bundle is ad-hoc signed and macOS invalidates the grant after every rebuild (fix a stale grant with `tccutil reset ScreenCapture tech.unravel.nyx`).

## Use

- Nyx lives in the menu bar (owl icon) — no Dock icon.
- Add apps via the dashboard picker, or press **⌃⇧L** while using an app to toggle its protection.
- The protected list persists at `~/Library/Application Support/Nyx/protected.json`.

## Known limitations (v1)

- macOS shows its screen-capture indicator ("Nyx — Currently Sharing") while a window is mirrored. There is no API to suppress it; the mirror is local-only and never leaves your Mac. Clicking the system "Stop Sharing" turns Nyx protection off (re-enable from the owl menu).

- Frontmost window of the app only; browsers are protected as whole apps, not per-tab.
- Notifications from a protected app are not covered.
- Brief overlay misalignment while dragging a protected window is expected.

Design and build plan live in `docs/`.
