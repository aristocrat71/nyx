#!/usr/bin/env bash
# Installs Nyx from GitHub Releases, refusing any download whose published SHA-256 does not match.
#   curl -fsSL https://raw.githubusercontent.com/unravel-team/nyx/main/install.sh | bash
# NYX_VERSION=nyx-vX.Y.Z pins a release; the latest is used otherwise.
set -euo pipefail

base="https://github.com/unravel-team/nyx/releases"
api="https://api.github.com/repos/unravel-team/nyx/releases"
if [ -n "${NYX_VERSION:-}" ]; then base="$base/download/$NYX_VERSION" api="$api/tags/$NYX_VERSION"; else base="$base/latest/download" api="$api/latest"; fi

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  amber=$'\033[38;5;214m' bold=$'\033[1m' dim=$'\033[2m' green=$'\033[1;32m' red=$'\033[1;31m' off=$'\033[0m'
else
  amber='' bold='' dim='' green='' red='' off=''
fi
say() { printf '%s==>%s %s\n' "$green" "$off" "$1"; }
die() { printf '%serror:%s %s\n' "$red" "$off" "$1" >&2; exit 1; }

# Draws its own bar from the size the release API reports: the download host often sends none.
fetch() {
  local total got pct pid
  total=$(curl -fsSL --max-time 10 "$api" 2>/dev/null | tr -d ' \n' | sed 's/.*"name":"Nyx.dmg"//' | grep -o '"size":[0-9]*' | head -1 | cut -d: -f2 || true)
  curl -fsSL "$1" -o "$2" &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    if [ -t 1 ]; then
      got=$(stat -f%z "$2" 2>/dev/null || echo 0)
      if [ "${total:-0}" -gt 0 ]; then
        pct=$((got * 100 / total)); [ "$pct" -gt 100 ] && pct=100
        printf '\r  %s[%-30s]%s %3d%%' "$amber" "$(printf '%*s' $((pct * 30 / 100)) '' | tr ' ' '#')" "$off" "$pct"
      else
        printf '\r  %d.%d MB' $((got / 1048576)) $((got % 1048576 * 10 / 1048576))
      fi
    fi
    sleep 0.2
  done
  wait "$pid" || return 1
  [ -t 1 ] && printf '\r  %s[%s]%s 100%%\n' "$amber" "##############################" "$off"
  return 0
}

name=(' _   _' '| \ | |_   ___  __' '|  \| | | | \ \/ /' '| |\  | |_| |>  <' '|_| \_|\__, /_/\_\' '       |___/')
echo
i=0
while IFS= read -r line; do
  n=''; [ "$i" -ge 2 ] && n="${name[$((i - 2))]:-}"
  printf '  %s%-14s%s   %s%s%s\n' "$amber" "$line" "$off" "$bold" "$n" "$off"
  i=$((i + 1))
done <<'OWL'
 /\         /\
 \ '-.___.-' /
 | .-.   .-. |
 |( @ )v( @ )|
 | '-'   '-' |
 |\   \ /   /|
 | \   X   / |
 |  \ / \ /  |
  \__V   V__/
    /_\ /_\
OWL
printf '\n  %sShare your screen, not everything on it.%s\n\n' "$dim" "$off"

case "$(uname -s)" in
  Darwin)
    tmp="$(mktemp -d)"
    trap 'hdiutil detach "$tmp/mnt" -quiet 2>/dev/null || true; rm -rf "$tmp"' EXIT
    say "Downloading Nyx…"
    fetch "$base/Nyx.dmg" "$tmp/Nyx.dmg" || die "no Nyx.dmg in that release"
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
