#!/usr/bin/env bash
# Installs Nyx from GitHub Releases, refusing any download whose published SHA-256 does not match.
#   curl -fsSL https://raw.githubusercontent.com/aristocrat71/nyx-app/main/install.sh | bash
# NYX_VERSION=nyx-vX.Y.Z pins a release; the latest is used otherwise.
set -euo pipefail

base="https://github.com/aristocrat71/nyx-app/releases"
if [ -n "${NYX_VERSION:-}" ]; then base="$base/download/$NYX_VERSION"; else base="$base/latest/download"; fi

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  amber=$'\033[38;5;214m' bold=$'\033[1m' dim=$'\033[2m' green=$'\033[1;32m' red=$'\033[1;31m' off=$'\033[0m'
else
  amber='' bold='' dim='' green='' red='' off=''
fi
say() { printf '%s==>%s %s\n' "$green" "$off" "$1"; }
die() { printf '%serror:%s %s\n' "$red" "$off" "$1" >&2; exit 1; }

owl=('          ' '   ,___,  ' '   (O,O)  ' '   /)__)  ' '  --"-"-- ' '          ')
name=(' _   _' '| \ | |_   ___  __' '|  \| | | | \ \/ /' '| |\  | |_| |>  <' '|_| \_|\__, /_/\_\' '       |___/')
echo
for i in "${!owl[@]}"; do printf '  %s%s%s  %s%s%s\n' "$amber" "${owl[$i]}" "$off" "$bold" "${name[$i]}" "$off"; done
printf '\n  %sShare your screen, not everything on it.%s\n\n' "$dim" "$off"

case "$(uname -s)" in
  Darwin)
    tmp="$(mktemp -d)"
    trap 'hdiutil detach "$tmp/mnt" -quiet 2>/dev/null || true; rm -rf "$tmp"' EXIT
    say "Downloading Nyx…"
    curl -fL# "$base/Nyx.dmg" -o "$tmp/Nyx.dmg" || die "no Nyx.dmg in that release"
    expected="$(curl -fsSL "$base/Nyx.dmg.sha256" | awk '{print $1}')" || die "no published checksum, refusing to install"
    [ "$expected" = "$(shasum -a 256 "$tmp/Nyx.dmg" | awk '{print $1}')" ] || die "checksum mismatch, refusing to install"
    say "Checksum verified."
    hdiutil attach "$tmp/Nyx.dmg" -nobrowse -quiet -mountpoint "$tmp/mnt"
    osascript -e 'quit app "Nyx"' 2>/dev/null || true
    rm -rf /Applications/Nyx.app
    cp -R "$tmp/mnt/Nyx.app" /Applications/
    # Nyx is not notarized; a download checked above needs no Gatekeeper prompt.
    xattr -dr com.apple.quarantine /Applications/Nyx.app
    say "Installed. Opening Nyx…"
    open /Applications/Nyx.app
    printf '\n  %sLook for the owl in your menu bar.%s\n\n' "$amber" "$off"
    ;;
  *) die "Nyx ships for macOS only right now. Windows and Linux are on the way." ;;
esac
