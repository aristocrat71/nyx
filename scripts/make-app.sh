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

# The dev identity is deliberately untrusted, so it is addressed by hash;
# the exact-line match keeps an unrelated "…Nyx Dev…" identity from matching.
IDENTITY="${CODESIGN_IDENTITY:-}"
if [ -n "$IDENTITY" ]; then
  SIGN_ARGS+=(--timestamp)
else
  IDENTITY=$(security find-identity -p codesigning 2>/dev/null \
    | grep -E '^ *[0-9]+\) [0-9A-F]+ "Nyx Dev"( \(.*\))?$' \
    | head -1 | awk '{print $2}')
  [ -n "$IDENTITY" ] && SIGN_ARGS+=(--timestamp=none)
fi

if [ -n "$IDENTITY" ]; then
  codesign "${SIGN_ARGS[@]}" --sign "$IDENTITY" "$APP"
  codesign -dvv "$APP" 2>&1 | sed -n 's/^Authority=/signed with /p'
else
  codesign "${SIGN_ARGS[@]}" --timestamp=none --sign - "$APP"
  echo "signed ad-hoc — Screen Recording grant will reset on rebuild; run scripts/make-dev-cert.sh once to fix"
fi

codesign --verify --strict --verbose=2 "$APP"
echo "built $APP"
