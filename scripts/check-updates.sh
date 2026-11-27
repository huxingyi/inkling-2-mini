#!/bin/bash
# Checks for newer llama.cpp builds, Pi releases and model files. Read-only.
# Exit 0 = up to date, 1 = update(s) available.
set -uo pipefail
cd "$(dirname "$0")/.."

TAG="$(sed -n 's/^TAG="\(.*\)"/\1/p' scripts/setup.sh)"
PI_VERSION="$(sed -n 's/^PI_VERSION="\([^"]*\)".*/\1/p' scripts/setup.sh)"
QUANT="${QUANT:-GSQ-RCO-Q2_K_XL}"
REPO="ISTA-DASLab/Inkling-2-Mini-GSQ-RCO-GGUF"
PKG="@earendil-works/pi-coding-agent"
PI_PREFIX="pi/node"

up=0
say()  { printf '%s\n' "$*"; }
new()  { up=1; say "  NEW: $*"; }
same() { say "  ok:  $*"; }
warn() { say "  skip: $* (network error or not installed)"; }

say "== llama.cpp (Unsloth build) =="
CUR_TAG="$(cat llama.cpp/.tag 2>/dev/null || echo unknown)"
say "  installed: ${CUR_TAG} (${TAG} pinned)"
latest="$(curl -sfL --max-time 20 https://api.github.com/repos/unslothai/llama.cpp/releases/latest | /usr/bin/python3 -c "import sys,json;print(json.load(sys.stdin)['tag_name'])" 2>/dev/null)"
if [ -n "$latest" ]; then
  [ "$latest" = "$CUR_TAG" ] && same "unslothai/llama.cpp $CUR_TAG (latest)" \
    || new "unslothai/llama.cpp $latest (pinned: $TAG) — bump TAG/URL/SHA256 in setup.sh"
  [ "$TAG" != "$latest" ] && say "    note: setup.sh also pins $TAG; re-checking via GitHub says $latest"
else
  warn "GitHub API"
fi

say "== Pi ($PKG) =="
installed="$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$PI_PREFIX/node_modules/$PKG/package.json" 2>/dev/null | head -1)"
say "  installed: ${installed:-not installed} (pinned: $PI_VERSION)"
latest_pi="$(npm view "$PKG" version 2>/dev/null)"
if [ -n "$latest_pi" ]; then
  if [ "$latest_pi" != "$PI_VERSION" ]; then
    new "Pi $latest_pi is out (pinned: $PI_VERSION) — bump PI_VERSION in setup.sh"
  elif [ "$installed" != "$PI_VERSION" ]; then
    new "Pi $PI_VERSION is pinned but ${installed:-nothing} is installed — run ./scripts/setup.sh"
  else
    same "Pi $latest_pi (latest)"
  fi
else
  warn "npm registry"
fi

say "== Model ($REPO) =="
cur_file="$(readlink -f models/inkling.gguf 2>/dev/null)"
say "  current quant: $QUANT"
info="$(curl -sfL --max-time 30 "https://huggingface.co/api/models/$REPO/tree/main?recursive=true" 2>/dev/null)"
if [ -n "$info" ]; then
  found="$(printf '%s' "$info" | /usr/bin/python3 -c "
import sys, json
path = None
for f in json.load(sys.stdin):
    p = f.get('path', '')
    if '$QUANT' in p: path = p; break
print(path or '')" 2>/dev/null)"
  if [ -n "$found" ]; then
    same "$QUANT present in repo: $found"
    sha="$(printf '%s' "$info" | /usr/bin/python3 -c "
import sys, json
for f in json.load(sys.stdin):
    p = f.get('path', '')
    if p == '$found': print(f.get('lfs', {}).get('oid', '')); break" 2>/dev/null)"
    if [ -n "$sha" ] && [ -f models/inkling.gguf ]; then
      got="$(shasum -a 256 models/inkling.gguf | cut -d' ' -f1)"
      if [ "$got" = "$sha" ]; then
        same "models/inkling.gguf matches HF checksum ($got)"
      else
        new "model file hash mismatch (got $got, HF has $sha) — re-run download-model.sh"
      fi
    elif [ -f models/inkling.gguf ]; then
      warn "no SHA in HF response for $found"
    else
      new "models/inkling.gguf not found"
    fi
  else
    new "$QUANT not found in $REPO — check the file list in download-model.sh"
  fi
  new_quants="$(printf '%s' "$info" | /usr/bin/python3 -c "
import sys, json, re
names = [f.get('path','') for f in json.load(sys.stdin)]
q = sorted({m.group(0) for n in names for m in [re.search(r'(UD-[A-Za-z0-9_]+)', n)] if m})
print(', '.join(q))" 2>/dev/null)"
  same "available quants: ${new_quants:-unknown}"
else
  warn "Hugging Face API"
fi

say ""
if [ "$up" = 1 ]; then
  say "Updates available. To apply: bump the pin(s) in setup.sh, then ./scripts/setup.sh"
  exit 1
fi
say "Everything is current."
