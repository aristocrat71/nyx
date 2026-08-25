#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP="build/Nyx.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Nyx "$APP/Contents/MacOS/Nyx"
cp -R .build/release/Nyx_Nyx.bundle "$APP/Contents/Resources/"
cp assets/Info.plist "$APP/Contents/Info.plist"
if [ -f assets/AppIcon.icns ]; then
  cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi
IDENTITY="${CODESIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ] && security find-identity -v -p codesigning | grep -q "Nyx Dev"; then
  IDENTITY="Nyx Dev"
fi
if [ -n "$IDENTITY" ]; then
  codesign --force --sign "$IDENTITY" "$APP"
  echo "signed with '$IDENTITY'"
else
  codesign --force --sign - "$APP"
  echo "signed ad-hoc — Screen Recording grant will reset on rebuild; run scripts/make-dev-cert.sh once to fix"
fi
echo "built $APP"
