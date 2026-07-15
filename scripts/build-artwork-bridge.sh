#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

OUTPUT="${1:-.build/artwork-bridge/YTMusicArtworkBridge.dylib}"
mkdir -p "$(dirname "$OUTPUT")"

xcrun clang \
    -dynamiclib \
    -fobjc-arc \
    -fblocks \
    -framework Foundation \
    Support/ArtworkBridge/ArtworkBridge.m \
    -o "$OUTPUT"

codesign --force --sign - "$OUTPUT" >/dev/null 2>&1 || true
echo "OK: built $OUTPUT"
