#!/bin/bash
# Measures which context size works best on this Mac, with the real server and Pi.
#   ./scripts/bench-context.sh                      tries 16K, 32K, 48K, 64K (stops early if one fails)
#   CTXS="16384 32768" ./scripts/bench-context.sh   only these sizes
#   CTXS="24576 32768:256" NO_STOP=1 ./scripts/bench-context.sh   CTX:UBATCH pairs, run them all
# Takes ~30-60 minutes. Stop your own server first. Results go to bench/results.md.
set -euo pipefail
cd "$(dirname "$0")/.."
WIRED_MB="${WIRED_MB:-12288}"
cur=$(sysctl -n iogpu.wired_limit_mb 2>/dev/null || echo 0)
if [ "$cur" -lt "$WIRED_MB" ]; then echo "Raising GPU memory limit to $WIRED_MB MB (needs your password once)"; sudo sysctl iogpu.wired_limit_mb="$WIRED_MB"; fi
exec python3 scripts/bench-context.py
