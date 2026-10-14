/**
 * What a model costs and how large its context window is, from
 * @pydantic/genai-prices' data, which its package carries: nothing is fetched,
 * and the data moves only with the pinned version.
 */
import { calcPrice, type PriceCalculation } from '@pydantic/genai-prices';
import type { TokenUsage } from './usage.ts';

/** The currency genai-prices gives every price in. */
export const PRICE_CURRENCY = 'USD';

/**
 * What a turn's tokens cost on `model`, in `PRICE_CURRENCY`; undefined for a
 * model the data does not know, or tokens it cannot price.
 */
export function turnCost(
  model: string,
  tokens: TokenUsage,
): number | undefined {
  return lookUp(model, priced(tokens))?.total_price;
}

/** `model`'s context window in tokens, when the data gives one. */
export function contextWindow(model: string): number | undefined {
  const size = lookUp(model, { input_tokens: 0 })?.model.context_window;

  return typeof size === 'number' && size > 0 ? size : undefined;
}

/**
 * The tokens that fill the context after a turn: what went in and what came
 * out. For a turn of one request that is the context; a turn of several
 * counts what went in more than once, so it reads as fuller than it is.
 */
export function contextFrom(tokens: TokenUsage): number {
  const usage = priced(tokens);

  return (usage.input_tokens ?? 0) + (usage.output_tokens ?? 0);
}

/**
 * ACP's counts as genai-prices takes them, where the input includes what was
 * read from or written to the cache and the output the thinking. ACP does not
 * say whether an agent's input already includes its cache, as OpenAI's does,
 * or not, as Anthropic's does; the total says which sum the agent made, and
 * without one the counts are taken as apart, the way ACP lists them.
 */
function priced(tokens: TokenUsage): Record<string, number> {
  const input = tokens.inputTokens ?? 0;
  const output = tokens.outputTokens ?? 0;
  const read = tokens.cachedReadTokens ?? 0;
  const written = tokens.cachedWriteTokens ?? 0;
  const thought = tokens.thoughtTokens ?? 0;
  const total = tokens.totalTokens;
  const cacheInside =
    total !== undefined &&
    (total === input + output + thought || total === input + output);
  const thoughtInside =
    total !== undefined &&
    (total === input + output + read + written || total === input + output);

  return {
    input_tokens: cacheInside ? input : input + read + written,
    output_tokens: thoughtInside ? output : output + thought,
    cache_read_tokens: read,
    cache_write_tokens: written,
  };
}

/**
 * The data's entry for `model`. Agents name models their own way: Codex's
 * adapter adds the effort after a slash, Claude's a `[1m]`, a router puts the
 * provider first; each shorter name is tried after the whole one.
 */
function lookUp(
  model: string,
  usage: Record<string, number>,
): PriceCalculation | undefined {
  const bare = model.replace(/\[[^\]]*\]$/, '');
  const parts = bare.split('/');
  const names = new Set([model, bare, parts[0] ?? bare, parts.at(-1) ?? bare]);

  for (const name of names) {
    try {
      const found = calcPrice(usage, name);

      if (found !== null) {
        return found;
      }
    } catch {
      // Counts the data refuses, such as more read from the cache than went
      // in, price nothing rather than stop the session.
      return undefined;
    }
  }

  return undefined;
}
