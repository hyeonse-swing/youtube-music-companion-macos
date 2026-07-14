#!/usr/bin/env bash
# Builds a release YTMusicCompanion.app bundle. Lives in scripts/ but runs from the
# repo root so Package.swift / .build / the app bundle resolve.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="YTMusicCompanion"
BUNDLE="${APP}.app"
VERSION="0.1.0"
BUILD_VERSION="1"
BUNDLE_ID="com.hyeonseswing.YTMusicCompanion"
DISPLAY_NAME="YT Music Companion"
DISCORD_CLIENT_ID="${DISCORD_CLIENT_ID:-}"

if [[ -n "${DISCORD_CLIENT_ID}" && ! "${DISCORD_CLIENT_ID}" =~ ^[0-9]+$ ]]; then
    echo "DISCORD_CLIENT_ID must contain digits only" >&2
    exit 2
fi

if [[ -z "${DISCORD_CLIENT_ID}" ]]; then
    echo "==> Warning: Discord Rich Presence will be disabled (DISCORD_CLIENT_ID is empty)"
fi

echo "==> Compiling (release)..."
swift build -c release
BIN=".build/release/${APP}"

echo "==> Assembling ${BUNDLE}..."
rm -rf "${BUNDLE}"
mkdir -p "${BUNDLE}/Contents/MacOS" "${BUNDLE}/Contents/Resources"
cp "${BIN}" "${BUNDLE}/Contents/MacOS/${APP}"

# SwiftPM emits target resources into a <pkg>_<target>.bundle next to the binary
# (e.g. the tray icon). Bundle.module finds it under the app's Resources at runtime.
for resbundle in .build/release/*.bundle; do
    [ -e "${resbundle}" ] && cp -R "${resbundle}" "${BUNDLE}/Contents/Resources/"
done

# App icon (regenerate with: swift scripts/make-icon.swift then iconutil).
[ -e scripts/AppIcon.icns ] && cp scripts/AppIcon.icns "${BUNDLE}/Contents/Resources/AppIcon.icns"

cat > "${BUNDLE}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>${APP}</string>
    <key>CFBundleDisplayName</key>     <string>${DISPLAY_NAME}</string>
    <key>CFBundleIdentifier</key>      <string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key>      <string>${APP}</string>
    <key>CFBundleIconFile</key>        <string>AppIcon</string>
    <key>CFBundleVersion</key>         <string>${BUILD_VERSION}</string>
    <key>CFBundleShortVersionString</key> <string>${VERSION}</string>
    <key>DiscordClientID</key>         <string>${DISCORD_CLIENT_ID}</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>LSMinimumSystemVersion</key>  <string>14.0</string>
    <key>LSUIElement</key>             <true/>
    <key>NSHighResolutionCapable</key> <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key> <true/>
</dict>
</plist>
PLIST

echo "==> Ad-hoc code-signing..."
codesign --force --sign - "${BUNDLE}" >/dev/null 2>&1 || echo "    (codesign skipped)"

echo "OK: built ${BUNDLE}  ->  open ${BUNDLE}"
