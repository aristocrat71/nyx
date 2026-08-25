# Nyx 🦉

Screen-share privacy for macOS. Share your entire screen; when you switch to a protected app, you see and use it normally while viewers see a black "Nyx is protecting this window" placeholder.

Requires macOS 14+ and Screen Recording permission.

## Build

```sh
swift build            # dev build
swift run              # run from the terminal
./scripts/make-app.sh  # assemble build/Nyx.app (tray app, bundled fonts, icon)
```

The bundle is ad-hoc signed, so macOS may re-ask for Screen Recording permission after a rebuild.

## Use

- Nyx lives in the menu bar (owl icon) — no Dock icon.
- Add apps via the dashboard picker, or press **⌃⌥⇧N** while using an app to toggle its protection.
- The protected list persists at `~/Library/Application Support/Nyx/protected.json`.

## Known limitations (v1)

- Frontmost window of the app only; browsers are protected as whole apps, not per-tab.
- Notifications from a protected app are not covered.
- Brief overlay misalignment while dragging a protected window is expected.

Design and build plan live in `docs/`.
