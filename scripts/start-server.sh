#!/bin/bash
# Starts llama-server tuned for a 16 GB M2. Leave this terminal open.
set -euo pipefail
cd "$(dirname "$0")/.."
QUANT="${QUANT:-}"     # e.g. QUANT=<other GSQ-RCO quant> ; empty = models/inkling.gguf (GSQ-RCO-Q2_K_XL)
if [ -n "$QUANT" ]; then
  MODEL=$(ls models/*"$QUANT"*.gguf 2>/dev/null | grep -v -e mmproj -e dspark | head -1 || true)
  if [ -z "$MODEL" ]; then
    echo "$QUANT not downloaded yet; fetching it (checksum-verified, Q2 is kept)"
    NO_LINK=1 QUANT="$QUANT" ./scripts/download-model.sh
    MODEL=$(ls models/*"$QUANT"*.gguf | grep -v -e mmproj -e dspark | head -1)
  fi
else
  MODEL=models/inkling.gguf
fi
case "$QUANT" in *Q3*) DEF_CTX=8192; DEF_WIRED=13312 ;; *) DEF_CTX=24576; DEF_WIRED=12288 ;; esac
CTX="${CTX:-$DEF_CTX}"
WIRED_MB="${WIRED_MB:-$DEF_WIRED}"   # 3-bit needs ~13 GiB for Metal, leaving ~3 GiB for macOS
UBATCH="${UBATCH:-512}"   # smaller (e.g. 128) shrinks llama.cpp's working memory so longer contexts fit; prompt reading gets a bit slower
MMPROJ=""
if [ "${VISION:-1}" != "0" ]; then
  MMPROJ=models/mmproj-Inkling-2-Mini-BF16.gguf
  if [ ! -f "$MMPROJ" ]; then
    echo "Vision projector not downloaded; fetching it (checksum-verified)"
    NO_LINK=1 VISION=1 ./scripts/download-model.sh
    MMPROJ=$(ls models/*mmproj*.gguf | head -1)
  fi
fi
if [ -n "$MMPROJ" ]; then
  echo "Model: $MODEL | context: $CTX | micro-batch: $UBATCH | GPU memory limit: $WIRED_MB MB | vision: $MMPROJ (projector adds ~0.7 GB plus image tokens; consider CTX=8192 if memory is tight)"
else
  echo "Model: $MODEL | context: $CTX | micro-batch: $UBATCH | GPU memory limit: $WIRED_MB MB"  # OpenCode's system prompt + tools need ~10k tokens; drop to 8192 for plain chat if memory is tight
fi
_MMPROJ_ARGS=()
[ -n "$MMPROJ" ] && _MMPROJ_ARGS=(--mmproj "$MMPROJ")

# Let the GPU use ~12 GB of the 16 GB (default is ~10.7 GB). Resets on reboot.
cur=$(sysctl -n iogpu.wired_limit_mb 2>/dev/null || echo 0)
if [ "$cur" -lt "$WIRED_MB" ]; then echo "Raising GPU memory limit to $WIRED_MB MB (needs your password)"; sudo sysctl iogpu.wired_limit_mb="$WIRED_MB"; fi

xattr -dr com.apple.quarantine llama.cpp bin 2>/dev/null || true

exec ./llama.cpp/llama-server \
  --model "$MODEL" \
  --alias inkling-2-mini \
  --jinja \
  --ctx-size "$CTX" \
  --ubatch-size "$UBATCH" \
  --n-gpu-layers 99 \
  --parallel 1 \
  --flash-attn on \
  --cache-type-k q8_0 --cache-type-v q8_0 \
  --temp 1.0 --top-p 1.0 --top-k 0 --min-p 0.0 \
  --host 127.0.0.1 --port 8080 ${_MMPROJ_ARGS[@]+"${_MMPROJ_ARGS[@]}"}
