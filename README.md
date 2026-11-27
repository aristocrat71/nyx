<div align="center">

<img src="assets/nyx-logo.png" alt="" width="96">

# Nyx

**Share your screen, not everything on it.**

Nyx blacks out the apps and sites you choose whenever something is capturing your screen.<br>
You keep using them normally — viewers see a placeholder.

One codebase for macOS, Windows and Linux, built with Tauri.

</div>

---

## How it works

Nyx never touches the other app or the meeting. It puts two windows of its own on top — a black cover that capture software sees, and a live mirror that only you see. Your clicks and keys pass through to the real app underneath.

<div align="center">
<img src="assets/nyx-how-it-works.png" alt="The real app sits under a black cover that viewers see and a live mirror that only you see." width="820">
</div>

| | macOS | Windows | Linux (X11) |
|---|---|---|---|
| Knows a capture started | WindowServer's screen-watcher flag | the capture consent store | no signal: always covers |
| Cover viewers see | above the app's windows, menus included | above the app's windows, menus included | above the app's windows |
| Mirror only you see | ScreenCaptureKit, `sharingType = none` | Windows Graphics Capture, `WDA_EXCLUDEFROMCAPTURE` | none: X11 cannot hide a window from capture |
| Site rules | host from the address bar (Accessibility) | brand name in the window title | brand name in the window title |
| Status | built and tested | written, compile-checked, **not yet run** | written, compile-checked, **not yet run** |

On Linux you see the cover too, so protected apps are unusable while they are in front. Wayland sessions are not supported: Nyx cannot see or cover other windows there, and says so.

---

## Install

macOS, in one line. It verifies the download's checksum and skips the Gatekeeper prompt:

```sh
curl -fsSL https://raw.githubusercontent.com/unravel-team/nyx/main/install.sh | bash
```

Or download [Nyx.dmg](https://github.com/unravel-team/nyx/releases/latest/download/Nyx.dmg). Nyx is not notarized yet, so the first launch is blocked: click **Done**, then **System Settings › Privacy & Security › Open Anyway**. Windows and Linux builds are not released yet.

---

## Use

- Nyx lives in the **tray** (owl icon). The dashboard opens on first launch, or from the tray.
- Add apps from the dashboard picker, by pressing <kbd>Ctrl</kbd><kbd>Shift</kbd><kbd>L</kbd> (<kbd>⌃</kbd><kbd>⇧</kbd><kbd>L</kbd> on a Mac) while using one, or from the tray's first item.
- List a host such as `youtube.com` and the browser is covered whenever a matching page is your front tab. Subdomains count (`m.youtube.com`), look-alikes do not (`notyoutube.com`).
- If the mirror cannot start, Nyx fails closed: the cover stays up and the tray dot turns red.
- The protected list is `protected.json` in `~/Library/Application Support/Nyx` (macOS), `%APPDATA%\Nyx` (Windows) or `~/.config/Nyx` (Linux). The macOS file is the one the Swift version of Nyx wrote, so an existing list carries over.

macOS asks for **Screen Recording** on first launch, and site rules need **Accessibility**. Windows and Linux ask for nothing.

---

<div align="center">

<sub>Built by</sub><br>
<img src="assets/Unravel_Logo_-_Transparent.png" alt="Unravel" width="128">

</div>
