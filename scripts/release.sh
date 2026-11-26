#!/bin/bash
# Usage: scripts/release.sh 0.2.0. Sets the version everywhere, dates the CHANGELOG's
# Unreleased section, then commits and tags locally. Pushing the tag starts the release.
set -euo pipefail
cd "$(dirname "$0")/.."

v="${1:-}"
[[ "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "usage: $0 X.Y.Z" >&2; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "commit or stash your changes first" >&2; exit 1; }
git rev-parse -q --verify "refs/tags/nyx-v$v" >/dev/null && { echo "nyx-v$v already exists" >&2; exit 1; }
grep -q '^## \[Unreleased\]' CHANGELOG.md || { echo "CHANGELOG.md has no ## [Unreleased] section" >&2; exit 1; }

perl -pi -e 's/^## \[Unreleased\].*/## ['"$v"'] - '"$(date +%F)"'/ if !$done && /^## \[Unreleased\]/ && ++$done' CHANGELOG.md
for f in package.json src-tauri/tauri.conf.json; do
  perl -pi -e 's/"version": "[^"]*"/"version": "'"$v"'"/ if !$done && /"version"/ && ++$done' "$f"
done
perl -pi -e 's/^version = "[^"]*"/version = "'"$v"'"/ if !$done && /^version = / && ++$done' src-tauri/Cargo.toml
perl -0pi -e 's/(name = "nyx"\nversion = )"[^"]*"/$1"'"$v"'"/' src-tauri/Cargo.lock

git commit -qam "nyx: release v$v"
git tag "nyx-v$v"
echo "Tagged nyx-v$v. Push main, then the tag: git push origin main nyx-v$v"
