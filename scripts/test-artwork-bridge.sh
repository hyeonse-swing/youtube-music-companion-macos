#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

OUTPUT=".build/artwork-bridge-tests/ArtworkBridgeSelectionTests"
mkdir -p "$(dirname "$OUTPUT")" .build/module-cache
xcrun clang -fobjc-arc -fblocks -mmacosx-version-min=13.0 \
    -framework Foundation \
    Support/ArtworkBridge/NowPlayingBridge.m \
    Tests/ArtworkBridgeSelectionTests.m \
    -o "$OUTPUT"
"$OUTPUT"
