# Changelog

All notable changes to Nyx are recorded here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and
Nyx uses [semantic versioning](https://semver.org/).

**This file is published.** The release workflow extracts the section matching
the tag being built and uses it as the GitHub release body, so it is what anyone
downloading Nyx reads. A tag with no matching section here fails the release
before anything is built. Write the entry as you merge, not at tag time.

## [0.1.1] - 2026-10-08

### Fixed

- **Nyx quit instantly on launch.** Every 0.1.0 install outside a build machine
  died before drawing anything: the app looked for its bundled fonts and images
  beside the app bundle, and then at a build path that only exists on the
  machine that compiled it. It now reads them from inside the app, where they
  have always been shipped.

## [0.1.0] - 2026-10-08

First release. Nyx sits in the menu bar and blacks out the apps and sites you
list whenever something is capturing your screen — you keep using them normally,
viewers see a placeholder.

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
