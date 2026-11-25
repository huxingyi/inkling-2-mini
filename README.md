# Inkling 2 Mini on a 16 GB MacBook

Local setup for [Inkling 2 Mini](https://thinkingmachines.ai/news/inkling-2-mini/) on an Apple Silicon Mac
with 16 GB of memory: a llama.cpp server, the 2-bit Unsloth GGUF, and the [Pi](https://pi.dev) coding agent
tuned for a small context window.

This repo holds scripts and config only. The model (~9 GB), llama.cpp and Pi are downloaded again by
`scripts/setup.sh`, each pinned to a version and checksum-verified.

## Recover from scratch

    git clone https://github.com/huxingyi/inkling-2-mini.git ~/Workspaces/inkling-2-mini
    cd ~/Workspaces/inkling-2-mini
    ./scripts/setup.sh                        # llama.cpp + model + Pi; safe to re-run

Needs: Apple Silicon Mac, ~25 GB free disk, Node.js 22.19+ (nvm is used if present).

## Run

    ./scripts/start-server.sh                 # tab 1; asks for sudo once to raise the GPU memory limit
    ./scripts/verify.sh                       # tab 2, optional: health, speed, tool-call test
    cd pi-playground && ../scripts/pi.sh      # tab 2: Pi in the scratch folder

## Options

| Command | Effect |
|---|---|
| `CTX=32768 UBATCH=128 ./scripts/start-server.sh` | Larger context; smaller micro-batch saves working memory |
| `QUANT=UD-IQ3_XXS ./scripts/start-server.sh` | Use (and download) another quant; Q2 stays the default |
| `WORKDIR=~/code/app ./scripts/pi.sh` | Run Pi on another folder |
| `SANDBOX=1 ./scripts/pi.sh` | macOS sandbox: shell commands can't write outside the work folder |
| `PI_MAX_TOOL_CHARS=4000 ./scripts/pi.sh` | Tighter cap on each tool result |

## What's here

| Path | Purpose |
|---|---|
| `scripts/setup.sh` | Rebuilds llama.cpp (Unsloth `b12588-mix-c0c3de8`), the model and Pi 1.6.0 |
| `scripts/start-server.sh` | `llama-server` on 127.0.0.1:8080, tuned for 16 GB |
| `scripts/download-model.sh` | Downloads a GGUF from `unsloth/Inkling-2-Mini-GGUF`, verifies SHA-256 |
| `scripts/verify.sh` | Smoke test |
| `scripts/pi.sh` | Launches Pi; syncs its context window and compaction to the server's `n_ctx` |
| `pi/agent/models.json` | Local endpoint, sampling, thinking level mapped to `reasoning_effort` |
| `pi/agent/settings.json` | Defaults (thinking: low) and compaction scaled to the context |
| `pi/agent/APPEND_SYSTEM.md` | Rules that keep reads, searches and command output small |
| `pi/agent/extensions/workdir-guard.ts` | Blocks write/edit outside the work folder |
| `pi/agent/extensions/output-cap.ts` | Cuts any tool result over 6,000 characters |
| `docs/inside-a-local-agent.html` | Explainer: tokens, chat template, decoding, tool calls, agent loop |

Not tracked: `models/`, `llama.cpp/`, `vendor/`, `pi/node/`, and Pi's `auth.json`, `sessions/` and caches.

Note: `scripts/pi.sh` rewrites `contextWindow` in `models.json` and `compaction` in `settings.json`
to match the running server, so those files show as changed after you use a different `CTX`.
Run `git checkout pi/agent` before committing if you don't want to keep that.
