#!/bin/bash
# HEAD-checks every Hugging Face model URL in the sources. Upstream repos rename or drop
# quantizations (ggml-org removed gemma-4-E4B Q4_K_M, which broke Parrot's recommended model),
# so run this before a release.
set -uo pipefail
cd "$(dirname "$0")/.."
failed=0
while read -r url; do
    code=$(curl -s -o /dev/null -w "%{http_code}" -I -L --max-time 30 "$url")
    echo "${code} ${url}"
    [ "${code}" = "200" ] || failed=1
done < <(grep -rhoE 'https://huggingface\.co/[^"]+\.gguf' Infra Core UI App | sort -u)
exit "${failed}"
