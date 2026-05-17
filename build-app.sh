#!/bin/bash
# Builds RefineClone as a proper .app bundle with Info.plist and entitlements.
# Usage: ./build-app.sh [release|debug]
set -euo pipefail

CONFIG="${1:-release}"
BINARY_PATH=".build/arm64-apple-macosx/${CONFIG}/RefineClone"
APP_DIR="RefineClone.app"
CONTENTS="${APP_DIR}/Contents"
MACOS="${CONTENTS}/MacOS"
ENTITLEMENTS="Resources/RefineClone.entitlements"
PLIST_SRC="Resources/Info.plist"
PLIST_DST="${CONTENTS}/Info.plist"
BUNDLE_ID="com.thousandflowers.refineclone"

echo "[*] Building (${CONFIG})..."
swift build -c "${CONFIG}"

echo "[*] Packaging as ${APP_DIR}..."
rm -rf "${APP_DIR}"
mkdir -p "${MACOS}"
mkdir -p "${CONTENTS}/Resources"

# Copy .lproj localization directories
for lproj in Resources/*.lproj; do
    if [ -d "$lproj" ]; then
        cp -r "$lproj" "${CONTENTS}/Resources/"
    fi
done

cp "${BINARY_PATH}" "${MACOS}/RefineClone"

# Copy Info.plist and resolve Xcode-style variable tokens
sed \
  -e "s/\$(DEVELOPMENT_LANGUAGE)/en/g" \
  -e "s/\$(EXECUTABLE_NAME)/RefineClone/g" \
  -e "s/\$(PRODUCT_BUNDLE_IDENTIFIER)/${BUNDLE_ID}/g" \
  -e "s/\$(PRODUCT_NAME)/RefineClone/g" \
  "${PLIST_SRC}" > "${PLIST_DST}"

echo "[*] Signing with entitlements..."
codesign \
  --sign - \
  --entitlements "${ENTITLEMENTS}" \
  --force \
  --deep \
  "${APP_DIR}"

echo ""
echo "[✓] ${APP_DIR} pronto."
echo "    Sposta in /Applications oppure avvia con:"
echo "    open ${APP_DIR}"
echo ""
echo "    Prima del primo avvio concedi Accessibilità in:"
echo "    Impostazioni di Sistema → Privacy e Sicurezza → Accessibilità"
