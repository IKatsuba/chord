/**
 * What a session has spent: each turn's tokens, as the agent's answer to its
 * prompt gives them, kept by chord for the life of the window.
 */
import type { Usage } from '@agentclientprotocol/sdk';

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

export interface Spent {
  /** Each turn's tokens by the turn's id, every one the agent reported. */
  readonly turns: Readonly<Record<string, TokenUsage>>;
}

/** `spent` with a turn's tokens; a turn reported again replaces its own. */
export function addTurn(
  spent: Spent | undefined,
  turnId: string,
  tokens: TokenUsage,
): Spent {
  return { turns: { ...spent?.turns, [turnId]: tokens } };
}
