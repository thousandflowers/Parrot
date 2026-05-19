#!/bin/bash
# Generates or updates appcast.xml for a new Parrot release.
#
# Prerequisites:
#   - Sparkle's generate_appcast tool in PATH (ships with Sparkle.framework)
#     or at: .build/arm64-apple-macosx/release/Sparkle.framework/Versions/B/generate_appcast
#   - A zipped .app built with build-app.sh (e.g. Parrot.zip)
#   - The EdDSA private key exported via generate_keys (Sparkle tool)
#
# Usage:
#   ./scripts/generate_appcast.sh <version> <zip_path> [<private_key_path>]
#
# Example:
#   ./scripts/generate_appcast.sh 1.0.0 Parrot.zip ~/.sparkle_private_key
#
# The script will:
#   1. Sign the zip with the EdDSA key
#   2. Append a new <item> to appcast.xml
#   3. Print the entry for manual review

set -euo pipefail

VERSION="${1:-}"
ZIP_PATH="${2:-Parrot.zip}"
KEY_PATH="${3:-}"
BUILD_NUM="${4:-1}"   # CFBundleVersion integer — must increment with every release

if [ -z "$VERSION" ]; then
    echo "Usage: $0 <version> <zip_path> [<private_key_path>] [<build_num>]"
    exit 1
fi

if [ ! -f "$ZIP_PATH" ]; then
    echo "[!] Zip not found: $ZIP_PATH"
    exit 1
fi

# Locate sign_update tool (part of Sparkle)
SIGN_UPDATE=""
for candidate in \
    "$(command -v sign_update 2>/dev/null)" \
    ".build/arm64-apple-macosx/release/Sparkle.framework/Versions/B/sign_update" \
    "/opt/homebrew/bin/sign_update"; do
    [ -x "$candidate" ] && { SIGN_UPDATE="$candidate"; break; }
done

if [ -z "$SIGN_UPDATE" ]; then
    echo "[!] sign_update not found. Install Sparkle or add it to PATH."
    echo "    Alternatively, sign manually with: sign_update <zip> -f <key_file>"
    exit 1
fi

echo "[*] Computing file size and signature..."
FILE_SIZE=$(wc -c < "$ZIP_PATH" | tr -d ' ')
PUB_DATE=$(date -u "+%a, %d %b %Y %H:%M:%S +0000")
DOWNLOAD_URL="https://github.com/thousandflowers/Parrot/releases/download/v${VERSION}/$(basename "$ZIP_PATH")"

if [ -n "$KEY_PATH" ]; then
    SIGNATURE=$("$SIGN_UPDATE" "$ZIP_PATH" -f "$KEY_PATH")
else
    SIGNATURE=$("$SIGN_UPDATE" "$ZIP_PATH" 2>/dev/null || echo "REPLACE_WITH_SIGNATURE")
fi

# Build item XML
ITEM=$(cat <<EOF
        <item>
            <title>Version ${VERSION}</title>
            <pubDate>${PUB_DATE}</pubDate>
            <sparkle:version>${BUILD_NUM}</sparkle:version>
            <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
            <enclosure
                url="${DOWNLOAD_URL}"
                length="${FILE_SIZE}"
                type="application/octet-stream"
                sparkle:edSignature="${SIGNATURE}"
            />
            <sparkle:releaseNotesLink>https://github.com/thousandflowers/Parrot/releases/tag/v${VERSION}</sparkle:releaseNotesLink>
        </item>
EOF
)

echo ""
echo "=== New appcast item ==="
echo "$ITEM"
echo ""

# Insert before closing </channel> tag
APPCAST="appcast.xml"
if [ -f "$APPCAST" ]; then
    # Insert item before </channel>
    sed -i.bak "s|    </channel>|${ITEM}\n\n    </channel>|" "$APPCAST"
    rm -f "${APPCAST}.bak"
    echo "[✓] Appended to ${APPCAST}"
else
    echo "[!] ${APPCAST} not found — copy the item above manually."
fi
