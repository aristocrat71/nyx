#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Nyx.app"
[ -d "$APP" ] || { echo "no $APP — run make app first" >&2; exit 1; }

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
DMG="build/Nyx-$VERSION.dmg"

STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT
# ditto rather than cp -R: it preserves the signature's extended attributes.
ditto "$APP" "$STAGING/Nyx.app"
ln -s /Applications "$STAGING/Applications"

rm -f "$DMG"
hdiutil create -volname "Nyx $VERSION" -srcfolder "$STAGING" \
  -format UDZO -fs HFS+ -quiet "$DMG"

# Apple only notarizes a signed disk image, and Gatekeeper checks the image
# itself before the app inside it.
if [ -n "${CODESIGN_IDENTITY:-}" ]; then
  codesign --force --timestamp --sign "$CODESIGN_IDENTITY" "$DMG"
  codesign --verify --strict --verbose=2 "$DMG"
fi

echo "built $DMG"
