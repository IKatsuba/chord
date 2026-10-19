/**
 * Each turn's own cost, found from the session's cost so far as it moves,
 * for the record to keep beside the turn's tokens (CHD-373, CHD-378's
 * "A session's whole spend"). An agent's cost is a sum so far, counted from
 * the opening or from the session's start (`cost_counts.ts`), so a turn's is
 * what the sum moved by in it, within one opening of the session; only the
 * first figure of an opening needs to know which.
 */
import type { SessionUpdate } from '@agentclientprotocol/sdk';
import type { CostCount } from '../cost_counts.ts';
import { filledIn } from './enrich.ts';
import { PRICE_CURRENCY, turnCost } from './prices.ts';
import type { TokenUsage } from './usage.ts';

/** A session's cost so far, as one `usage_update` gave it. */
export interface CostReading {
  readonly amount: number;
  readonly currency: string;
  /** chord's estimate, from the turns' tokens, not the agent's figure. */
  readonly estimated: boolean;
}

/** What a turn's record line carries of its cost. */
export interface TurnCost {
  readonly cost?: { readonly amount: number; readonly currency: string };
  readonly estimated?: true;
  /**
   * The agent gave a cost in the turn that cannot be told apart from what
   * came before it, and chord had no tokens to price it by: the turn is left
   * out of the session's sum, and said to be.
   */
  readonly uncounted?: true;
}

/** What one opening of a session knows of its cost. */
export interface OpeningCosts {
  /** What the agent's cost counts from; none where it is not known. */
  readonly counts: CostCount | undefined;
  /** The opening goes on in a record chord kept, from where `past` left it. */
  readonly resumed: boolean;
  /** The last cost the record kept from before this opening. */
  readonly past?: CostReading | undefined;
  /** The last cost heard in this opening. */
  readonly seen?: CostReading | undefined;
}

/** The cost a `usage_update` says the session has come to, if it says one. */
export function costReading(update: SessionUpdate): CostReading | undefined {
  if (
    update.sessionUpdate !== 'usage_update' ||
    typeof update.cost?.amount !== 'number' ||
    typeof update.cost.currency !== 'string'
  ) {
    return undefined;
  }

  return {
    amount: update.cost.amount,
    currency: update.cost.currency,
    estimated: filledIn(update).includes('cost'),
  };
}

/** The last cost among a session's own updates, as its record replays them. */
export function lastReading(
  updates: readonly SessionUpdate[],
): CostReading | undefined {
  return updates.reduce<CostReading | undefined>(
    (last, update) => costReading(update) ?? last,
    undefined,
  );
}

/**
 * The cost of the turn that began when the opening's last cost was `before`
 * and has it at `opening.seen` now, the turn's `tokens` and `model` to price
 * it by where nothing else tells it.
 */
export function costOfTurn(
  opening: OpeningCosts,
  before: CostReading | undefined,
  tokens: TokenUsage | undefined,
  model: string | undefined,
): TurnCost {
  const after = opening.seen;

  // Nothing new in the turn: it cost nothing anyone reported.
  if (
    after === undefined ||
    (after.amount === before?.amount && after.currency === before.currency)
  ) {
    return {};
  }

  const less = (amount: number): TurnCost => ({
    cost: {
      amount: Math.max(0, after.amount - amount),
      currency: after.currency,
    },
    ...(after.estimated ? { estimated: true as const } : {}),
  });

  if (before !== undefined) {
    return before.currency === after.currency ? less(before.amount) : {};
  }

  const { past } = opening;

  // chord's estimate goes on from the record's, which it was given back.
  if (after.estimated) {
    return less(
      past?.estimated === true && past.currency === after.currency
        ? past.amount
        : 0,
    );
  }

  if (!opening.resumed || opening.counts === 'opening') {
    return less(0);
  }

  if (opening.counts === 'session') {
    return past === undefined || past.estimated
      ? less(0)
      : past.currency === after.currency
        ? less(past.amount)
        : {};
  }

  // Whether this is the turn's or the session's is not known: the turn's
  // tokens priced, as for an agent that gives no cost (the owner's Q61).
  const priced =
    tokens === undefined || model === undefined
      ? undefined
      : turnCost(model, tokens);

  return priced === undefined
    ? { uncounted: true }
    : {
        cost: { amount: priced, currency: PRICE_CURRENCY },
        estimated: true,
      };
}
