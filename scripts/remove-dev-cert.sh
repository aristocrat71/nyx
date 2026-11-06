#!/bin/bash
# Removes the "Nyx Dev" signing identity, its private key, and — for keychains
# set up by older versions of make-dev-cert.sh — its code-signing trust setting.
set -euo pipefail

NAME="Nyx Dev"

if ! security find-certificate -c "$NAME" >/dev/null 2>&1; then
  echo "no '$NAME' certificate found — nothing to do"
  exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

if security find-certificate -c "$NAME" -p > "$TMP/cert.pem" 2>/dev/null; then
  security remove-trusted-cert "$TMP/cert.pem" 2>/dev/null \
    || echo "no trust setting to remove"
fi

while security find-identity -p codesigning 2>/dev/null \
  | grep -qE "^ *[0-9]+\) [0-9A-F]+ \"$NAME\"( \(.*\))?$"; do
  security delete-identity -c "$NAME" >/dev/null
done

echo "removed '$NAME'. Rebuilds are ad-hoc signed again, so macOS will reset"
echo "the Screen Recording grant: tccutil reset ScreenCapture tech.unravel.nyx"
