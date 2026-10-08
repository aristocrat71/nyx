#!/usr/bin/env bash
# Nyx installer for macOS: downloads the release DMG, verifies its published
# SHA-256 (fails closed), installs to /Applications. NYX_VERSION pins a version.
set -euo pipefail

REPO="aristocrat71/nyx"
API_BASE="https://api.github.com/repos/${REPO}/releases"
API="${API_BASE}/latest"
[ -n "${NYX_VERSION:-}" ] && API="${API_BASE}/tags/${NYX_VERSION}"

say() { printf '\033[1;32m==>\033[0m %s\n' "$1"; }
warn() { printf '\033[1;33mnote:\033[0m %s\n' "$1"; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$1" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || die "Nyx is macOS only — this is $(uname -s)"
# Matches LSMinimumSystemVersion in the bundle; an older macOS can install it
# but the app will not launch.
os_version="$(sw_vers -productVersion)"
[ "${os_version%%.*}" -ge 14 ] \
  || die "Nyx needs macOS 14 or later (this is $os_version)"

# First asset download URL whose filename matches the given regex.
asset_url() {
  curl -fsSL "$API" 2>/dev/null \
    | grep -o '"browser_download_url": *"[^"]*"' \
    | sed 's/.*"\(https[^"]*\)"/\1/' \
    | grep -iE "$1" \
    | head -1
}

sha256_of() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    die "no sha256 tool (shasum/sha256sum) found to verify the download"
  fi
}

# Verify $1 against the "<file>.sha256" published next to its release asset ($2).
# Aborts on a missing checksum (fail closed) or any mismatch.
verify_sha() {
  local file="$1" url="$2" sums expected actual
  say "Verifying checksum…"
  sums="$(curl -fsSL "${url}.sha256")" \
    || die "no published checksum for $(basename "$url") — refusing to install"
  expected="$(printf '%s\n' "$sums" | awk '{print $1}' | head -1)"
  [ -n "$expected" ] || die "empty checksum for $(basename "$url")"
  actual="$(sha256_of "$file")"
  [ "$expected" = "$actual" ] \
    || die "checksum mismatch for $(basename "$url") (expected $expected, got $actual) — aborting"
}

say "Fetching the Nyx release…"
url="$(asset_url '\.dmg$')" || true
[ -n "${url:-}" ] || die "no macOS .dmg in that release"

tmp="$(mktemp -d)"
trap 'hdiutil detach "$tmp/mnt" -quiet 2>/dev/null || true; rm -rf "$tmp"' EXIT
say "Downloading $(basename "$url")…"
curl -fSL --progress-bar "$url" -o "$tmp/nyx.dmg"
verify_sha "$tmp/nyx.dmg" "$url"

mkdir -p "$tmp/mnt"
hdiutil attach "$tmp/nyx.dmg" -nobrowse -quiet -mountpoint "$tmp/mnt"
app="$(/usr/bin/find "$tmp/mnt" -maxdepth 1 -name '*.app' | head -1)"
[ -n "$app" ] || die "no .app inside the dmg"
dest="/Applications/$(basename "$app")"

# Nyx is a menu bar app and may be running over its own bundle.
if pgrep -x Nyx >/dev/null 2>&1; then
  say "Quitting the running Nyx…"
  osascript -e 'tell application id "tech.unravel.nyx" to quit' 2>/dev/null \
    || pkill -x Nyx 2>/dev/null || true
  for _ in 1 2 3 4 5; do
    pgrep -x Nyx >/dev/null 2>&1 || break
    sleep 1
  done
fi

say "Installing to /Applications…"
rm -rf "$dest"
# ditto rather than cp -R: it preserves the signature's extended attributes, and
# macOS keys the Screen Recording grant to that signature.
ditto "$app" "$dest"

if spctl --assess --type exec "$dest" >/dev/null 2>&1; then
  say "Done — launch Nyx from /Applications or Spotlight, and grant Screen Recording when it asks."
else
  # Not notarized yet, so Gatekeeper would block the first launch. The download
  # was already checksum-verified, which the click-through prompt never does.
  xattr -dr com.apple.quarantine "$dest" 2>/dev/null || true
  warn "this build is not notarized — quarantine cleared so it opens without a Gatekeeper prompt"
  say "Done — launch Nyx from /Applications or Spotlight, and grant Screen Recording when it asks."
fi
