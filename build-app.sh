#!/bin/bash
# Builds Parrot as a universal .app bundle (arm64 + x86_64) with Info.plist,
# entitlements, and a self-contained llama-server with all required dylibs.
# Usage: ./build-app.sh [release|debug]
set -euo pipefail

CONFIG="${1:-release}"
BINARY_PATH=".build/universal-apple-macosx/${CONFIG}/Parrot"
APP_DIR="Parrot.app"
CONTENTS="${APP_DIR}/Contents"
MACOS="${CONTENTS}/MacOS"
FRAMEWORKS="${CONTENTS}/Frameworks"
ENTITLEMENTS="Resources/Parrot.entitlements"
PLIST_SRC="Resources/Info.plist"
PLIST_DST="${CONTENTS}/Info.plist"
BUNDLE_ID="com.thousandflowers.parrot"

# Signing — set SIGNING_IDENTITY to use Developer ID (required for Gatekeeper + notarization).
# Example: SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./build-app.sh
# Leave unset (or empty) for ad-hoc signing (testers must right-click → Open on first launch).
# Signing identity resolution:
#   1. Explicit SIGNING_IDENTITY env var wins (Developer ID for distribution/notarization).
#   2. Otherwise auto-pick a local "Apple Development" identity if one exists. This gives a STABLE
#      code signature, so macOS (TCC) keeps Accessibility / Input Monitoring grants across rebuilds —
#      ad-hoc signing changes the cdhash every build and silently resets those permissions.
#   3. Fall back to ad-hoc.
if [ -z "${SIGNING_IDENTITY:-}" ]; then
    DEV_ID_HASH="$(security find-identity -v -p codesigning 2>/dev/null | grep "Apple Development" | head -1 | awk '{print $2}')"
    SIGNING_IDENTITY="${DEV_ID_HASH:--}"
fi
if [ "${SIGNING_IDENTITY}" = "-" ]; then
    SIGN_OPTS="--force --timestamp=none"
    echo "[i] Ad-hoc signing (no stable identity). Permissions reset on each rebuild."
elif [[ "${SIGNING_IDENTITY}" == *"Developer ID"* ]]; then
    # Notarization requires the hardened runtime + a secure timestamp.
    SIGN_OPTS="--force --timestamp --options runtime"
    echo "[i] Signing identity (Developer ID, hardened runtime): ${SIGNING_IDENTITY}"
else
    # Stable local identity; hardened runtime on so local builds exercise the release entitlements.
    SIGN_OPTS="--force --timestamp=none --options runtime"
    echo "[i] Signing with stable identity (hardened runtime): ${SIGNING_IDENTITY}"
fi

echo "[*] Building arm64 (${CONFIG})..."
swift build -c "${CONFIG}" --arch arm64
# Ask SwiftPM where products live (swiftbuild: .build/out/Products/<Config>; native: .build/<triple>/<config>).
BIN_DIR="$(swift build -c "${CONFIG}" --arch arm64 --show-bin-path)"
# swiftbuild uses ONE products dir for every arch, so the x86_64 build below would overwrite the
# arm64 binary: keep each slice aside before lipo.
SLICES=".build/universal-apple-macosx/${CONFIG}"
mkdir -p "${SLICES}"
ARM64_PATH="${SLICES}/Parrot-arm64"
cp "${BIN_DIR}/Parrot" "${ARM64_PATH}"

echo "[*] Building x86_64 (${CONFIG})..."
# Only the main app for x86_64 — the completion helper links libllama from Apple-Silicon Homebrew
# and is bundled arm64-only (its target machines are Apple Silicon).
if swift build -c "${CONFIG}" --arch x86_64 --product Parrot 2>/dev/null; then
    X86_PATH="${SLICES}/Parrot-x86_64"
    cp "$(swift build -c "${CONFIG}" --arch x86_64 --show-bin-path)/Parrot" "${X86_PATH}"
    echo "[*] Creating universal binary..."
    mkdir -p ".build/universal-apple-macosx/${CONFIG}"
    lipo -create -output "${BINARY_PATH}" "${ARM64_PATH}" "${X86_PATH}"
    echo "[✓] Universal binary created."
else
    echo "[!] x86_64 build unavailable — bundling arm64 only."
    BINARY_PATH="${ARM64_PATH}"
fi

echo "[*] Packaging as ${APP_DIR}..."
rm -rf "${APP_DIR}"
mkdir -p "${MACOS}"
mkdir -p "${CONTENTS}/Resources"
mkdir -p "${FRAMEWORKS}"

# Copy .lproj localization directories
for lproj in Resources/*.lproj; do
    [ -d "$lproj" ] && cp -r "$lproj" "${CONTENTS}/Resources/"
done
# App icon (Finder, Dock, Gatekeeper dialogs). Info.plist gets CFBundleIconFile below.
cp Resources/AppIcon.icns "${CONTENTS}/Resources/AppIcon.icns"

cp "${BINARY_PATH}" "${MACOS}/Parrot"
install_name_tool -add_rpath "@loader_path/../Frameworks" "${MACOS}/Parrot"

# In-process completion helper (arm64 only). Reuses the bundled libllama/ggml dylibs in Frameworks.
HELPER_SRC="${BIN_DIR}/ParrotCompletionHelper"
if [ -f "${HELPER_SRC}" ]; then
    echo "[*] Bundling ParrotCompletionHelper..."
    cp "${HELPER_SRC}" "${MACOS}/ParrotCompletionHelper"
else
    echo "[!] ParrotCompletionHelper not built — inline completion will use the server fallback."
fi


# Embed Sparkle.framework (always from arm64 build — framework is architecture-independent)
SPARKLE_SRC="${BIN_DIR}/Sparkle.framework"
if [ -d "${SPARKLE_SRC}" ]; then
    ditto "${SPARKLE_SRC}" "${FRAMEWORKS}/Sparkle.framework"   # cp -r flattens Versions/Current symlinks -> "bundle format is ambiguous"
else
    echo "[!] Sparkle.framework not found at ${SPARKLE_SRC}" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Bundle llama-server + the completion helper + every Homebrew dylib they need
# (Apple Silicon only: the bundled dylibs come from the arm64 Homebrew prefix, so an x86_64
# llama-server slice could never load them.)
# ---------------------------------------------------------------------------
# shellcheck source=scripts/bundle-deps.sh
source scripts/bundle-deps.sh
bundle_swiftpm_resources "${BIN_DIR}" "${CONTENTS}/Resources"
LLAMA_BIN="${BREW_PREFIX}/bin/llama-server"
if [ -x "${LLAMA_BIN}" ]; then
    echo "[*] Bundling llama-server + dylibs..."
    cp "$(readlink -f "${LLAMA_BIN}")" "${MACOS}/llama-server"
    chmod u+w,+x "${MACOS}/llama-server"
    bundle_closure "${MACOS}/llama-server"
else
    echo "[!] llama-server not found. Install with: brew install llama.cpp" >&2
    echo "    The app will look for llama-server in Homebrew at runtime." >&2
fi
[ -f "${MACOS}/ParrotCompletionHelper" ] && bundle_closure "${MACOS}/ParrotCompletionHelper"
if [ -x "${LLAMA_BIN}" ] || [ -f "${MACOS}/ParrotCompletionHelper" ]; then
    bundle_ggml_plugins "${MACOS}"
    echo "[✓] Bundled $(find "${FRAMEWORKS}" -maxdepth 1 -name "*.dylib" | wc -l | tr -d " ") dylibs, $(find "${MACOS}" -maxdepth 1 -name "libggml-*.so" | wc -l | tr -d " ") ggml backends."
    echo "[*] Signing bundled dylibs + binaries..."
    for bin in "${FRAMEWORKS}"/*.dylib "${MACOS}"/libggml-*.so "${MACOS}/llama-server"; do
        # shellcheck disable=SC2086
        [ -f "$bin" ] && codesign --sign "${SIGNING_IDENTITY}" ${SIGN_OPTS} "$bin"
    done
fi

# ---------------------------------------------------------------------------

# Copy Info.plist and resolve Xcode-style variable tokens
sed \
  -e "s/\$(DEVELOPMENT_LANGUAGE)/en/g" \
  -e "s/\$(EXECUTABLE_NAME)/Parrot/g" \
  -e "s/\$(PRODUCT_BUNDLE_IDENTIFIER)/${BUNDLE_ID}/g" \
  -e "s/\$(PRODUCT_NAME)/Parrot/g" \
  "${PLIST_SRC}" > "${PLIST_DST}"
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "${PLIST_DST}" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIcon" "${PLIST_DST}"
# Release builds stamp the tag version.
if [ -n "${APP_VERSION:-}" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${APP_VERSION}" "${PLIST_DST}"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(git rev-list --count HEAD 2>/dev/null || echo 1)" "${PLIST_DST}"
fi

echo "[*] Signing Sparkle sub-components (inside-out)..."
SPARKLE_VB="${FRAMEWORKS}/Sparkle.framework/Versions/B"
for xpc in "${SPARKLE_VB}/XPCServices"/*.xpc; do
    # shellcheck disable=SC2086
    [ -d "$xpc" ] && codesign --sign "${SIGNING_IDENTITY}" ${SIGN_OPTS} "$xpc"
done
# shellcheck disable=SC2086
[ -d "${SPARKLE_VB}/Updater.app" ] && \
    codesign --sign "${SIGNING_IDENTITY}" ${SIGN_OPTS} "${SPARKLE_VB}/Updater.app"
# shellcheck disable=SC2086
[ -f "${SPARKLE_VB}/Autoupdate" ] && \
    codesign --sign "${SIGNING_IDENTITY}" ${SIGN_OPTS} "${SPARKLE_VB}/Autoupdate"
# shellcheck disable=SC2086
codesign --sign "${SIGNING_IDENTITY}" ${SIGN_OPTS} "${SPARKLE_VB}/Sparkle"

# shellcheck disable=SC2086
[ -f "${MACOS}/ParrotCompletionHelper" ] && codesign --sign "${SIGNING_IDENTITY}" ${SIGN_OPTS} "${MACOS}/ParrotCompletionHelper"

echo "[*] Signing Parrot.app..."
# shellcheck disable=SC2086
codesign \
  --sign "${SIGNING_IDENTITY}" \
  --entitlements "${ENTITLEMENTS}" \
  ${SIGN_OPTS} \
  "${APP_DIR}"

# ---------------------------------------------------------------------------
# Notarization (requires Developer ID + NOTARIZE_* env vars)
# Set: NOTARIZE_TEAM_ID, NOTARIZE_APPLE_ID, NOTARIZE_PASSWORD (app-specific pwd)
# ---------------------------------------------------------------------------
if [ "${SIGNING_IDENTITY}" != "-" ] && \
   [ -n "${NOTARIZE_TEAM_ID:-}" ] && \
   [ -n "${NOTARIZE_APPLE_ID:-}" ] && \
   [ -n "${NOTARIZE_PASSWORD:-}" ]; then
    echo "[*] Zipping for notarization..."
    ZIP_NAME="${APP_DIR%.app}.zip"
    ditto -c -k --keepParent "${APP_DIR}" "${ZIP_NAME}"

    echo "[*] Submitting to Apple notarization service (may take a few minutes)..."
    xcrun notarytool submit "${ZIP_NAME}" \
        --team-id "${NOTARIZE_TEAM_ID}" \
        --apple-id "${NOTARIZE_APPLE_ID}" \
        --password "${NOTARIZE_PASSWORD}" \
        --wait

    echo "[*] Stapling ticket..."
    xcrun stapler staple "${APP_DIR}"
    rm -f "${ZIP_NAME}"
    echo "[✓] Notarization complete."
else
    if [ "${SIGNING_IDENTITY}" != "-" ]; then
        echo "[!] NOTARIZE_* env vars not set — skipping notarization."
    fi
fi

# ---------------------------------------------------------------------------
# DMG packaging — styled with drag-to-Applications background
# ---------------------------------------------------------------------------
DMG_NAME="${APP_DIR%.app}.dmg"
DMG_TMP="${APP_DIR%.app}-rw.dmg"
DMG_VOL="Parrot"

echo "[*] Creating ${DMG_NAME} (styled drag-to-Applications)..."

# Detach any previous mount with the same name
hdiutil detach "/Volumes/${DMG_VOL}" -quiet 2>/dev/null || true

# Calculate size with 30 MB headroom for .DS_Store / Finder metadata
APP_MB=$(du -sm "${APP_DIR}" | awk '{print $1}')
DMG_MB=$((APP_MB + 30))

# Generate background image (1120×680 px, 2× Retina — displayed at 560×340)
# Arrow: bar x=440-660 y=325-355, head x=660-740 tapering at y=340
python3 - /tmp/parrot_dmg_bg.png << 'PYEOF'
import struct, zlib, sys
W, H = 1120, 680
BG    = (246, 246, 248)   # macOS window background
ARROW = (174, 174, 178)   # systemGray2
rows = []
for y in range(H):
    row = bytearray([0])
    for x in range(W):
        r, g, b = BG
        if 440 <= x < 660 and 325 <= y < 355:
            r, g, b = ARROW
        elif 660 <= x < 740:
            t = (x - 660) / 80.0
            half = int(30 * (1 - t))
            if 340 - half <= y < 340 + half:
                r, g, b = ARROW
        row.extend([r, g, b])
    rows.append(bytes(row))
raw  = b''.join(rows)
comp = zlib.compress(raw, 6)
def chunk(n, d):
    c = n + d
    return struct.pack('>I', len(d)) + c + struct.pack('>I', zlib.crc32(c) & 0xffffffff)
png = (b'\x89PNG\r\n\x1a\n'
     + chunk(b'IHDR', struct.pack('>IIBBBBB', W, H, 8, 2, 0, 0, 0))
     + chunk(b'IDAT', comp)
     + chunk(b'IEND', b''))
open(sys.argv[1], 'wb').write(png)
PYEOF

# Create blank writable DMG
rm -f "${DMG_TMP}"
hdiutil create -size "${DMG_MB}m" -volname "${DMG_VOL}" \
    -fs HFS+ "${DMG_TMP}" > /dev/null

# Mount at a fixed path to avoid races
hdiutil attach -readwrite -noverify -noautoopen \
    -mountpoint "/Volumes/${DMG_VOL}" "${DMG_TMP}" > /dev/null

MOUNT="/Volumes/${DMG_VOL}"

# Populate
ditto "${APP_DIR}" "${MOUNT}/${APP_DIR}"
ln -s /Applications "${MOUNT}/Applications"
mkdir -p "${MOUNT}/.background"
cp /tmp/parrot_dmg_bg.png "${MOUNT}/.background/background.png"
chflags hidden "${MOUNT}/.background" 2>/dev/null || true

# Configure window appearance and icon positions via Finder
osascript << APPLESCRIPT
tell application "Finder"
    tell disk "${DMG_VOL}"
        open
        delay 1
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {100, 100, 660, 440}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 128
        set background picture of viewOptions to file ".background:background.png"
        set position of item "Parrot.app" of container window to {140, 170}
        set position of item "Applications" of container window to {420, 170}
        close
        open
        update without registering applications
        delay 3
        close
    end tell
end tell
APPLESCRIPT

sync

# Unmount
hdiutil detach "${MOUNT}" -quiet

# Convert to final compressed read-only DMG
rm -f "${DMG_NAME}"
hdiutil convert "${DMG_TMP}" -format UDZO -imagekey zlib-level=9 \
    -o "${DMG_NAME}" > /dev/null
rm -f "${DMG_TMP}"
rm -f /tmp/parrot_dmg_bg.png

echo "[✓] ${DMG_NAME} ready."

echo ""
echo "[✓] Build complete: ${APP_DIR} + ${DMG_NAME}"
if [ "${SIGNING_IDENTITY}" = "-" ]; then
    echo "    First-launch: right-click Parrot.app → Open to bypass Gatekeeper."
    echo "    For distribution without warnings: set SIGNING_IDENTITY + NOTARIZE_* and rebuild."
fi

# Wren is built by ./build-wren.sh (standalone, bundled model). Don't derive it from Parrot.app
# here: that copy has no model and overwrote the real Wren.app in this directory.
