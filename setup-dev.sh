#!/bin/bash
set -euo pipefail

echo "=== Parrot — Setup sviluppo ==="

# 1. Verifica Xcode Command Line Tools
if ! xcode-select -p &>/dev/null; then
    echo "[!] Xcode Command Line Tools non installati. Installali con:"
    echo "    xcode-select --install"
    exit 1
fi

# 2. Verifica versione Swift
echo "[*] Swift: $(swift --version | head -1)"

# 3. Build
echo "[*] Build in corso..."
swift build
echo "[✓] Build completata"

# 4. Test
echo "[*] Test in corso..."
swift test
echo "[✓] Test completati"

echo ""
echo "=== Setup completato ==="
echo "Per avviare: swift run"
echo "Per test:    swift test"
echo "Per debug:   apri Package.swift in Xcode"
