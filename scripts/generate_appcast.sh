#!/bin/bash
# Generates or updates appcast.xml for a new Parrot release.
#
# Usage:
#   ./scripts/generate_appcast.sh <version> <zip_path> [<build_num>]
#
# Example:
#   ./scripts/generate_appcast.sh 0.9.1 Parrot_0.9.1.zip 2
#
# The EdDSA private key is read automatically from the macOS keychain
# (stored there by Sparkle's generate_keys tool).
# To use a key file instead: set KEY_PATH env var to the file path.

set -euo pipefail

VERSION="${1:-}"
ZIP_PATH="${2:-Parrot.zip}"
BUILD_NUM="${3:-1}"   # CFBundleVersion integer — must increment with every release

if [ -z "$VERSION" ]; then
    echo "Usage: $0 <version> <zip_path> [<build_num>]"
    exit 1
fi

if [ ! -f "$ZIP_PATH" ]; then
    echo "[!] Zip not found: $ZIP_PATH"
    exit 1
fi

# Locate sign_update (ships with Sparkle, stored in build artifacts)
SIGN_UPDATE=""
for candidate in \
    ".build/artifacts/sparkle/Sparkle/bin/sign_update" \
    ".build/checkouts/Sparkle/sign_update" \
    "$(command -v sign_update 2>/dev/null || true)" \
    "/opt/homebrew/bin/sign_update"; do
    [ -x "$candidate" ] && { SIGN_UPDATE="$candidate"; break; }
done

if [ -z "$SIGN_UPDATE" ]; then
    echo "[!] sign_update not found. Run 'swift build' first to download Sparkle."
    exit 1
fi

echo "[*] Signing and computing metadata..."
FILE_SIZE=$(wc -c < "$ZIP_PATH" | tr -d ' ')
PUB_DATE=$(date -u "+%a, %d %b %Y %H:%M:%S +0000")
DOWNLOAD_URL="https://github.com/thousandflowers/Parrot/releases/download/v${VERSION}/$(basename "$ZIP_PATH")"

# sign_update outputs: sparkle:edSignature="BASE64==" length="N"
# Extract just the base64 signature value
if [ -n "${KEY_PATH:-}" ]; then
    SIGN_OUTPUT=$("$SIGN_UPDATE" "$ZIP_PATH" -f "$KEY_PATH")
else
    SIGN_OUTPUT=$("$SIGN_UPDATE" "$ZIP_PATH")
fi
SIGNATURE=$(echo "$SIGN_OUTPUT" | grep -o 'edSignature="[^"]*"' | sed 's/edSignature="//;s/"$//')

if [ -z "$SIGNATURE" ]; then
    echo "[!] Failed to extract signature. sign_update output:"
    echo "$SIGN_OUTPUT"
    exit 1
fi

echo "[✓] Signature: ${SIGNATURE:0:20}..."

# Build item XML
ITEM=$(cat <<XMLEOF
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
XMLEOF
)

echo ""
echo "=== New appcast item ==="
echo "$ITEM"
echo ""

# Insert before closing </channel> — use Python for reliable multiline insert on macOS
APPCAST="appcast.xml"
if [ -f "$APPCAST" ]; then
    python3 - "$APPCAST" "$ITEM" <<'PYEOF'
import sys
path, item = sys.argv[1], sys.argv[2]
content = open(path, encoding='utf-8').read()
marker = '    </channel>'
if marker not in content:
    print("[!] Could not find </channel> in appcast.xml", file=sys.stderr)
    sys.exit(1)
updated = content.replace(marker, item + '\n\n' + marker, 1)
open(path, 'w', encoding='utf-8').write(updated)
PYEOF
    echo "[✓] Appended to ${APPCAST}"
else
    echo "[!] ${APPCAST} not found — create it first."
    exit 1
fi
