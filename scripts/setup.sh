#!/bin/bash
# =============================================================================
# Rebuilds everything this repo doesn't store: llama.cpp, the model and Pi.
# Safe to re-run: each step checks first and skips what's already there.
#
#   ./scripts/setup.sh                      default model (UD-Q2_K_XL, ~9.1 GB)
#   QUANT=UD-IQ3_XXS ./scripts/setup.sh     a different quant
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"

TAG="b12588-mix-c0c3de8"
ASSET="llama-${TAG}-bin-macos-arm64.tar.gz"
URL="https://github.com/unslothai/llama.cpp/releases/download/${TAG}/${ASSET}"
SHA256="229def18e27ed740ec4f3a6508f084b25630e08d8a87ada40b00622fc496ceb8"
PI_VERSION="1.6.0"; PKG="@earendil-works/pi-coding-agent"; NODE_MIN="22.19.0"
PI_PREFIX="$ROOT/pi/node"

ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
step() { printf '\n\033[1m%s\033[0m\n' "$*"; }
die()  { printf '\n\033[31mError:\033[0m %s\n' "$*" >&2; exit 1; }
ver_ge() { [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -1)" = "$2" ]; }

step "1. This Mac"
[ "$(uname -s)" = "Darwin" ] && [ "$(uname -m)" = "arm64" ] || die "Needs an Apple Silicon Mac."
ok "Apple Silicon, $(( $(sysctl -n hw.memsize) / 1024 / 1024 / 1024 )) GiB, macOS $(sw_vers -productVersion)"

step "2. llama.cpp (Unsloth build $TAG)"
if [ -x llama.cpp/llama-server ] && [ "$(cat llama.cpp/.tag 2>/dev/null || echo "$TAG")" = "$TAG" ]; then
  ok "Already installed"
else
  mkdir -p vendor
  curl -fL --progress-bar -o "vendor/$ASSET" "$URL" || die "Download failed."
  [ "$(shasum -a 256 "vendor/$ASSET" | cut -d' ' -f1)" = "$SHA256" ] || die "Checksum mismatch; not installing."
  tar xzf "vendor/$ASSET" -C vendor
  [ -e llama.cpp ] && mv llama.cpp "llama.cpp.old.$(date +%s)"
  mv "vendor/llama-$TAG" llama.cpp
  echo "$TAG" > llama.cpp/.tag
  ok "Installed, checksum verified"
fi
xattr -dr com.apple.quarantine llama.cpp 2>/dev/null || true

step "3. Model"
QUANT="${QUANT:-UD-Q2_K_XL}" ./scripts/download-model.sh
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
