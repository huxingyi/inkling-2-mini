#!/bin/bash
# Downloads ISTA-DASLab Inkling 2 Mini GGUF (or the mmproj vision projector; default VISION=1, set VISION=0 for text-only) and verifies SHA-256 against Hugging Face.
set -euo pipefail
cd "$(dirname "$0")/.."
if [ "${VISION:-1}" != "0" ]; then
  # Vision projector (mmproj): the model GGUF has no vision weights; this is a ~640 MB add-on.
  QUANT="mmproj"
else
  QUANT="${QUANT:-GSQ-RCO-Q2_K_XL}"          # alternative: QUANT=<other GSQ-RCO quant>
fi
REPO="ISTA-DASLab/Inkling-2-Mini-GSQ-RCO-GGUF"

# Disk check (this Mac had only ~24 GB free; macOS also needs room for swap)
free_gb=$(df -g . | awk 'NR==2{print $4}')
echo "Free disk: ${free_gb} GB"
need=$([[ "$QUANT" == "mmproj" ]] && echo 2 || { [[ "$QUANT" == *Q4* || "$QUANT" == *Q5* || "$QUANT" == *Q6* ]] && echo 25 || echo 15; })
if [ "$free_gb" -lt "$need" ]; then echo "Need at least $need GB free for $QUANT. Clear space first."; exit 1; fi

# Find the file for this quant in the repo (handles root or subfolder layouts)
info=$(curl -sfL "https://huggingface.co/api/models/$REPO/tree/main?recursive=true")
read -r FILE SHA SIZE < <(printf '%s' "$info" | /usr/bin/python3 -c "
import sys, json
q = sys.argv[1]
for f in json.load(sys.stdin):
    p = f.get('path', '')
    if p.endswith('.gguf') and 'dspark' not in p and (q == 'mmproj' and 'mmproj' in p or q != 'mmproj' and q in p and 'mmproj' not in p):
        print(p, f.get('lfs', {}).get('oid', ''), f.get('size', 0)); break
" "$QUANT")
[ -n "${FILE:-}" ] || { echo "Could not find $QUANT in $REPO"; exit 1; }
echo "File: $FILE ($((SIZE/1024/1024)) MB)"

mkdir -p models
OUT="models/$(basename "$FILE")"
PART="$OUT.part"
fsize() { stat -f%z "$1" 2>/dev/null || stat -c%s "$1"; }

if [ -f "$OUT" ] && [ -z "${FORCE:-}" ]; then
  if [ "$(fsize "$OUT")" = "$SIZE" ]; then
    echo "Already downloaded: $OUT (size matches Hugging Face; skipping)"
  else
    # Downloads only ever land in $OUT after passing the checksum, so a full-named file is
    # complete. A different size means the repo has re-uploaded the quant since then.
    echo "Keeping existing $OUT: it's a complete, earlier upload ($(fsize "$OUT") bytes; Hugging Face now has $SIZE)."
    echo "  To replace it with the current upload: FORCE=1 QUANT=$QUANT ./scripts/download-model.sh"
  fi
else
  # Resume only a partial download of this exact upload (same target size), never a different file.
  if [ -f "$PART" ] && { [ ! -f "$PART.size" ] || [ "$(cat "$PART.size")" != "$SIZE" ] || [ "$(fsize "$PART")" -gt "$SIZE" ]; }; then
    echo "Discarding a partial download of a different upload"; rm -f "$PART"
  fi
  echo "$SIZE" > "$PART.size"
  curl -L -C - --fail --progress-bar -o "$PART" "https://huggingface.co/$REPO/resolve/main/$FILE"
  echo "Verifying SHA-256..."
  got=$(shasum -a 256 "$PART" | cut -d' ' -f1)
  if [ "$got" != "$SHA" ]; then
    rm -f "$PART" "$PART.size"
    echo "MISMATCH: got $got expected $SHA. Deleted the download; re-run to try again."; exit 1
  fi
  mv -f "$PART" "$OUT"; rm -f "$PART.size"
  echo "OK: $OUT matches Hugging Face checksum"
fi
# models/inkling.gguf is what the single-Mac start-server.sh loads; NO_LINK=1 leaves it alone
if [ -z "${NO_LINK:-}" ] && [ "$QUANT" != "mmproj" ]; then ln -sf "$(basename "$OUT")" models/inkling.gguf; fi
