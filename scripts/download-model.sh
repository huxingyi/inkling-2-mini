#!/bin/bash
# Downloads Unsloth's Inkling 2 Mini GGUF and verifies its SHA-256 against Hugging Face.
set -euo pipefail
cd "$(dirname "$0")/.."
QUANT="${QUANT:-UD-Q2_K_XL}"          # alternative: QUANT=UD-IQ3_XXS (11.7 GB, tighter fit)
REPO="unsloth/Inkling-2-Mini-GGUF"

# Disk check (this Mac had only ~24 GB free; macOS also needs room for swap)
free_gb=$(df -g . | awk 'NR==2{print $4}')
echo "Free disk: ${free_gb} GB"
need=$([[ "$QUANT" == *Q4* || "$QUANT" == *Q5* || "$QUANT" == *Q6* ]] && echo 25 || echo 15)
if [ "$free_gb" -lt "$need" ]; then echo "Need at least $need GB free for $QUANT. Clear space first."; exit 1; fi

# Find the file for this quant in the repo (handles root or subfolder layouts)
info=$(curl -sfL "https://huggingface.co/api/models/$REPO/tree/main?recursive=true")
read -r FILE SHA SIZE < <(printf '%s' "$info" | /usr/bin/python3 -c "
import sys, json
q = sys.argv[1]
for f in json.load(sys.stdin):
    p = f.get('path', '')
    if p.endswith('.gguf') and q in p and 'mmproj' not in p and 'dspark' not in p:
        print(p, f.get('lfs', {}).get('oid', ''), f.get('size', 0)); break
" "$QUANT")
[ -n "${FILE:-}" ] || { echo "Could not find $QUANT in $REPO"; exit 1; }
echo "File: $FILE ($((SIZE/1024/1024)) MB)"

OUT="models/$(basename "$FILE")"
if [ -f "$OUT" ] && [ "$(stat -f%z "$OUT")" = "$SIZE" ]; then
  echo "Already downloaded: $OUT (size matches; skipping download)"
else
  curl -L -C - --fail --progress-bar -o "$OUT" "https://huggingface.co/$REPO/resolve/main/$FILE"
  echo "Verifying SHA-256..."
  got=$(shasum -a 256 "$OUT" | cut -d' ' -f1)
  if [ "$got" = "$SHA" ]; then echo "OK: $OUT matches Hugging Face checksum"; else echo "MISMATCH: got $got expected $SHA"; exit 1; fi
fi
# models/inkling.gguf is what the single-Mac start-server.sh loads; NO_LINK=1 leaves it alone
[ -n "${NO_LINK:-}" ] || ln -sf "$(basename "$OUT")" models/inkling.gguf
