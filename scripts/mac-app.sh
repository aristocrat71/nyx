#!/bin/bash
# Builds Nyx.app, signed with the "Nyx Dev" identity when it exists so the Screen Recording
# grant survives rebuilds, ad-hoc otherwise. NYX_UNIVERSAL=1 builds both Mac architectures.
set -euo pipefail
cd "$(dirname "$0")/.."

args=(--bundles app)
[ -n "${NYX_UNIVERSAL:-}" ] && args+=(--target universal-apple-darwin)

# The dev identity is deliberately untrusted, so it is addressed by hash; the exact-line
# match keeps an unrelated "…Nyx Dev…" identity from being picked.
if [ -z "${APPLE_SIGNING_IDENTITY:-}" ]; then
  hash=$(security find-identity -p codesigning 2>/dev/null \
    | grep -E '^ *[0-9]+\) [0-9A-F]+ "Nyx Dev"( \(.*\))?$' | head -1 | awk '{print $2}' || true)
  [ -n "$hash" ] && export APPLE_SIGNING_IDENTITY="$hash"
fi

bun tauri build "${args[@]}"
