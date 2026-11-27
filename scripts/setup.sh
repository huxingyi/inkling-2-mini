#!/bin/bash
# =============================================================================
# Rebuilds everything this repo doesn't store: llama.cpp, the model and Pi.
# Safe to re-run: each step checks first and skips what's already there.
#
#   ./scripts/setup.sh                      default model (GSQ-RCO-Q2_K_XL, ~9.79 GB)
#   QUANT=<other GSQ-RCO quant> ./scripts/setup.sh   a different quant
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"

TAG="b12776-mix-ef2df21"
ASSET="llama-${TAG}-bin-macos-arm64.tar.gz"
URL="https://github.com/unslothai/llama.cpp/releases/download/${TAG}/${ASSET}"
SHA256="e64e3dc64b31ea5cbf8f9bd965b8074371f5fe9a884e40d0b9f94618e253518d"
PI_VERSION="1.6.1"; PKG="@earendil-works/pi-coding-agent"; NODE_MIN="22.19.0"
PI_PREFIX="$ROOT/pi/node"

ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
step() { printf '\n\033[1m%s\033[0m\n' "$*"; }
die()  { printf '\n\033[31mError:\033[0m %s\n' "$*" >&2; exit 1; }
ver_ge() { [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -1)" = "$2" ]; }

step "1. This Mac"
[ "$(uname -s)" = "Darwin" ] && [ "$(uname -m)" = "arm64" ] || die "Needs an Apple Silicon Mac."
ok "Apple Silicon, $(( $(sysctl -n hw.memsize) / 1024 / 1024 / 1024 )) GiB, macOS $(sw_vers -productVersion)"

step "2. llama.cpp (Unsloth build $TAG)"
CUR_TAG="$(cat llama.cpp/.tag 2>/dev/null || echo unknown)"   # no marker = installed by hand, version unknown
if [ -x llama.cpp/llama-server ] && [ "$CUR_TAG" = "$TAG" ]; then
  ok "Already installed"
else
  mkdir -p vendor
  curl -fL --progress-bar -o "vendor/$ASSET" "$URL" || die "Download failed."
  [ "$(shasum -a 256 "vendor/$ASSET" | cut -d' ' -f1)" = "$SHA256" ] || die "Checksum mismatch; not installing."
  rm -rf "vendor/llama-$TAG"          # leftover from an interrupted run
  tar xzf "vendor/$ASSET" -C vendor
  if [ -e llama.cpp ]; then
    OLD="llama.cpp.old.$CUR_TAG.$(date +%Y%m%d-%H%M%S)"
    mv llama.cpp "$OLD"; echo "  Previous build ($CUR_TAG) moved to $OLD; delete it once the new one works."
  fi
  mv "vendor/llama-$TAG" llama.cpp
  echo "$TAG" > llama.cpp/.tag
  ok "Installed $TAG, checksum verified. Restart the server if it's running."
fi
xattr -dr com.apple.quarantine llama.cpp 2>/dev/null || true

step "3. Model"
QUANT="${QUANT:-GSQ-RCO-Q2_K_XL}" ./scripts/download-model.sh
ok "models/inkling.gguf -> $(readlink models/inkling.gguf)"

step "4. Pi $PI_VERSION"
node_ok() { command -v node >/dev/null 2>&1 && ver_ge "$(node -v | sed 's/^v//')" "$NODE_MIN"; }
if ! node_ok && [ -s "${NVM_DIR:-$HOME/.nvm}/nvm.sh" ]; then
  set +u; . "${NVM_DIR:-$HOME/.nvm}/nvm.sh"
  node_ok || nvm use 22 >/dev/null 2>&1 || nvm install 22 >/dev/null
  set -u
fi
node_ok || die "Pi needs Node.js $NODE_MIN+ (found $(node -v 2>/dev/null || echo none)). Install it with 'brew install node' or nvm, then re-run."
INSTALLED=$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$PI_PREFIX/node_modules/$PKG/package.json" 2>/dev/null | head -1 || true)
if [ "$INSTALLED" = "$PI_VERSION" ]; then ok "Already installed"
else
  mkdir -p "$PI_PREFIX"
  npm install --prefix "$PI_PREFIX" "$PKG@$PI_VERSION" --no-fund --no-audit --loglevel=error
  ok "Installed"
fi
command -v rg >/dev/null && command -v fd >/dev/null || echo "  Optional: 'brew install ripgrep fd' for faster file search in Pi."

step "5. Finishing"
mkdir -p pi-playground
chmod +x scripts/*.sh
ok "Scripts executable, pi-playground ready"

cat <<'MSG'

Done. Next:
  ./scripts/start-server.sh                 # tab 1 (CTX=32768 UBATCH=128 for a bigger window)
  ./scripts/verify.sh                       # tab 2, optional smoke test
  cd pi-playground && ../scripts/pi.sh      # tab 2
MSG
