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

# Hardened runtime keeps a same-user process from injecting into Nyx and
# inheriting its Screen Recording grant. Never add disable-library-validation.
SIGN_ARGS=(--force --options runtime)

IDENTITY="${CODESIGN_IDENTITY:-}"
if [ -n "$IDENTITY" ]; then
  SIGN_ARGS+=(--timestamp)
elif security find-identity -v -p codesigning | grep -q '"Nyx Dev"$'; then
  IDENTITY="Nyx Dev"
  SIGN_ARGS+=(--timestamp=none)
fi

if [ -n "$IDENTITY" ]; then
  codesign "${SIGN_ARGS[@]}" --sign "$IDENTITY" "$APP"
  echo "signed with '$IDENTITY'"
else
  codesign "${SIGN_ARGS[@]}" --timestamp=none --sign - "$APP"
  echo "signed ad-hoc — Screen Recording grant will reset on rebuild; run scripts/make-dev-cert.sh once to fix"
fi

codesign --verify --strict --verbose=2 "$APP"
echo "built $APP"
