#!/bin/bash
# Builds Parrot as a universal .app bundle (arm64 + x86_64) with Info.plist,
# entitlements, and a self-contained llama-server with all required dylibs.
# Usage: ./build-app.sh [release|debug]
set -euo pipefail

CONFIG="${1:-release}"
ARM64_PATH=".build/arm64-apple-macosx/${CONFIG}/Parrot"
X86_PATH=".build/x86_64-apple-macosx/${CONFIG}/Parrot"
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
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"
if [ "${SIGNING_IDENTITY}" = "-" ]; then
    SIGN_OPTS="--force --timestamp=none"
    echo "[i] Ad-hoc signing. Set SIGNING_IDENTITY for Developer ID + notarization."
else
    SIGN_OPTS="--force --options runtime"  # hardened runtime required for notarization
    echo "[i] Signing with Developer ID: ${SIGNING_IDENTITY}"
fi

echo "[*] Building arm64 (${CONFIG})..."
swift build -c "${CONFIG}" --arch arm64

echo "[*] Building x86_64 (${CONFIG})..."
if swift build -c "${CONFIG}" --arch x86_64 2>/dev/null; then
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

cp "${BINARY_PATH}" "${MACOS}/Parrot"
install_name_tool -add_rpath "@loader_path/../Frameworks" "${MACOS}/Parrot"

# Embed Sparkle.framework (always from arm64 build — framework is architecture-independent)
SPARKLE_SRC=".build/arm64-apple-macosx/${CONFIG}/Sparkle.framework"
if [ -d "${SPARKLE_SRC}" ]; then
    cp -r "${SPARKLE_SRC}" "${FRAMEWORKS}/"
else
    echo "[!] Sparkle.framework not found at ${SPARKLE_SRC}" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Bundle llama-server + all required Homebrew dylibs
# ---------------------------------------------------------------------------

# Locate llama-server binaries (arm64 = Apple Silicon Homebrew, x86_64 = Intel Homebrew)
LLAMA_ARM64="/opt/homebrew/bin/llama-server"
LLAMA_X86="/usr/local/bin/llama-server"
LLAMA_BIN=""

# Determine which to use as primary (for dylib resolution)
if [ -x "$LLAMA_ARM64" ]; then LLAMA_BIN="$LLAMA_ARM64"; fi

if [ -x "$LLAMA_ARM64" ] && [ -x "$LLAMA_X86" ]; then
    echo "[*] Bundling universal llama-server (arm64 + x86_64)..."
    lipo -create -output "${MACOS}/llama-server" "$LLAMA_ARM64" "$LLAMA_X86"
    LLAMA_BUNDLED=1
elif [ -x "$LLAMA_ARM64" ]; then
    echo "[*] Bundling arm64 llama-server..."
    cp "$LLAMA_ARM64" "${MACOS}/llama-server"
    LLAMA_BUNDLED=1
elif [ -x "$LLAMA_X86" ]; then
    echo "[*] Bundling x86_64 llama-server..."
    cp "$LLAMA_X86" "${MACOS}/llama-server"
    LLAMA_BIN="$LLAMA_X86"
    LLAMA_BUNDLED=1
else
    LLAMA_BUNDLED=0
fi

if [ "${LLAMA_BUNDLED}" = "1" ] && [ -n "$LLAMA_BIN" ]; then
    echo "[*] Bundling llama-server dylibs from ${LLAMA_BIN}..."

    # Resolve the actual Cellar path (Homebrew uses symlinks)
    LLAMA_REAL=$(readlink -f "$LLAMA_BIN" 2>/dev/null || realpath "$LLAMA_BIN")
    LLAMA_CPP_LIB=$(dirname "$(dirname "$LLAMA_REAL")")/lib

    GGML_LIB="/opt/homebrew/opt/ggml/lib"
    SSL_LIB="/opt/homebrew/opt/openssl@3/lib"

    chmod +x "${MACOS}/llama-server"

    # Dylibs to bundle (versioned .0. names so dyld finds them)
    DYLIBS=(
        "${LLAMA_CPP_LIB}/libllama.0.dylib"
        "${LLAMA_CPP_LIB}/libllama-common.0.dylib"
        "${LLAMA_CPP_LIB}/libmtmd.0.dylib"
        "${GGML_LIB}/libggml.0.dylib"
        "${GGML_LIB}/libggml-base.0.dylib"
        "${SSL_LIB}/libssl.3.dylib"
        "${SSL_LIB}/libcrypto.3.dylib"
    )

    for src in "${DYLIBS[@]}"; do
        [ -f "$src" ] && cp "$src" "${FRAMEWORKS}/" || echo "[!] Missing dylib: $src"
    done

    # ----------- fix_binary: rewrite all Homebrew paths to @rpath -----------
    fix_binary() {
        local b="$1"
        # llama.cpp libs
        for name in libllama.0.dylib libllama-common.0.dylib libmtmd.0.dylib; do
            for prefix in \
                "${LLAMA_CPP_LIB}" \
                "/opt/homebrew/opt/llama.cpp/lib" \
                "$(dirname "$(dirname "$(dirname "$LLAMA_REAL")")")/opt/llama.cpp/lib"; do
                install_name_tool -change "${prefix}/${name}" "@rpath/${name}" "$b" 2>/dev/null || true
            done
        done
        # ggml
        for name in libggml.0.dylib libggml-base.0.dylib; do
            install_name_tool -change "${GGML_LIB}/${name}" "@rpath/${name}" "$b" 2>/dev/null || true
        done
        # openssl (both opt/ path and versioned Cellar path)
        for name in libssl.3.dylib libcrypto.3.dylib; do
            install_name_tool -change "${SSL_LIB}/${name}" "@rpath/${name}" "$b" 2>/dev/null || true
            # Also fix versioned Cellar paths that openssl dylibs reference internally
            local ssl_cellar
            ssl_cellar=$(readlink -f "${SSL_LIB}" 2>/dev/null || realpath "${SSL_LIB}" 2>/dev/null || echo "")
            [ -n "$ssl_cellar" ] && \
                install_name_tool -change "${ssl_cellar}/${name}" "@rpath/${name}" "$b" 2>/dev/null || true
        done
    }

    # Fix llama-server: add rpath and rewrite hardcoded paths
    install_name_tool -add_rpath "@loader_path/../Frameworks" "${MACOS}/llama-server" 2>/dev/null || true
    fix_binary "${MACOS}/llama-server"

    # Fix each bundled dylib: update install name, add rpath, rewrite deps
    for dylib in "${FRAMEWORKS}"/libllama*.dylib "${FRAMEWORKS}"/libmtmd*.dylib \
                 "${FRAMEWORKS}"/libggml*.dylib "${FRAMEWORKS}"/libssl*.dylib \
                 "${FRAMEWORKS}"/libcrypto*.dylib; do
        [ -f "$dylib" ] || continue
        name=$(basename "$dylib")
        install_name_tool -id "@rpath/${name}" "$dylib" 2>/dev/null || true
        install_name_tool -add_rpath "@loader_path" "$dylib" 2>/dev/null || true
        fix_binary "$dylib"
    done

    echo "[*] Signing llama-server dylibs..."
    for dylib in "${FRAMEWORKS}"/libllama*.dylib "${FRAMEWORKS}"/libmtmd*.dylib \
                 "${FRAMEWORKS}"/libggml*.dylib "${FRAMEWORKS}"/libssl*.dylib \
                 "${FRAMEWORKS}"/libcrypto*.dylib; do
        # shellcheck disable=SC2086
        [ -f "$dylib" ] && codesign --sign "${SIGNING_IDENTITY}" ${SIGN_OPTS} "$dylib"
    done
    # shellcheck disable=SC2086
    codesign --sign "${SIGNING_IDENTITY}" ${SIGN_OPTS} "${MACOS}/llama-server"
    echo "[✓] llama-server bundled."
else
    echo "[!] llama-server not found. Install with: brew install llama.cpp" >&2
    echo "    The app will look for llama-server in Homebrew at runtime." >&2
fi

# ---------------------------------------------------------------------------

# Copy Info.plist and resolve Xcode-style variable tokens
sed \
  -e "s/\$(DEVELOPMENT_LANGUAGE)/en/g" \
  -e "s/\$(EXECUTABLE_NAME)/Parrot/g" \
  -e "s/\$(PRODUCT_BUNDLE_IDENTIFIER)/${BUNDLE_ID}/g" \
  -e "s/\$(PRODUCT_NAME)/Parrot/g" \
  "${PLIST_SRC}" > "${PLIST_DST}"

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
# DMG packaging
# ---------------------------------------------------------------------------
echo "[*] Creating ${APP_DIR%.app}.dmg..."
DMG_NAME="${APP_DIR%.app}.dmg"
rm -f "${DMG_NAME}"
hdiutil create -volname "Parrot" \
    -srcfolder "${APP_DIR}" \
    -ov -format UDZO \
    "${DMG_NAME}" > /dev/null
echo "[✓] ${DMG_NAME} ready."

echo ""
echo "[✓] Build complete: ${APP_DIR} + ${DMG_NAME}"
if [ "${SIGNING_IDENTITY}" = "-" ]; then
    echo "    Testers: right-click the .app → Open on first launch to bypass Gatekeeper."
    echo "    For proper distribution: set SIGNING_IDENTITY + NOTARIZE_* and rebuild."
fi
