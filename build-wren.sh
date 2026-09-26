#!/bin/bash
# Builds Wren as a STANDALONE .app with an LLM bundled inside — runs out of the box, no model
# download, fully offline. Independent of Parrot's grammar stack at runtime: drops llama-server,
# its TLS/mtmd dylibs, and uses only the in-process ParrotCompletionHelper + libllama.
#
# Result: Wren.app (com.thousandflowers.wren) containing app + helper + libllama/ggml + one .gguf.
# Target footprint: model (~492MB) + ~30MB app ≈ <550MB.
#
# Usage: MODEL_PATH=/path/to/model.gguf ./build-wren.sh [release|debug]
#   MODEL_PATH defaults to the qwen2.5-0.5b model in Parrot's Application Support dir.
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-release}"
APP_DIR="Wren.app"
CONTENTS="${APP_DIR}/Contents"
MACOS="${CONTENTS}/MacOS"
FRAMEWORKS="${CONTENTS}/Frameworks"
RES="${CONTENTS}/Resources"
ENTITLEMENTS="Resources/Parrot.entitlements"
PLIST_SRC="Resources/Info.plist"
PLIST_DST="${CONTENTS}/Info.plist"
BUNDLE_ID="com.thousandflowers.wren"

MODEL_PATH="${MODEL_PATH:-$HOME/Library/Application Support/Parrot/Models/qwen2.5-0.5b-instruct-q4_k_m.gguf}"
if [ ! -f "${MODEL_PATH}" ]; then
    echo "[!] Model not found: ${MODEL_PATH}" >&2
    echo "    Set MODEL_PATH=/path/to/model.gguf and re-run." >&2
    exit 1
fi

# --- Signing identity (stable Apple Development keeps TCC grants across rebuilds) ---
if [ -z "${SIGNING_IDENTITY:-}" ]; then
    DEV_ID_HASH="$(security find-identity -v -p codesigning 2>/dev/null | grep "Apple Development" | head -1 | awk '{print $2}')"
    SIGNING_IDENTITY="${DEV_ID_HASH:--}"
fi
# Hardened runtime is mandatory for notarization; Developer ID builds also need a secure timestamp.
# Local Apple Development builds keep --timestamp=none (offline-friendly) but still enable the
# hardened runtime so the same entitlements get exercised before a release.
if [ "${SIGNING_IDENTITY}" = "-" ]; then
    SIGN_OPTS="--force --timestamp=none"
    echo "[i] Ad-hoc signing."
elif [[ "${SIGNING_IDENTITY}" == *"Developer ID"* ]]; then
    SIGN_OPTS="--force --timestamp --options runtime"
    echo "[i] Signing identity (Developer ID, hardened runtime): ${SIGNING_IDENTITY}"
else
    SIGN_OPTS="--force --timestamp=none --options runtime"
    echo "[i] Signing identity (hardened runtime): ${SIGNING_IDENTITY}"
fi

echo "[*] Building arm64 (${CONFIG})..."
swift build -c "${CONFIG}" --arch arm64 --product Parrot
swift build -c "${CONFIG}" --arch arm64 --product ParrotCompletionHelper

BIN=".build/arm64-apple-macosx/${CONFIG}/Parrot"
HELPER=".build/arm64-apple-macosx/${CONFIG}/ParrotCompletionHelper"
SPARKLE_SRC=".build/arm64-apple-macosx/${CONFIG}/Sparkle.framework"

echo "[*] Assembling ${APP_DIR}..."
rm -rf "${APP_DIR}"
mkdir -p "${MACOS}" "${FRAMEWORKS}" "${RES}/Models"

cp "${BIN}" "${MACOS}/Parrot"
install_name_tool -add_rpath "@loader_path/../Frameworks" "${MACOS}/Parrot" 2>/dev/null || true

cp "${HELPER}" "${MACOS}/ParrotCompletionHelper"
install_name_tool -add_rpath "@loader_path/../Frameworks" "${MACOS}/ParrotCompletionHelper" 2>/dev/null || true
install_name_tool -delete_rpath "/opt/homebrew/lib" "${MACOS}/ParrotCompletionHelper" 2>/dev/null || true

# MLX Metal shaders: SwiftPM cannot compile .metal sources (mlx-swift README), so reuse the
# metallib produced by an xcodebuild pass when available. Without it the MLX backend reports
# "unavailable" at runtime (it does not crash).
# `|| true`: under `set -o pipefail` a missing metallib would otherwise abort the whole build.
MLX_METALLIB=$(ls .xcbuild/Build/Products/*/mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib 2>/dev/null | head -1 || true)
if [ -n "${MLX_METALLIB}" ]; then
    cp "${MLX_METALLIB}" "${MACOS}/mlx.metallib"
    echo "[✓] MLX metallib bundled"
else
    echo "[i] No MLX metallib (run 'xcodebuild build -scheme Parrot-Package -destination platform=macOS -derivedDataPath .xcbuild' once to enable the MLX backend)"
fi

# App icon (Wren's own; Resources/AppIcon.icns is Parrot's)
cp Resources/WrenIcon.icns "${RES}/AppIcon.icns"

# Menu bar icon (template image for NSImageView)
cp Resources/MenuIcon.png "${RES}/"
cp Resources/MenuIcon@2x.png "${RES}/" 2>/dev/null || true

# Localizations (small) so system strings resolve.
for lproj in Resources/*.lproj; do [ -d "$lproj" ] && cp -r "$lproj" "${RES}/"; done

# The bundled model — this is what makes Wren self-contained.
echo "[*] Bundling model $(basename "${MODEL_PATH}") ($(du -h "${MODEL_PATH}" | awk '{print $1}'))..."
cp "${MODEL_PATH}" "${RES}/Models/"

# Sparkle (the main binary links it). Architecture-independent framework.
[ -d "${SPARKLE_SRC}" ] || { echo "[!] Sparkle.framework missing" >&2; exit 1; }
ditto "${SPARKLE_SRC}" "${FRAMEWORKS}/Sparkle.framework"   # ditto keeps Versions/Current symlinks (cp -r flattens them)

# --- libllama + everything it transitively needs from Homebrew (ggml, libomp, ...) ---
# Walk `otool -L` from libllama, copy each /opt/homebrew dylib into Frameworks and rewrite the
# reference to @rpath. Data-driven on purpose: ggml's link set changes between bottles (0.23 added
# libomp) and a missing one means "Library not loaded" on every Mac without Homebrew.
BREW_PREFIX="$(brew --prefix 2>/dev/null || echo /opt/homebrew)"
brew_deps() {   # $1 = binary → its /opt/homebrew dependencies, one per line
    otool -L "$1" | awk 'NR>1 {print $1}' | grep "^${BREW_PREFIX}/" || true
}
bundle_dylib() {   # $1 = Homebrew dylib path (as referenced by a dependent)
    local name real dep
    name="$(basename "$1")"
    [ -f "${FRAMEWORKS}/${name}" ] && return 0
    real="$(readlink -f "$1" 2>/dev/null || realpath "$1")"
    [ -f "${real}" ] || { echo "[!] Missing dylib: $1" >&2; exit 1; }
    cp "${real}" "${FRAMEWORKS}/${name}"
    chmod u+w "${FRAMEWORKS}/${name}"
    install_name_tool -id "@rpath/${name}" "${FRAMEWORKS}/${name}" 2>/dev/null || true
    install_name_tool -add_rpath "@loader_path" "${FRAMEWORKS}/${name}" 2>/dev/null || true
    while read -r dep; do
        [ -n "${dep}" ] || continue
        install_name_tool -change "${dep}" "@rpath/$(basename "${dep}")" "${FRAMEWORKS}/${name}" 2>/dev/null || true
        bundle_dylib "${dep}"
    done < <(brew_deps "${FRAMEWORKS}/${name}")
}
bundle_dylib "${BREW_PREFIX}/opt/llama.cpp/lib/libllama.0.dylib"
while read -r dep; do
    [ -n "${dep}" ] || continue
    install_name_tool -change "${dep}" "@rpath/$(basename "${dep}")" "${MACOS}/ParrotCompletionHelper" 2>/dev/null || true
done < <(brew_deps "${MACOS}/ParrotCompletionHelper")
# ggml >= 0.23 loads its compute backends (Metal, CPU variants, BLAS) as plugins from
# <ggml>/libexec at runtime; the loader also searches the executable's directory, so ship
# them next to the helper. Whatever the bottle provides gets bundled - no fixed list.
GGML_PLUGIN_DIR="$(brew --prefix ggml 2>/dev/null)/libexec"
for plugin in "${GGML_PLUGIN_DIR}"/libggml-*.so; do
    [ -f "${plugin}" ] || { echo "[!] No ggml backend plugins in ${GGML_PLUGIN_DIR}" >&2; exit 1; }
    name="$(basename "${plugin}")"
    cp "${plugin}" "${MACOS}/${name}"
    chmod u+w "${MACOS}/${name}"
    install_name_tool -add_rpath "@loader_path/../Frameworks" "${MACOS}/${name}" 2>/dev/null || true
    while read -r dep; do
        [ -n "${dep}" ] || continue
        install_name_tool -change "${dep}" "@rpath/$(basename "${dep}")" "${MACOS}/${name}" 2>/dev/null || true
        bundle_dylib "${dep}"
    done < <(brew_deps "${MACOS}/${name}")
done
echo "[✓] Bundled ggml backends: $(find "${MACOS}" -maxdepth 1 -name "libggml-*.so" | wc -l | tr -d " ")"
echo "[✓] Bundled dylibs: $(find "${FRAMEWORKS}" -maxdepth 1 -name "*.dylib" | wc -l | tr -d " ")"

# --- Info.plist (Wren identity) ---
sed \
  -e "s/\$(DEVELOPMENT_LANGUAGE)/en/g" \
  -e "s/\$(EXECUTABLE_NAME)/Parrot/g" \
  -e "s/\$(PRODUCT_BUNDLE_IDENTIFIER)/${BUNDLE_ID}/g" \
  -e "s/\$(PRODUCT_NAME)/Wren/g" \
  "${PLIST_SRC}" > "${PLIST_DST}"
/usr/libexec/PlistBuddy -c "Set :CFBundleName Wren" "${PLIST_DST}" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :CFBundleName string Wren" "${PLIST_DST}"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName Wren" "${PLIST_DST}" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string Wren" "${PLIST_DST}"
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "${PLIST_DST}" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIcon" "${PLIST_DST}"
# Release builds stamp the tag version (Info.plist carries Parrot's version otherwise).
if [ -n "${APP_VERSION:-}" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${APP_VERSION}" "${PLIST_DST}"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(git rev-list --count HEAD 2>/dev/null || echo 1)" "${PLIST_DST}"
fi

# --- Sign inside-out ---
echo "[*] Signing..."
for dylib in "${FRAMEWORKS}"/*.dylib; do
    codesign --sign "${SIGNING_IDENTITY}" ${SIGN_OPTS} "$dylib"
done
SPARKLE_VB="${FRAMEWORKS}/Sparkle.framework/Versions/B"
for xpc in "${SPARKLE_VB}/XPCServices"/*.xpc; do [ -d "$xpc" ] && codesign --sign "${SIGNING_IDENTITY}" ${SIGN_OPTS} "$xpc"; done
[ -d "${SPARKLE_VB}/Updater.app" ] && codesign --sign "${SIGNING_IDENTITY}" ${SIGN_OPTS} "${SPARKLE_VB}/Updater.app"
[ -f "${SPARKLE_VB}/Autoupdate" ] && codesign --sign "${SIGNING_IDENTITY}" ${SIGN_OPTS} "${SPARKLE_VB}/Autoupdate"
[ -f "${SPARKLE_VB}/Sparkle" ] && codesign --sign "${SIGNING_IDENTITY}" ${SIGN_OPTS} "${SPARKLE_VB}/Sparkle"
for plugin in "${MACOS}"/libggml-*.so; do codesign --sign "${SIGNING_IDENTITY}" ${SIGN_OPTS} "$plugin"; done
codesign --sign "${SIGNING_IDENTITY}" ${SIGN_OPTS} "${MACOS}/ParrotCompletionHelper"
codesign --sign "${SIGNING_IDENTITY}" --entitlements "${ENTITLEMENTS}" ${SIGN_OPTS} "${APP_DIR}"

echo ""
echo "[✓] ${APP_DIR} ready — $(du -sh "${APP_DIR}" | awk '{print $1}') total."
[ "${SIGNING_IDENTITY}" = "-" ] && echo "    First launch: right-click Wren.app → Open."

# --- Optional: notarize + DMG packaging (set WREN_DMG=1; CI/release path) ---
# Local debug builds skip this. A real `brew install --cask wren` needs Wren.dmg uploaded
# to GitHub Releases — that is what this produces.
if [ "${WREN_DMG:-0}" = "1" ]; then
    ZIP_NAME="Wren.zip"

    # Notarize (Developer ID + NOTARIZE_* required; ad-hoc builds skip this).
    if [ "${SIGNING_IDENTITY}" != "-" ] && \
       [ -n "${NOTARIZE_TEAM_ID:-}" ] && \
       [ -n "${NOTARIZE_APPLE_ID:-}" ] && \
       [ -n "${NOTARIZE_PASSWORD:-}" ]; then
        echo "[*] Notarizing ${APP_DIR}..."
        rm -f "${ZIP_NAME}"
        ditto -c -k --keepParent "${APP_DIR}" "${ZIP_NAME}"
        xcrun notarytool submit "${ZIP_NAME}" \
            --team-id "${NOTARIZE_TEAM_ID}" \
            --apple-id "${NOTARIZE_APPLE_ID}" \
            --password "${NOTARIZE_PASSWORD}" \
            --wait
        xcrun stapler staple "${APP_DIR}"
        rm -f "${ZIP_NAME}"
        echo "[✓] Notarized + stapled."
    else
        echo "[i] NOTARIZE_* not set (or ad-hoc) — DMG will be unnotarized; users right-click → Open."
    fi

    DMG_NAME="Wren.dmg"
    DMG_TMP="Wren-rw.dmg"
    DMG_VOL="Wren"
    APP_MB=$(du -sm "${APP_DIR}" | awk '{print $1}')
    DMG_MB=$((APP_MB + 30))

    echo "[*] Creating ${DMG_NAME} (drag-to-Applications)..."
    hdiutil detach "/Volumes/${DMG_VOL}" -quiet 2>/dev/null || true
    rm -f "${DMG_TMP}" "${DMG_NAME}"
    hdiutil create -size "${DMG_MB}m" -volname "${DMG_VOL}" -fs HFS+ "${DMG_TMP}" > /dev/null
    hdiutil attach -readwrite -noverify -noautoopen -mountpoint "/Volumes/${DMG_VOL}" "${DMG_TMP}" > /dev/null
    cp -R "${APP_DIR}" "/Volumes/${DMG_VOL}/"
    ln -s /Applications "/Volumes/${DMG_VOL}/Applications"
    hdiutil detach "/Volumes/${DMG_VOL}" -quiet
    hdiutil convert "${DMG_TMP}" -format UDZO -imagekey zlib-level=9 -o "${DMG_NAME}" > /dev/null
    rm -f "${DMG_TMP}"
    [ "${SIGNING_IDENTITY}" != "-" ] && codesign --sign "${SIGNING_IDENTITY}" ${SIGN_OPTS} "${DMG_NAME}" || true
    echo "[✓] ${DMG_NAME} ready — $(du -h "${DMG_NAME}" | awk '{print $1}')."
fi
