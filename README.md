# Inkling 2 Mini on a 16 GB MacBook

Local setup for [Inkling 2 Mini](https://thinkingmachines.ai/news/inkling-2-mini/) on an Apple Silicon Mac
with 16 GB of memory: a llama.cpp server, the 2-bit GSQ-RCO GGUF, and the [Pi](https://pi.dev) coding agent
tuned for a small context window.

This repo holds scripts and config only. The model (~9.8 GB), llama.cpp and Pi are downloaded again by
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
| `CTX=16384 ./scripts/start-server.sh` | Tighter context, faster and lighter on 16 GB (default is 24576) |
| `QUANT=<other quant> ./scripts/start-server.sh` | Use (and download) another quant in `ISTA-DASLab/Inkling-2-Mini-GSQ-RCO-GGUF`; Q2 stays the default |
| `VISION=0 ./scripts/start-server.sh` | Text-only: disables the vision projector (default is `VISION=1`). Vision eats context tokens, so consider `CTX=8192` |
| `VISION=0 ./scripts/verify.sh` | Skip the vision smoke test (default is enabled) |
| `WORKDIR=~/code/app ./scripts/pi.sh` | Run Pi on another folder |
| `SANDBOX=1 ./scripts/pi.sh` | macOS sandbox: shell commands can't write outside the work folder |
| `PI_MAX_TOOL_CHARS=4000 ./scripts/pi.sh` | Tighter cap on each tool result |
| `TRIM_START=0.8 TRIM_TARGET=0.3 ./scripts/pi.sh` | When context trimming starts and how far it cuts (default 0.70 → 0.30); `TRIM_OFF=1` disables it |

## What's here

| Path | Purpose |
|---|---|
| `scripts/setup.sh` | Rebuilds llama.cpp (Unsloth build `b12776-mix-ef2df21`), the model and Pi 1.6.1 |
| `scripts/start-server.sh` | `llama-server` on 127.0.0.1:8080, tuned for 16 GB |
| `scripts/download-model.sh` | Downloads a GGUF from `ISTA-DASLab/Inkling-2-Mini-GSQ-RCO-GGUF`, verifies SHA-256; `VISION=0` downloads only the LLM GGUF; default fetches the mmproj projector (`mmproj-Inkling-2-Mini-BF16.gguf`, ~640 MB) alongside it |
| `scripts/verify.sh` | Smoke test |
| `scripts/bench-context.sh` | Measures context sizes with the real server and Pi; results in `bench/` |
| `scripts/pi.sh` | Launches Pi; syncs its context window and compaction to the server's `n_ctx` |
| `pi/agent/models.json` | Local endpoint, sampling, thinking level mapped to `reasoning_effort` |
| `pi/agent/settings.json` | Defaults (thinking: low) and compaction scaled to the context |
| `pi/agent/APPEND_SYSTEM.md` | Rules that keep reads, searches and command output small |
| `pi/agent/extensions/workdir-guard.ts` | Blocks write/edit outside the work folder |
| `pi/agent/extensions/output-cap.ts` | Cuts any tool result over 6,000 characters |
| `pi/agent/extensions/output-room.ts` | Lets replies use the room really left in the window; Pi otherwise holds back 4,096 tokens, cutting replies short past ~12K |
| `pi/agent/extensions/context-trim.ts` | Past 70% of the window, replaces old tool output, long tool arguments and old thinking with one-line notes (no model call) |

Not tracked: `models/`, `llama.cpp/`, `vendor/`, `pi/node/`, and Pi's `auth.json`, `sessions/` and caches.

Note: `scripts/pi.sh` rewrites `contextWindow` in `models.json` and `compaction` in `settings.json`
to match the running server, so those files show as changed after you use a different `CTX`.
Run `git checkout pi/agent` before committing if you don't want to keep that.
