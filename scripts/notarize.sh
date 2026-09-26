#!/bin/bash
set -euo pipefail

TARGET="${1:-}"
[ -n "$TARGET" ] || { echo "usage: notarize.sh <path to .app or .dmg>" >&2; exit 1; }
: "${APPLE_ID:?set APPLE_ID}" "${APPLE_TEAM_ID:?set APPLE_TEAM_ID}" "${APPLE_APP_PASSWORD:?set APPLE_APP_PASSWORD}"

SUBMISSION="$TARGET"
if [[ "$TARGET" == *.app ]]; then
  TMP=$(mktemp -d)
  trap 'rm -rf "$TMP"' EXIT
  SUBMISSION="$TMP/$(basename "${TARGET%.app}").zip"
  # notarytool takes an archive, not a bundle, and ditto is the only zip that
  # keeps the signature intact.
  ditto -c -k --keepParent "$TARGET" "$SUBMISSION"
fi

xcrun notarytool submit "$SUBMISSION" \
  --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_PASSWORD" \
  --wait --timeout 30m

# Stapling the ticket onto the artifact lets a first launch verify offline.
xcrun stapler staple "$TARGET"
xcrun stapler validate "$TARGET"
