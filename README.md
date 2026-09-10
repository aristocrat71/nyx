# Nyx

Screen-share privacy for macOS. Share your entire screen; when you switch to a protected app during a share, you see and use it normally while viewers see a black "Nyx is protecting this window" placeholder. With nothing capturing your screen, Nyx stays out of the way.

Requires macOS 14+ and Screen Recording permission.

## Build

```sh
make run      # build and run from the terminal
make test     # run the test suite
make release  # optimized build
make app      # assemble build/Nyx.app (tray app, bundled fonts, icon)
make icon     # rebuild the app icon and the dashboard glyph from assets/nyx-logo.png
make clean    # remove build artifacts
```

Run `./scripts/make-dev-cert.sh` once to create a self-signed "Nyx Dev" signing identity; `make app` picks it up automatically and the Screen Recording grant then survives rebuilds. Without it the bundle is ad-hoc signed and macOS invalidates the grant after every rebuild (fix a stale grant with `tccutil reset ScreenCapture tech.unravel.nyx`).

The certificate is not installed as a trusted root — `codesign` accepts an untrusted leaf addressed by hash, and TCC keys the grant to the leaf either way. It is still a signing identity that grants Screen Recording to anything signed with it under `tech.unravel.nyx`, so remove it when you are done developing:

```sh
./scripts/remove-dev-cert.sh
```

`make app` signs with the hardened runtime. Debug builds (`make run`) are ad-hoc signed by SwiftPM and carry `com.apple.security.get-task-allow`; grant Screen Recording to `build/Nyx.app` rather than to a debug build.

## Use

- Nyx lives in the menu bar (owl icon) — no Dock icon.
- Add apps via the dashboard picker, by pressing **⌃⇧L** while using an app, or from the owl menu's first item, which toggles protection for whatever is frontmost.
- The protected list persists at `~/Library/Application Support/Nyx/protected.json`.

## Known limitations (v1)

- macOS shows its screen-capture indicator ("Nyx — Currently Sharing") while a window is mirrored, which only happens while something else is already capturing the screen. There is no API to suppress it; the mirror is local-only and never leaves your Mac. Clicking the system "Stop Sharing" turns Nyx protection off (re-enable from the owl menu).
- Nyx notices a share a moment after it starts, not before. A protected app that is already frontmost when the share begins is covered about half a second in, as soon as the capture is running. Once engaged, Nyx stays engaged until you switch apps even if the share ended earlier: it cannot tell the share's capture apart from its own mirror.

- Every window the protected app owns is covered, including its menus and tooltips. Browsers are still protected as whole apps, not per-tab.
- Notifications are drawn by the system, not by the protected app, so they are not covered.
- The overlay sits one level above the protected app's own windows, so the Dock, the Cmd-Tab switcher, the menu bar and menu-bar-extra menus stay visible over it. While the app has a menu or tooltip open the overlay rises to cover that too, and those system elements are hidden from you (never from viewers) until it closes.
- Mission Control and Exposé shrink the real windows out from under the placeholders.
- If Nyx cannot start its capture stream it fails closed: the placeholder stays up and you lose the local preview until the stream recovers. The menu bar icon turns red and the dashboard says "Hidden — no local preview".
- While a protected app is frontmost during a share Nyx costs roughly 10% of one core (a full-display capture plus a 60 Hz window resnap). It is idle otherwise.

Design and build plan live in `docs/`.
