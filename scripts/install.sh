#!/usr/bin/env bash
# Builds YTMusicCompanion.app and installs it to /Applications.
# After this: launch via Spotlight ("YT Music Companion"), `open -a YTMusicCompanion`,
# or add it as a Login Item (System Settings > General > Login Items) to auto-start.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build-app.sh

DEST="/Applications/YTMusicCompanion.app"
rm -rf "$DEST"
cp -R YTMusicCompanion.app "$DEST"

echo "Installed -> $DEST"
echo "Launch it with:  open -a YTMusicCompanion   (or Spotlight)"
