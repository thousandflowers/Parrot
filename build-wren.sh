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
SIGN_OPTS="--force --timestamp=none"
[ "${SIGNING_IDENTITY}" = "-" ] && echo "[i] Ad-hoc signing." || echo "[i] Signing identity: ${SIGNING_IDENTITY}"

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

# Localizations (small) so system strings resolve.
for lproj in Resources/*.lproj; do [ -d "$lproj" ] && cp -r "$lproj" "${RES}/"; done

# The bundled model — this is what makes Wren self-contained.
echo "[*] Bundling model $(basename "${MODEL_PATH}") ($(du -h "${MODEL_PATH}" | awk '{print $1}'))..."
cp "${MODEL_PATH}" "${RES}/Models/"

# Sparkle (the main binary links it). Architecture-independent framework.
[ -d "${SPARKLE_SRC}" ] && cp -r "${SPARKLE_SRC}" "${FRAMEWORKS}/" || { echo "[!] Sparkle.framework missing" >&2; exit 1; }

# --- libllama + ggml only (NO llama-server, mtmd, ssl, crypto) ---
LLAMA_LIB="/opt/homebrew/opt/llama.cpp/lib"
GGML_LIB="/opt/homebrew/opt/ggml/lib"
DYLIBS=(
    "${LLAMA_LIB}/libllama.0.dylib"
    "${GGML_LIB}/libggml.0.dylib"
    "${GGML_LIB}/libggml-base.0.dylib"
)
for src in "${DYLIBS[@]}"; do
    real="$(readlink -f "$src" 2>/dev/null || realpath "$src")"
    [ -f "$real" ] && cp "$real" "${FRAMEWORKS}/$(basename "$src")" || { echo "[!] Missing dylib: $src" >&2; exit 1; }
done

# Rewrite Homebrew paths → @rpath so the bundle is self-contained.
fix_binary() {
    local b="$1"
    install_name_tool -change "${LLAMA_LIB}/libllama.0.dylib" "@rpath/libllama.0.dylib" "$b" 2>/dev/null || true
    for name in libggml.0.dylib libggml-base.0.dylib; do
        install_name_tool -change "${GGML_LIB}/${name}" "@rpath/${name}" "$b" 2>/dev/null || true
    done
}
fix_binary "${MACOS}/ParrotCompletionHelper"
for dylib in "${FRAMEWORKS}"/libllama*.dylib "${FRAMEWORKS}"/libggml*.dylib; do
    name=$(basename "$dylib")
    install_name_tool -id "@rpath/${name}" "$dylib" 2>/dev/null || true
    install_name_tool -add_rpath "@loader_path" "$dylib" 2>/dev/null || true
    fix_binary "$dylib"
done

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

# --- Sign inside-out ---
echo "[*] Signing..."
for dylib in "${FRAMEWORKS}"/libllama*.dylib "${FRAMEWORKS}"/libggml*.dylib; do
    codesign --sign "${SIGNING_IDENTITY}" ${SIGN_OPTS} "$dylib"
done
SPARKLE_VB="${FRAMEWORKS}/Sparkle.framework/Versions/B"
for xpc in "${SPARKLE_VB}/XPCServices"/*.xpc; do [ -d "$xpc" ] && codesign --sign "${SIGNING_IDENTITY}" ${SIGN_OPTS} "$xpc"; done
[ -d "${SPARKLE_VB}/Updater.app" ] && codesign --sign "${SIGNING_IDENTITY}" ${SIGN_OPTS} "${SPARKLE_VB}/Updater.app"
[ -f "${SPARKLE_VB}/Autoupdate" ] && codesign --sign "${SIGNING_IDENTITY}" ${SIGN_OPTS} "${SPARKLE_VB}/Autoupdate"
[ -f "${SPARKLE_VB}/Sparkle" ] && codesign --sign "${SIGNING_IDENTITY}" ${SIGN_OPTS} "${SPARKLE_VB}/Sparkle"
codesign --sign "${SIGNING_IDENTITY}" ${SIGN_OPTS} "${MACOS}/ParrotCompletionHelper"
codesign --sign "${SIGNING_IDENTITY}" --entitlements "${ENTITLEMENTS}" ${SIGN_OPTS} "${APP_DIR}"

echo ""
echo "[✓] ${APP_DIR} ready — $(du -sh "${APP_DIR}" | awk '{print $1}') total."
[ "${SIGNING_IDENTITY}" = "-" ] && echo "    First launch: right-click Wren.app → Open."
