/**
 * What a session has spent: each turn's tokens, as the agent's answer to its
 * prompt gives them, and its own cost, as chord found it, kept by chord for
 * the life of the window.
 */
import type { Usage } from '@agentclientprotocol/sdk';
import type { TurnCost } from './turn_costs.ts';

/**
 * A turn's tokens. A field the agent did not report is absent, never zero,
 * so a report can say what it was not told.
 */
export interface TokenUsage {
  readonly inputTokens?: number;
  readonly outputTokens?: number;
  readonly cachedReadTokens?: number;
  readonly cachedWriteTokens?: number;
  readonly thoughtTokens?: number;
  readonly totalTokens?: number;
}

export const TOKEN_FIELDS = [
  'inputTokens',
  'outputTokens',
  'cachedReadTokens',
  'cachedWriteTokens',
  'thoughtTokens',
  'totalTokens',
] as const satisfies readonly (keyof TokenUsage)[];

/** ACP's `Usage` without its nulls and `_meta`. */
export function tokensOf(usage: Usage): TokenUsage {
  return Object.fromEntries(
    TOKEN_FIELDS.flatMap((field) =>
      typeof usage[field] === 'number' ? [[field, usage[field]]] : [],
    ),
  );
}

/** A turn's own cost as a session keeps it, with the model it ended on. */
export type SpentTurn = TurnCost & { readonly model?: string };

export interface Spent {
  /** Each turn's tokens by the turn's id, every one the agent reported. */
  readonly turns: Readonly<Record<string, TokenUsage>>;
  /**
   * The session's tokens as an agent whose answers give its running total
   * last gave them, in place of each turn's (CHD-472).
   */
  readonly total?: TokenUsage;
  /**
   * Each turn's own cost by the turn's id, the agent's own cycles' among
   * them, where it had one or was left uncounted (CHD-373).
   */
  readonly costs?: Readonly<Record<string, SpentTurn>>;
}

/**
 * `spent` with a turn's tokens, where it has any, and its cost; a turn
 * reported again replaces its own. Tokens that are the session's running
 * `total` replace the total it had, and no turn keeps them.
 */
export function addTurn(
  spent: Spent | undefined,
  turnId: string,
  tokens: TokenUsage,
  cost: SpentTurn = {},
  total = false,
): Spent {
  const { [turnId]: _, ...costs } = spent?.costs ?? {};
  const counted = cost.cost !== undefined || cost.uncounted === true;
  const some = Object.keys(tokens).length > 0;

  return {
    ...spent,
    ...(total && some ? { total: tokens } : {}),
    turns:
      !some || total
        ? (spent?.turns ?? {})
        : { ...spent?.turns, [turnId]: tokens },
    ...(counted || spent?.costs !== undefined
      ? { costs: counted ? { ...costs, [turnId]: cost } : costs }
      : {}),
  };
}
