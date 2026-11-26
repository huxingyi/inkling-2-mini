// Gives the model the output room that actually fits in the window.
//
// Pi sets max_tokens to contextWindow - input - 4096: a fixed margin for cloud services that count
// tokens higher than Pi does. On a 16K window that is 25% of it, so at ~12K of input the model gets
// only a few hundred tokens and replies end with "Response was truncated before completion".
// llama-server counts exactly, so for a local model this raises max_tokens (never lowers it) to
//   min(model maxTokens, contextWindow - input - margin),  margin = max(256, 3% of input).
// Env: OUTPUT_MARGIN=256 (minimum margin in tokens)
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const MIN_MARGIN = Number(process.env.OUTPUT_MARGIN || 256);

export default function (pi: ExtensionAPI) {
  pi.on("before_provider_request", (event, ctx) => {
    const p = event.payload as Record<string, unknown> | undefined;
    if (!p || typeof p.max_tokens !== "number") return;
    const model = ctx.model as { baseUrl?: string; contextWindow?: number; maxTokens?: number } | undefined;
    if (!model?.contextWindow || !model.maxTokens) return;
    if (!/\/\/(127\.0\.0\.1|localhost|\[::1\])[:/]/.test(model.baseUrl ?? "")) return; // local servers only
    const input = ctx.getContextUsage?.()?.tokens;
    if (input == null) return;
    const room = Math.min(model.maxTokens, model.contextWindow - input - Math.max(MIN_MARGIN, Math.ceil(input * 0.03)));
    if (room <= p.max_tokens) return;
    return { ...p, max_tokens: room };
  });
}
