#!/usr/bin/env bash
# Builds a release YTMusicCompanion.app bundle. Lives in scripts/ but runs from the
# repo root so Package.swift / .build / the app bundle resolve.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="YTMusicCompanion"
BUNDLE="${APP}.app"
VERSION="0.16.1"
BUILD_VERSION="24"
BUNDLE_ID="com.hyeonseswing.YTMusicCompanion"
DISPLAY_NAME="YT Music Companion"
MINIMUM_SYSTEM_VERSION="13.0"
ARCHITECTURES=(arm64 x86_64)
DISCORD_CLIENT_ID="${DISCORD_CLIENT_ID:-}"
# Forward explicit SwiftPM flags (for example a writable cache path in CI).
SWIFT_BUILD_ARGUMENTS=("$@")

verify_architectures() {
    local path="$1"
    local label="$2"
    local actual
    actual="$(lipo -archs "${path}")"
    for architecture in "${ARCHITECTURES[@]}"; do
        case " ${actual} " in
            *" ${architecture} "*) ;;
            *)
                echo "${label} is missing ${architecture}; found: ${actual}" >&2
                exit 1
                ;;
        esac
    done
}

verify_minimum_system_version() {
    local path="$1"
    local label="$2"
    local found=false
    while read -r version; do
        found=true
        if [[ "${version}" != "${MINIMUM_SYSTEM_VERSION}" ]]; then
            echo "${label} requires macOS ${version}; expected ${MINIMUM_SYSTEM_VERSION}" >&2
            exit 1
        fi
    done < <(otool -l "${path}" | awk '$1 == "minos" { print $2 }')
    if [[ "${found}" != true ]]; then
        echo "Could not read ${label} minimum macOS version" >&2
        exit 1
    fi
}

if [[ -n "${DISCORD_CLIENT_ID}" && ! "${DISCORD_CLIENT_ID}" =~ ^[0-9]+$ ]]; then
    echo "DISCORD_CLIENT_ID must contain digits only" >&2
    exit 2
fi

if [[ -z "${DISCORD_CLIENT_ID}" ]]; then
    echo "==> Warning: Discord Rich Presence will be disabled (DISCORD_CLIENT_ID is empty)"
fi

SWIFT_ARCHITECTURE_ARGUMENTS=()
for architecture in "${ARCHITECTURES[@]}"; do
    SWIFT_ARCHITECTURE_ARGUMENTS+=(--arch "${architecture}")
done

echo "==> Compiling Universal release (${ARCHITECTURES[*]})..."
swift build -c release "${SWIFT_ARCHITECTURE_ARGUMENTS[@]}" "${SWIFT_BUILD_ARGUMENTS[@]}"
BIN_DIR="$(
    swift build -c release \
        "${SWIFT_ARCHITECTURE_ARGUMENTS[@]}" \
        "${SWIFT_BUILD_ARGUMENTS[@]}" \
        --show-bin-path
)"
BIN="${BIN_DIR}/${APP}"
verify_architectures "${BIN}" "App binary"
verify_minimum_system_version "${BIN}" "App binary"

echo "==> Compiling artwork bridge..."
MACOSX_DEPLOYMENT_TARGET="${MINIMUM_SYSTEM_VERSION}" \
    ARCHITECTURES="${ARCHITECTURES[*]}" \
    ./scripts/build-artwork-bridge.sh

BRIDGE=".build/artwork-bridge/YTMusicArtworkBridge.dylib"
verify_architectures "${BRIDGE}" "Artwork bridge"
verify_minimum_system_version "${BRIDGE}" "Artwork bridge"

echo "==> Assembling ${BUNDLE}..."
rm -rf "${BUNDLE}"
mkdir -p "${BUNDLE}/Contents/MacOS" "${BUNDLE}/Contents/Resources"
cp "${BIN}" "${BUNDLE}/Contents/MacOS/${APP}"
cp "${BRIDGE}" "${BUNDLE}/Contents/Resources/"
cp "Support/ArtworkBridge/artwork-bridge.pl" "${BUNDLE}/Contents/Resources/"

# Keep SwiftPM's target resource bundle inside the standard app Resources folder.
# AppResources resolves this packaged copy directly and never relies on the
# compiler-generated absolute build-directory fallback in an installed app.
for resbundle in "${BIN_DIR}"/*.bundle; do
    [ -e "${resbundle}" ] && cp -R "${resbundle}" "${BUNDLE}/Contents/Resources/"
done

# SwiftUI's standard localized controls resolve strings from the main app bundle.
# Keep the same source localizations in both the SwiftPM resource bundle (used by
# AppKit's explicit localizer) and the assembled app bundle.
for localization in Sources/YTMusicCompanion/Resources/*.lproj; do
    [ -d "${localization}" ] && cp -R "${localization}" "${BUNDLE}/Contents/Resources/"
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
    <key>CFBundleDevelopmentRegion</key> <string>en</string>
    <key>CFBundleLocalizations</key>
    <array>
        <string>en</string>
        <string>ko</string>
    </array>
    <key>CFBundleIdentifier</key>      <string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key>      <string>${APP}</string>
    <key>CFBundleIconFile</key>        <string>AppIcon</string>
    <key>CFBundleVersion</key>         <string>${BUILD_VERSION}</string>
    <key>CFBundleShortVersionString</key> <string>${VERSION}</string>
    <key>NSHumanReadableCopyright</key> <string>Copyright © 2026 Hyeonse Im</string>
    <key>DiscordClientID</key>         <string>${DISCORD_CLIENT_ID}</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>LSMinimumSystemVersion</key>  <string>${MINIMUM_SYSTEM_VERSION}</string>
    <key>LSUIElement</key>             <true/>
    <key>NSHighResolutionCapable</key> <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key> <true/>
    <key>NSAccessibilityUsageDescription</key>
    <string>Reads the exact title, artist, album, and song URL visible in the YouTube Music player bar.</string>
</dict>
</plist>
PLIST

echo "==> Ad-hoc code-signing..."
codesign --force --deep --sign - "${BUNDLE}" >/dev/null 2>&1 || echo "    (codesign skipped)"

echo "==> Verifying standalone resources..."
RESOURCE_CHECK_OUTPUT="$("${BUNDLE}/Contents/MacOS/${APP}" --check-resources)"
echo "    ${RESOURCE_CHECK_OUTPUT}"
if [[ "${RESOURCE_CHECK_OUTPUT}" != "RESOURCES → application bundle: ok" ]]; then
    echo "Packaged resource verification failed" >&2
    exit 1
fi

echo "OK: built ${BUNDLE}  ->  open ${BUNDLE}"
