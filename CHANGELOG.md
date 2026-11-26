# Changelog

All notable changes to Nyx are recorded here.

## [0.1.4] - 2026-11-26

### Fixed

- **Dashboard opens in front.** When macOS reopens Nyx, for example after you
  allow Screen Recording, the dashboard now comes up in front of your other
  windows instead of behind them.
- **The right owl in the intro.** The intro's last page now shows the owl
  exactly as it appears in your menu bar.

## [0.1.3] - 2026-11-26

### Added

- **Version in Settings.** Settings show which version of Nyx is running.

### Changed

- **Where to find Nyx.** The intro now ends by showing the owl in the menu bar,
  and Settings says how to get back to the dashboard: click the owl, or open
  Nyx again.

## [0.1.2] - 2026-11-26

### Changed

- **Always reachable.** Opening Nyx again from Spotlight or Finder opens the
  dashboard, so a crowded menu bar that hides the owl no longer locks you out.
  The owl also starts at the right end of the menu bar, the last place macOS
  hides icons.

### Fixed

- **Permissions after an update.** System Settings could show Nyx as allowed
  while Nyx still asked for Screen Recording or Accessibility, because the entry
  belonged to the previous version. The first time Nyx starts after an update it
  clears such entries, so allowing it once more takes effect.

## [0.1.1] - 2026-11-26

From this version on, Nyx updates itself. Coming from 0.1.0, install this one by
hand once, and every later release arrives on its own.

### Added

- **Automatic updates.** Nyx checks for a new release shortly after launch and
  every six hours, verifies the download's checksum, and installs it the next
  time nothing is covered, then reopens itself.
- **What's new after an update.** After Nyx updates, the dashboard lists what
  changed, with a link to the full release notes.

### Changed

- **A calmer empty dashboard.** With nothing protected, the dashboard shows just
  the owl and the two add buttons.
- **Add buttons above the lists.** Add app and Add website sit right under their
  heading, so they stay in reach however long the lists grow.
- **Pickers open beside their button.** The app picker and the website field open
  next to the button you clicked, instead of at the top of the window.

## [0.1.0] - 2026-11-26

First release. Nyx sits in the menu bar and blacks out the apps and sites you
list whenever something is capturing your screen — you keep using them normally,
viewers see a placeholder. macOS only for now; Windows and Linux are on the way.

### Added

- **Per-app protection.** Add apps from the dashboard picker, with **⌃⇧L** while
  using one, or from the owl menu's first item. Every window the app owns is
  covered, menus and tooltips included.
- **Per-site protection.** List a host such as `youtube.com` and the browser is
  covered whenever a matching page is your front tab, then uncovered when you
  switch away. Subdomains count, look-alikes do not.
- **Capture-gated.** Nyx only draws while a screen capture is actually running,
  and is idle otherwise.
- **Fails closed.** If the local preview stream dies the placeholder stays up,
  the menu bar icon turns red and the dashboard says so.
- **One-line install,** which checks the download against its published
  checksum before installing. Every installer also ships with a `.sha256` and a
  build provenance attestation.
