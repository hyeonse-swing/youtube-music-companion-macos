#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

OUTPUT="${1:-.build/artwork-bridge/YTMusicArtworkBridge.dylib}"
MINIMUM_SYSTEM_VERSION="${MACOSX_DEPLOYMENT_TARGET:-13.0}"
ARCHITECTURES_STRING="${ARCHITECTURES:-arm64 x86_64}"
mkdir -p "$(dirname "$OUTPUT")"

read -r -a ARCHITECTURE_LIST <<< "${ARCHITECTURES_STRING}"
ARCHITECTURE_ARGUMENTS=()
for architecture in "${ARCHITECTURE_LIST[@]}"; do
    ARCHITECTURE_ARGUMENTS+=(-arch "${architecture}")
done

xcrun clang \
    "${ARCHITECTURE_ARGUMENTS[@]}" \
    -dynamiclib \
    -fobjc-arc \
    -fblocks \
    -mmacosx-version-min="${MINIMUM_SYSTEM_VERSION}" \
    -framework Foundation \
    Support/ArtworkBridge/ArtworkBridge.m \
    -o "$OUTPUT"

codesign --force --sign - "$OUTPUT" >/dev/null 2>&1 || true
echo "OK: built $OUTPUT (${ARCHITECTURE_LIST[*]})"
