// Trims old tool output from what is sent to the model, so a 16K window lasts much longer.
// No model call is involved: old tool results, long tool-call arguments (heredocs, file contents)
// and old thinking are replaced in code with one-line notes. The saved session keeps everything.
//
// It waits until the context passes TRIM_START (75% of the window) and then cuts, oldest first,
// down to TRIM_TARGET (30%). The server then has to re-read the conversation once from the first
// changed message (~4-5K tokens, ~50-60 s at 88 tok/s); the system prompt and your first message stay cached.
// Cuts are permanent for the session, so the turns between trims stay fast.
// The last TRIM_KEEP_TURNS (3) model turns, your messages and the model's replies are never cut.
//
// Env: TRIM_START=0.75 TRIM_TARGET=0.30 TRIM_KEEP_TURNS=3 TRIM_OFF=1 (disable)
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const START = Number(process.env.TRIM_START || 0.75);
const TARGET = Number(process.env.TRIM_TARGET || 0.3);
const KEEP_TURNS = Number(process.env.TRIM_KEEP_TURNS || 3);
const CHARS_PER_TOKEN = 3.5; // rough; only used to estimate how much a cut saves
const MIN_CHARS = 400;       // smaller pieces aren't worth a note

type Part = { type: string; text?: string; thinking?: string; id?: string; name?: string; arguments?: any; [k: string]: unknown };
type Msg = { role: string; content?: Part[] | string; toolCallId?: string; toolName?: string; [k: string]: unknown };

const len = (x: unknown) => (typeof x === "string" ? x.length : JSON.stringify(x ?? "").length);
const oneLine = (s: unknown, n: number) => String(s ?? "").replace(/\s+/g, " ").trim().slice(0, n);

function label(name: string, args: any): string {
  const a = args ?? {};
  if (name === "bash") return `bash: ${oneLine(a.command, 70)}`;
  if (name === "read") return `read ${a.path ?? ""}${a.offset ? ` from line ${a.offset}` : ""}`;
  return `${name} ${oneLine(a.path ?? a.pattern ?? "", 70)}`;
}

// Replacement for a tool call's arguments: keep what was done, drop the bulk.
function shrinkArgs(name: string, args: any): any {
  const a = { ...(args ?? {}) };
  for (const k of Object.keys(a)) {
    const v = a[k];
    if (typeof v !== "string" || v.length < 200) continue;
    a[k] = k === "command"
      ? `${v.slice(0, 120)} ... [${v.length - 120} chars removed from context]`
      : `[${v.length} chars removed from context]`;
  }
  return a;
}

export default function (pi: ExtensionAPI) {
  if (process.env.TRIM_OFF) return;
  // toolCallIds whose call+result have been cut. Only grows, so every later request sends the
  // same text for them and the server's cache stays valid up to the newest turn.
  const cut = new Set<string>();

  function apply(messages: Msg[]): { messages: Msg[]; changed: boolean } {
    let changed = false;
    const out = messages.map((m) => {
      if (m.role === "toolResult" && m.toolCallId && cut.has(m.toolCallId)) {
        const parts = Array.isArray(m.content) ? m.content : [];
        const size = parts.reduce((n, p) => n + (p.type === "text" ? (p.text ?? "").length : 0), 0);
        if (size < MIN_CHARS) return m;
        changed = true;
        const lines = parts.map((p) => p.text ?? "").join("\n").split("\n").length;
        return { ...m, content: [{ type: "text", text: `[${m.toolName ?? "tool"} output removed from context: ${lines} lines, ${size} chars. Run it again if you still need it.]` }] };
      }
      if (m.role === "assistant" && Array.isArray(m.content)) {
        const calls = m.content.filter((p) => p.type === "toolCall");
        if (!calls.length || !calls.every((p) => p.id && cut.has(p.id))) return m;
        const content = m.content
          .filter((p) => !(p.type === "thinking" && len(p.thinking) >= MIN_CHARS))
          .map((p) => (p.type === "toolCall" && len(p.arguments) >= MIN_CHARS ? { ...p, arguments: shrinkArgs(p.name ?? "", p.arguments) } : p));
        if (len(content) !== len(m.content)) { changed = true; return { ...m, content }; }
      }
      return m;
    });
    return { messages: out, changed };
  }

  pi.on("context", async (event, ctx) => {
    const messages = event.messages as Msg[];
    const usage = ctx.getContextUsage?.();
    const window = usage?.contextWindow ?? ctx.model?.contextWindow;
    let tokens = usage?.tokens;

    if (window && tokens != null && tokens > window * START) {
      // Candidates: tool calls older than the last KEEP_TURNS assistant turns, oldest first.
      let seen = 0, protectFrom = messages.length;
      for (let i = messages.length - 1; i >= 0; i--) {
        if (messages[i].role === "assistant" && ++seen === KEEP_TURNS) { protectFrom = i; break; }
      }
      const resultSize = new Map<string, number>();
      for (const m of messages) if (m.role === "toolResult" && m.toolCallId) resultSize.set(m.toolCallId, len(m.content));
      const goal = window * TARGET;
      for (let i = 0; i < protectFrom && tokens > goal; i++) {
        const m = messages[i];
        if (m.role !== "assistant" || !Array.isArray(m.content)) continue;
        const ids = m.content.filter((p) => p.type === "toolCall" && p.id).map((p) => p.id as string);
        if (!ids.length || ids.every((id) => cut.has(id))) continue;
        let saved = m.content.reduce((n, p) => n + (p.type === "thinking" ? len(p.thinking) : p.type === "toolCall" ? Math.max(0, len(p.arguments) - 200) : 0), 0);
        for (const id of ids) { if (!cut.has(id)) saved += Math.max(0, (resultSize.get(id) ?? 0) - 150); cut.add(id); }
        tokens -= saved / CHARS_PER_TOKEN;
      }
      ctx.ui?.setStatus?.("context-trim", `trimmed old tool output (${cut.size} calls)`);
    }

    if (!cut.size) return;
    const r = apply(messages);
    return r.changed ? { messages: r.messages } : undefined;
  });
}
