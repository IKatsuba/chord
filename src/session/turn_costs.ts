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
import { COST } from './transcript/subagents.ts';
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
  /**
   * Not a turn's: what an older record spent before it kept each turn's
   * cost, its last cost then, as last reported, up to when it began to,
   * where it says (the owner's Q62).
   */
  readonly before?: { readonly until?: number };
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
  if (update.sessionUpdate !== 'usage_update') {
    return undefined;
  }

  // An agent or a record may have bent it: one that does not read as a
  // cost is none.
  const cost = COST.safeParse(update.cost);

  return cost.success
    ? { ...cost.data, estimated: filledIn(update).includes('cost') }
    : undefined;
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

  // No cost came in the turn: it cost nothing anyone reported. One that
  // came and did not move is a turn of nothing, which it says.
  if (after === undefined || after === before) {
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

/** A turn's figures as the conversation reports them: its tokens and cost. */
export type TurnFigures = {
  readonly turnId: string;
  readonly usage: TokenUsage;
  /** The model the turn ended on. */
  readonly model?: string;
} & TurnCost;

/** A turn or cycle as its cost is found, from its beginning to the next's. */
interface CostTurn {
  readonly id: string;
  /** The opening's cost when it began. */
  readonly before: CostReading | undefined;
  /** It has ended; what comes under it now is its tail. */
  over: boolean;
  tokens?: TokenUsage | undefined;
  model?: string | undefined;
  /** Its cost as it was last reported. */
  reported?: string;
}

/**
 * One opening of a session's turns and their costs: each turn's figures as
 * it ends, and again when its cost comes after its end, as Claude's can.
 */
export class TurnCosts {
  #opening: OpeningCosts;
  /**
   * The turn or cycle that began last, until the next begins: a cost that
   * comes after its end is still its.
   */
  #turn: CostTurn | undefined;

  /**
   * An opening of a session on an agent whose cost counts as `counts`
   * says, going on in a record chord kept when `resumed`, whose own updates
   * are `past`.
   */
  constructor(
    counts: CostCount | undefined,
    resumed: boolean,
    past: readonly SessionUpdate[],
  ) {
    this.#opening = { counts, resumed, past: lastReading(past) };
  }

  /** A turn or the agent's own cycle began, from the cost there is now. */
  began(turnId: string): void {
    this.#turn = { id: turnId, before: this.#opening.seen, over: false };
  }

  /**
   * One of the session's own updates, under `turnId`: the figures of the
   * turn it came after the end of, when it moved that turn's cost.
   */
  heard(turnId: string, update: SessionUpdate): TurnFigures | undefined {
    const reading = costReading(update);

    if (reading === undefined) {
      return undefined;
    }

    this.#opening = { ...this.#opening, seen: reading };

    const turn = this.#turn;

    return turn?.over === true && turn.id === turnId
      ? this.#figures(turn, false)
      : undefined;
  }

  /**
   * As `heard`, under the turn or cycle that began last: for a session let
   * go, whose updates no turn of the window's takes any more (CHD-373 S3c).
   */
  heardLast(update: SessionUpdate): TurnFigures | undefined {
    return this.heard(this.#turn?.id ?? '', update);
  }

  /**
   * A turn or cycle ended, with the tokens its answer gave and the model it
   * was on: its figures, always for one with tokens, else only when it has a
   * cost to say.
   */
  ended(
    turnId: string,
    tokens: TokenUsage | undefined,
    model: string | undefined,
  ): TurnFigures | undefined {
    const turn = this.#turn;

    if (turn?.id !== turnId) {
      return tokens === undefined ? undefined : { turnId, usage: tokens };
    }

    turn.over = true;
    turn.tokens = tokens;
    turn.model = model;

    return this.#figures(turn, tokens !== undefined);
  }

  #figures(turn: CostTurn, always: boolean): TurnFigures | undefined {
    const cost = costOfTurn(
      this.#opening,
      turn.before,
      turn.tokens,
      turn.model,
    );
    const said = JSON.stringify(cost);

    if (!always && said === (turn.reported ?? JSON.stringify({}))) {
      return undefined;
    }

    turn.reported = said;

    return {
      turnId: turn.id,
      usage: turn.tokens ?? {},
      ...(turn.model === undefined ? {} : { model: turn.model }),
      ...cost,
    };
  }
}
