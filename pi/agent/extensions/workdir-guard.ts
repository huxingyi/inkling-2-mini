// Blocks write/edit tool calls that target files outside the folder Pi was started in.
// Symlinks are resolved, so a link inside the folder can't point the edit elsewhere.
// The blocked reason goes back to the model, so it can retry with a path inside the folder.
import { isToolCallEventType, type ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { realpathSync, existsSync } from "node:fs";
import { dirname, isAbsolute, resolve, sep } from "node:path";
import { homedir } from "node:os";

function real(p: string): string {
  // New files don't exist yet: resolve the deepest existing ancestor, then re-append the rest.
  let cur = p, rest = "";
  while (!existsSync(cur) && dirname(cur) !== cur) {
    const part = cur.slice(dirname(cur).length + 1);
    rest = rest ? `${part}${sep}${rest}` : part;
    cur = dirname(cur);
  }
  const base = realpathSync(cur);
  return rest ? resolve(base, rest) : base;
}

export default function (pi: ExtensionAPI) {
  pi.on("tool_call", async (event, ctx) => {
    if (!isToolCallEventType("write", event) && !isToolCallEventType("edit", event)) return;
    const raw = String((event.input as { path?: string }).path ?? "");
    const expanded = raw.startsWith("~") ? homedir() + raw.slice(1) : raw;
    const target = real(isAbsolute(expanded) ? expanded : resolve(ctx.cwd, expanded));
    const root = real(ctx.cwd);
    if (target === root || target.startsWith(root + sep)) return;
    return { block: true, reason: `Blocked: ${raw} is outside the work folder ${root}. Only edit files inside it.` };
  });
}
