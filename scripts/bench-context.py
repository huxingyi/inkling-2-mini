#!/usr/bin/env python3
"""Finds the largest practical context size for this Mac, with the real server and real Pi.

For each size (smallest first) it starts llama-server, records memory and swap, fills the context
to 90% with this repo's own files plus a fact planted at the very start, asks for that fact back,
and runs Pi on a real read-only task. It stops at the first size that fails or starts swapping.
Results: bench/results.md (summary) and bench/*.log. Run it via scripts/bench-context.sh.
"""
import json, os, re, subprocess, sys, time, urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "bench"; OUT.mkdir(exist_ok=True)
URL = "http://127.0.0.1:8080"
# Each entry is CTX or CTX:UBATCH, e.g. "24576 32768:256".
SIZES = [(int(x.split(":")[0]), x.split(":")[1] if ":" in x else None) for x in os.environ.get("CTXS", "16384 32768 49152 65536").split()]
NEEDLE = "AMBER-FALCON-7731"
PI_TASK = ("Answer three questions about this repo by reading only the files you need; do not change anything. "
           "1) Which llama.cpp TAG does scripts/setup.sh install? 2) What is the default context size (DEF_CTX) "
           "for the 2-bit model in scripts/start-server.sh? 3) Which environment variable makes scripts/pi.sh work "
           "in another folder? Reply with three short lines.")
PI_EXPECT = ["b12722", "16384", "WORKDIR"]

def log(msg):
    line = f"[{time.strftime('%H:%M:%S')}] {msg}"
    print(line, flush=True)
    with open(OUT / "progress.log", "a") as f: f.write(line + "\n")

def post(path, body, timeout=3600):
    req = urllib.request.Request(URL + path, data=json.dumps(body).encode(), headers={"Content-Type": "application/json"})
    return json.load(urllib.request.urlopen(req, timeout=timeout))

def healthy():
    try: return json.load(urllib.request.urlopen(URL + "/health", timeout=3)).get("status") == "ok"
    except Exception: return False

def mem():
    out = {}
    try:
        p = subprocess.run(["memory_pressure"], capture_output=True, text=True, timeout=20).stdout
        m = re.search(r"free percentage:\s*(\d+)%", p); out["free_pct"] = int(m.group(1)) if m else None
    except Exception: out["free_pct"] = None
    s = subprocess.run(["sysctl", "-n", "vm.swapusage"], capture_output=True, text=True).stdout
    m = re.search(r"used = ([\d.]+)M", s); out["swap_mb"] = float(m.group(1)) if m else None
    v = subprocess.run(["vm_stat"], capture_output=True, text=True).stdout
    m = re.search(r"Swapouts:\s+(\d+)", v); out["swapouts"] = int(m.group(1)) if m else None
    m = re.search(r"Swapins:\s+(\d+)", v); out["swapins"] = int(m.group(1)) if m else None
    return out

def filler_text():
    parts = []
    for p in sorted(ROOT.glob("scripts/*.sh")) + [ROOT / "README.md", ROOT / "pi/agent/APPEND_SYSTEM.md"] + \
             sorted(ROOT.glob("pi/agent/extensions/*.ts")) + sorted(ROOT.glob("docs/*.html")):
        try: t = p.read_text(errors="replace")
        except Exception: continue
        if p.suffix == ".html":
            t = re.sub(r"(?s)<(script|style).*?</\1>", " ", t); t = re.sub(r"<[^>]+>", " ", t); t = re.sub(r"\s+", " ", t)
        parts.append(f"=== {p.relative_to(ROOT)} ===\n{t}\n")
    return "".join(parts)

def server_buffers(logfile):
    keep = []
    for line in Path(logfile).read_text(errors="replace").splitlines():
        if re.search(r"(KV|kv).*(size|buffer)|compute buffer|model buffer|MiB|recommendedMaxWorkingSetSize|n_ctx", line) and len(keep) < 40:
            keep.append(line.strip()[:200])
    return keep

def run_size(ctx, ubatch=None):
    r = {"ctx": ctx, "ubatch": ubatch or "512"}
    logfile = OUT / f"server-{ctx}-{r['ubatch']}.log"
    r["mem_before"] = mem()
    log(f"--- {ctx} tokens (micro-batch {r['ubatch']}): starting server")
    env = dict(os.environ, CTX=str(ctx))
    if ubatch: env["UBATCH"] = ubatch
    t0 = time.time()
    proc = subprocess.Popen([str(ROOT / "scripts/start-server.sh")], cwd=ROOT, env=env,
                            stdout=open(logfile, "w"), stderr=subprocess.STDOUT)
    try:
        while not healthy():
            if proc.poll() is not None or time.time() - t0 > 600:
                r["error"] = "server did not start (see log tail)"
                r["log_tail"] = Path(logfile).read_text(errors="replace").splitlines()[-15:]
                return r
            time.sleep(2)
        r["load_s"] = round(time.time() - t0)
        r["buffers"] = server_buffers(logfile)
        r["mem_loaded"] = mem()
        log(f"loaded in {r['load_s']}s, memory free {r['mem_loaded']['free_pct']}%, swap {r['mem_loaded']['swap_mb']} MB")

        # Baseline generation speed with an almost empty context.
        b = post("/v1/chat/completions", {"messages": [{"role": "user", "content": "Write a 120-word paragraph about tea."}],
                 "max_tokens": 160, "temperature": 0, "chat_template_kwargs": {"reasoning_effort": "none"}})
        r["gen_tps_empty"] = round(b["timings"]["predicted_per_second"], 1)

        # Fill to ~90% with real repo text, the fact at the very start, the question at the end.
        unit = filler_text()
        unit_tokens = len(post("/tokenize", {"content": unit})["tokens"])
        target = int(ctx * 0.9) - 300
        body = (unit * (target // unit_tokens + 1))
        body = body[: int(len(body) * target / ((target // unit_tokens + 1) * unit_tokens))]
        prompt = (f"NOTE FOR LATER: the release codename is {NEEDLE}.\n\nReference material follows.\n\n{body}\n\n"
                  "Question: what is the release codename given in the NOTE FOR LATER at the very beginning? "
                  "Reply with only the codename.")
        log(f"filling ~{target} tokens (expect ~{target // 80}s+)")
        t1 = time.time()
        a = post("/v1/chat/completions", {"messages": [{"role": "user", "content": prompt}], "max_tokens": 600,
                 "temperature": 0, "cache_prompt": False, "chat_template_kwargs": {"reasoning_effort": "none"}})
        t = a["timings"]
        r["fill_tokens"] = t["prompt_n"]; r["fill_s"] = round(time.time() - t1)
        r["prompt_tps_full"] = round(t["prompt_per_second"], 1)
        r["gen_tps_full"] = round(t["predicted_per_second"], 1) if t.get("predicted_n", 0) > 1 else None
        msg = a["choices"][0]["message"]
        ans = (msg.get("content") or "").strip()
        r["needle_answer"] = ans[:80]
        r["needle_ok"] = NEEDLE in ans or NEEDLE in (msg.get("reasoning_content") or "")
        r["mem_full"] = mem()
        log(f"read {r['fill_tokens']} tokens in {r['fill_s']}s ({r['prompt_tps_full']} tok/s); "
            f"fact recalled: {r['needle_ok']}; memory free {r['mem_full']['free_pct']}%")

        # Real Pi run against this server (pi.sh syncs Pi's context window to it).
        log("running Pi on a real task")
        t2 = time.time()
        try:
            p = subprocess.run([str(ROOT / "scripts/pi.sh"), "--mode", "json", "--no-session", "-p", PI_TASK],
                               cwd=ROOT, env=dict(os.environ, WORKDIR=str(ROOT)), capture_output=True, text=True, timeout=1200)
            (OUT / f"pi-{ctx}-{r['ubatch']}.jsonl").write_text(p.stdout)
            final, peak, turns = "", 0, 0
            for line in p.stdout.splitlines():
                try: ev = json.loads(line)
                except Exception: continue
                m = ev.get("message") or {}
                if ev.get("type") == "message_end" and m.get("role") == "assistant":
                    turns += 1; peak = max(peak, (m.get("usage") or {}).get("totalTokens", 0))
                    txt = "".join(c.get("text", "") for c in m.get("content", []) if c.get("type") == "text").strip()
                    if txt: final = txt
            r["pi_s"] = round(time.time() - t2); r["pi_turns"] = turns; r["pi_peak_ctx"] = peak
            r["pi_answer"] = final[:300]
            r["pi_ok"] = all(x.lower() in final.lower() for x in PI_EXPECT)
            if p.returncode != 0: r["pi_error"] = p.stderr.strip().splitlines()[-3:]
        except subprocess.TimeoutExpired:
            r["pi_s"] = 1200; r["pi_ok"] = False; r["pi_error"] = ["timed out after 20 min"]
        log(f"Pi: {r.get('pi_turns')} turns in {r['pi_s']}s, correct: {r['pi_ok']}")
        r["mem_end"] = mem()
        r["swapin_mb_while_working"] = round(((r["mem_end"].get("swapins") or 0) - (r["mem_loaded"].get("swapins") or 0)) * 16 / 1024)
        log(f"swap read back while working: {r['swapin_mb_while_working']} MB; swap used {r['mem_end']['swap_mb']} MB")
        return r
    except Exception as e:
        r["error"] = f"{type(e).__name__}: {e}"
        r["log_tail"] = Path(logfile).read_text(errors="replace").splitlines()[-15:]
        return r
    finally:
        proc.terminate()
        try: proc.wait(30)
        except subprocess.TimeoutExpired: proc.kill()
        time.sleep(5)

def write_report(results):
    (OUT / "results.json").write_text(json.dumps(results, indent=1))
    rows = ["| Context:micro-batch | Starts | Free mem (loaded → full) | Swap used | Read speed at 90% | Full re-read | Gen tok/s (empty → full) | Fact recalled | Pi correct | Pi time | Swap read back |",
            "|---|---|---|---|---|---|---|---|---|---|---|"]
    for r in results:
        if "error" in r and "fill_tokens" not in r:
            rows.append(f"| {r['ctx']}:{r['ubatch']} | NO: {r['error']} | | | | | | | | | |"); continue
        ml, mf = r.get("mem_loaded", {}), r.get("mem_full", {})
        rows.append(f"| {r['ctx']}:{r['ubatch']} | yes ({r.get('load_s')}s) | {ml.get('free_pct')}% → {mf.get('free_pct')}% | "
                    f"{mf.get('swap_mb')} MB | {r.get('prompt_tps_full')} tok/s | {r.get('fill_s')}s | "
                    f"{r.get('gen_tps_empty')} → {r.get('gen_tps_full')} | {r.get('needle_ok')} | {r.get('pi_ok')} | {r.get('pi_s')}s | {r.get('swapin_mb_while_working')} MB |")
    (OUT / "results.md").write_text("# Context size benchmark\n\n" + "\n".join(rows) + "\n\nDetails: results.json, server-*.log, pi-*.jsonl\n")

def main():
    if healthy():
        sys.exit("A server is already running on 127.0.0.1:8080. Stop it first (Ctrl+C in its tab), then re-run.")
    (OUT / "progress.log").write_text("")
    results = []
    for ctx, ub in SIZES:
        r = run_size(ctx, ub); results.append(r); write_report(results)
        if os.environ.get("NO_STOP"): continue
        base = results[0]
        slow = r.get("gen_tps_full") and base.get("gen_tps_full") and r["gen_tps_full"] < 0.6 * base["gen_tps_full"]
        if "error" in r or not r.get("pi_ok") or slow or (r.get("swapin_mb_while_working") or 0) > 2000:
            log(f"stopping: {ctx} failed, got too slow or swapped heavily"); break
    log("done: see bench/results.md")

if __name__ == "__main__":
    main()
