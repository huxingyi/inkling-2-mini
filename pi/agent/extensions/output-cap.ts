// Caps every tool result before it enters the conversation, so one big file, web page or
// log can't overflow a small context window. Keeps the start and the end, and tells the
// model how to ask for less. Limit: PI_MAX_TOOL_CHARS (default 6000 chars, ~1.5-2.5K tokens).
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const MAX = Number(process.env.PI_MAX_TOOL_CHARS || 6000);

export default function (pi: ExtensionAPI) {
  pi.on("tool_result", async (event) => {
    const parts = (event.content ?? []) as Array<{ type: string; text?: string }>;
    const total = parts.reduce((n, p) => n + (p.type === "text" ? (p.text ?? "").length : 0), 0);
    if (total <= MAX) return;
    const text = parts.filter((p) => p.type === "text").map((p) => p.text ?? "").join("\n");
    const head = Math.floor(MAX * 0.7), tail = MAX - head;
    const note =
      `\n\n[... ${total - MAX} of ${total} characters cut by output-cap to protect the small context window. ` +
      `Ask for less: rg -n "pattern" | head -30, sed -n 'START,ENDp', read with offset/limit, head -c 3000, ` +
      `or strip HTML first. ...]\n\n`;
    const capped = text.slice(0, head) + note + text.slice(text.length - tail);
    return { content: [...parts.filter((p) => p.type !== "text"), { type: "text", text: capped }] };
  });
}
