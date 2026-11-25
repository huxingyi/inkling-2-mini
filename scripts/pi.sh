#!/bin/bash
# =============================================================================
# Pi coding agent, wired to the local Inkling server. Safe to re-run.
#
#   ./scripts/pi.sh                      interactive, in the current folder
#   ./scripts/pi.sh -p "question"        one-shot answer, then exit
#   ./scripts/pi.sh --thinking off       change thinking level (off|minimal|low|medium|high)
#   WORKDIR=~/code/myapp ./scripts/pi.sh work in that folder instead of the current one
#   SANDBOX=1 ./scripts/pi.sh            also stop shell commands writing outside it (macOS sandbox)
#
# Pi works on the folder you run it from. Everything it installs or reads
# (Node packages, config, sessions) stays in inkling-2-mini/pi/.
# =============================================================================
set -euo pipefail
CALLER_DIR="$(pwd)"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PI_VERSION="1.6.0"
PKG="@earendil-works/pi-coding-agent"
NODE_MIN="22.19.0"
PI_PREFIX="$ROOT/pi/node"
PI_BIN="$PI_PREFIX/node_modules/.bin/pi"

ok()  { printf '  \033[32m✓\033[0m %s\n' "$*" >&2; }
die() { printf '\n\033[31mError:\033[0m %s\n' "$*" >&2; exit 1; }
ver_ge() { [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -1)" = "$2" ]; }

# ---------------------------------------------------------------- 1. Node.js >= 22.19
node_ok() { command -v node >/dev/null 2>&1 && ver_ge "$(node -v | sed 's/^v//')" "$NODE_MIN"; }
if ! node_ok && [ -s "${NVM_DIR:-$HOME/.nvm}/nvm.sh" ]; then
  # shellcheck disable=SC1091
  set +u; . "${NVM_DIR:-$HOME/.nvm}/nvm.sh"
  node_ok || nvm use 22 >/dev/null 2>&1 || true
  if ! node_ok; then echo "Installing Node 22 with nvm (one time)..." >&2; nvm install 22 >/dev/null; nvm use 22 >/dev/null; fi
  set -u
fi
node_ok || die "Pi needs Node.js $NODE_MIN or newer (found: $(node -v 2>/dev/null || echo none)). Install it with 'brew install node' or nvm, then re-run."
ok "Node $(node -v)"

# ---------------------------------------------------------------- 2. Pi (pinned)
INSTALLED=$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$PI_PREFIX/node_modules/$PKG/package.json" 2>/dev/null | head -1 || true)
if [ -x "$PI_BIN" ] && [ "$INSTALLED" = "$PI_VERSION" ]; then
  ok "Pi $PI_VERSION"
else
  echo "Installing Pi $PI_VERSION into pi/node (one time)..." >&2
  mkdir -p "$PI_PREFIX"
  npm install --prefix "$PI_PREFIX" "$PKG@$PI_VERSION" --no-fund --no-audit --loglevel=error >&2
  ok "Pi $PI_VERSION installed"
fi

# ---------------------------------------------------------------- 3. server
if curl -sf -m 3 http://127.0.0.1:8080/health >/dev/null; then
  ok "Inkling server is up on 127.0.0.1:8080"
else
  die "The Inkling server isn't running. Start it in another tab with ./scripts/start-server.sh, then re-run."
fi

# ---------------------------------------------------------------- 4. match Pi's context to the server
N_CTX=$(curl -sf -m 3 http://127.0.0.1:8080/props | python3 -c "import sys,json;d=json.load(sys.stdin);print((d.get('default_generation_settings') or {}).get('n_ctx') or d.get('n_ctx') or '')" 2>/dev/null || true)
if [ -n "$N_CTX" ]; then
  python3 - "$ROOT/pi/agent/models.json" "$N_CTX" <<'PY'
import json, sys
path, n = sys.argv[1], int(sys.argv[2])
d = json.load(open(path))
m = d["providers"]["inkling"]["models"][0]
if m.get("contextWindow") != n:
    m["contextWindow"] = n
    json.dump(d, open(path, "w"), indent=2)
# Pi's compaction defaults (reserve 16384, keep 20000) assume a big window; scale them to this one
spath = path.replace("models.json", "settings.json")
st = json.load(open(spath))
want = {"enabled": True, "reserveTokens": max(4096, n // 3), "keepRecentTokens": max(3072, int(n * 0.35))}
if st.get("compaction") != want:
    st["compaction"] = want
    json.dump(st, open(spath, "w"), indent=2)
PY
  ok "Pi context window set to $N_CTX tokens (from the server); compaction scaled to match"
fi

# ---------------------------------------------------------------- 5. run
if [ -n "${WORKDIR:-}" ]; then
  CALLER_DIR="$(cd "${WORKDIR/#\~/$HOME}" 2>/dev/null && pwd -P)" || die "WORKDIR not found: $WORKDIR"
fi
export PI_CODING_AGENT_DIR="$ROOT/pi/agent"   # models.json + settings.json for the local model
export PI_SKIP_VERSION_CHECK=1 PI_TELEMETRY=0 PI_OFFLINE=1
ok "Working folder: $CALLER_DIR"
echo "  Pi runs read/write/edit/bash WITHOUT asking first. Use a folder you don't mind it changing." >&2
echo "  write/edit outside this folder are blocked (pi/agent/extensions/workdir-guard.ts)." >&2
cd "$CALLER_DIR"
if [ -n "${SANDBOX:-}" ]; then
  # Kernel-enforced: every process Pi starts (including bash commands) can only write inside the
  # work folder, Pi's own config/session folder, temp folders and /dev. Reads are unrestricted.
  PROFILE="(version 1)(allow default)(deny file-write*)
(allow file-write* (subpath \"$(pwd -P)\") (subpath \"$ROOT/pi\")
  (subpath \"/private/tmp\") (subpath \"/private/var/folders\") (subpath \"$HOME/.npm\")
  (literal \"/dev/null\") (literal \"/dev/zero\") (regex #\"^/dev/(tty|ttys|fd/|ptmx|dtracehelper)\"))"
  ok "Sandbox on: shell commands also can't write outside $(pwd -P)"
  exec sandbox-exec -p "$PROFILE" "$PI_BIN" "$@"
fi
exec "$PI_BIN" "$@"
