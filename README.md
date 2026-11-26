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
| `CTX=24576 ./scripts/start-server.sh` | Larger context, but swaps and runs ~25% slower on 16 GB (see Context size) |
| `QUANT=UD-IQ3_XXS ./scripts/start-server.sh` | Use (and download) another quant; Q2 stays the default |
| `WORKDIR=~/code/app ./scripts/pi.sh` | Run Pi on another folder |
| `SANDBOX=1 ./scripts/pi.sh` | macOS sandbox: shell commands can't write outside the work folder |
| `PI_MAX_TOOL_CHARS=4000 ./scripts/pi.sh` | Tighter cap on each tool result |
| `TRIM_START=0.8 TRIM_TARGET=0.3 ./scripts/pi.sh` | When context trimming starts and how far it cuts (default 0.75 → 0.30); `TRIM_OFF=1` disables it |

## Context size

16K (the default) is the largest size that runs well on a 16 GB M2. Measured with `scripts/bench-context.sh`
(real server, context filled to 90% with this repo's files, then a real Pi task):

| Context | Swap read back | Generation during Pi turns | Pi task | Reading a full window |
|---|---|---|---|---|
| **16K** | 73 MB | ~13.5 tok/s | 78 s | 3 min (82 tok/s) |
| 24K | 533 MB | ~10 tok/s | 108 s | 5 min (74 tok/s) |
| 32K | 1.3 GB | ~10 tok/s | 100 s | 8 min (63 tok/s) |
| 32K, `UBATCH=256` | 1.1 GB | ~9 tok/s | 164 s | 9.5 min (54 tok/s) |
| 48K | fails: Metal out of memory | | | |

The model and its buffers take ~12 GB, so every extra GB of context pushes macOS into swap, which slows
every turn, not just long ones. The model recalled a fact planted at the start of the window at every size
that ran. Use `context-trim.ts` (below) to make 16K last, rather than a bigger window.

## What's here

| Path | Purpose |
|---|---|
| `scripts/setup.sh` | Rebuilds llama.cpp (Unsloth `b12722-mix-f1c70ea`), the model and Pi 1.6.0 |
| `scripts/start-server.sh` | `llama-server` on 127.0.0.1:8080, tuned for 16 GB |
| `scripts/download-model.sh` | Downloads a GGUF from `unsloth/Inkling-2-Mini-GGUF`, verifies SHA-256 |
| `scripts/verify.sh` | Smoke test |
| `scripts/bench-context.sh` | Measures context sizes with the real server and Pi; results in `bench/` |
| `scripts/pi.sh` | Launches Pi; syncs its context window and compaction to the server's `n_ctx` |
| `pi/agent/models.json` | Local endpoint, sampling, thinking level mapped to `reasoning_effort` |
| `pi/agent/settings.json` | Defaults (thinking: low) and compaction scaled to the context |
| `pi/agent/APPEND_SYSTEM.md` | Rules that keep reads, searches and command output small |
| `pi/agent/extensions/workdir-guard.ts` | Blocks write/edit outside the work folder |
| `pi/agent/extensions/output-cap.ts` | Cuts any tool result over 6,000 characters |
| `pi/agent/extensions/context-trim.ts` | Past 75% of the window, replaces old tool output, long tool arguments and old thinking with one-line notes (no model call) |
| `docs/inside-a-local-agent.html` | Explainer: tokens, chat template, decoding, tool calls, agent loop |

Not tracked: `models/`, `llama.cpp/`, `vendor/`, `pi/node/`, and Pi's `auth.json`, `sessions/` and caches.

Note: `scripts/pi.sh` rewrites `contextWindow` in `models.json` and `compaction` in `settings.json`
to match the running server, so those files show as changed after you use a different `CTX`.
Run `git checkout pi/agent` before committing if you don't want to keep that.
