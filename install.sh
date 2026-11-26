#!/usr/bin/env bash
# Installs Nyx from GitHub Releases, refusing any download whose published SHA-256 does not match.
#   curl -fsSL https://raw.githubusercontent.com/aristocrat71/nyx-app/main/install.sh | bash
# NYX_VERSION=nyx-vX.Y.Z pins a release; the latest is used otherwise.
set -euo pipefail

base="https://github.com/aristocrat71/nyx-app/releases"
if [ -n "${NYX_VERSION:-}" ]; then base="$base/download/$NYX_VERSION"; else base="$base/latest/download"; fi

say() { printf '\033[1;32m==>\033[0m %s\n' "$1"; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$1" >&2; exit 1; }

case "$(uname -s)" in
  Darwin)
    tmp="$(mktemp -d)"
    trap 'hdiutil detach "$tmp/mnt" -quiet 2>/dev/null || true; rm -rf "$tmp"' EXIT
    say "Downloading Nyx…"
    curl -fL# "$base/Nyx.dmg" -o "$tmp/Nyx.dmg" || die "no Nyx.dmg in that release"
    expected="$(curl -fsSL "$base/Nyx.dmg.sha256" | awk '{print $1}')" || die "no published checksum, refusing to install"
    [ "$expected" = "$(shasum -a 256 "$tmp/Nyx.dmg" | awk '{print $1}')" ] || die "checksum mismatch, refusing to install"
    hdiutil attach "$tmp/Nyx.dmg" -nobrowse -quiet -mountpoint "$tmp/mnt"
    osascript -e 'quit app "Nyx"' 2>/dev/null || true
    rm -rf /Applications/Nyx.app
    cp -R "$tmp/mnt/Nyx.app" /Applications/
    # Nyx is not notarized; a download checked above needs no Gatekeeper prompt.
    xattr -dr com.apple.quarantine /Applications/Nyx.app
    say "Installed. Opening Nyx…"
    open /Applications/Nyx.app
    ;;
  *) die "Nyx ships for macOS only right now. Windows and Linux are on the way." ;;
esac
