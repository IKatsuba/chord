/**
 * What `/cost`, `/context` and `/status` report into the transcript: rows of
 * a label and its value, made from what the agent has said about the session
 * and what chord knows of it. Nothing the agent has not reported is drawn as
 * a zero; the report says the agent has not said.
 */
import type { Cost } from '@agentclientprotocol/sdk';
import { type AgentModels, modelName } from '../../session/models.ts';
import type { AgentMode } from '../../session/modes.ts';
import type { ReportRow, Usage } from '../../session/transcript/types.ts';
import {
  type Spent,
  TOKEN_FIELDS,
  type TokenUsage,
} from '../../session/usage.ts';
import type { AppState } from '../app/state.ts';
import { formatElapsed } from '../../session/elapsed.ts';
import { contextEstimated, contextUsed } from '../status/status.ts';

/** Said after a figure chord worked out itself, never the agent's. */
export const ESTIMATE_NOTE = "(chord's estimate)";

/** The commands that report; each is one of chord's own. */
export type ReportCommand = 'cost' | 'context' | 'status';

/** What a report is made from. */
export interface ReportFacts {
  readonly agent: string;
  readonly cwd: string;
  /** The agent's id for the session, once it is up. */
  readonly sessionId?: string | undefined;
  /** When the session came up, and now, epoch milliseconds. */
  readonly since?: number | undefined;
  readonly now: number;
  readonly models?: AgentModels | undefined;
  /** The id of the mode the agent reports, and the modes it offers. */
  readonly mode?: string | undefined;
  readonly modes: readonly AgentMode[];
  /** Each turn's tokens, as the agent answered its prompt. */
  readonly spent?: Spent | undefined;
  /** The turn running now, by its id; none between turns. */
  readonly running?: string | undefined;
  /** The context window and cost as the last `usage_update` gave them. */
  readonly context?: Usage | undefined;
  /** The sessions open in the window, and how many wait on the person. */
  readonly sessions?: { readonly open: number; readonly waits: number };
}

/** The facts the window holds, for a report run now. */
export function reportFacts(
  state: AppState,
  agent: string,
  cwd: string,
  now: number,
  sessions?: { readonly open: number; readonly waits: number },
): ReportFacts {
  return {
    ...(sessions === undefined ? {} : { sessions }),
    agent,
    cwd,
    sessionId: state.sessionId,
    since: state.since,
    now,
    models: state.models,
    mode: state.transcript.mode,
    modes: state.modes,
    spent: state.spent,
    running: runningTurn(state),
    context: state.transcript.usage,
  };
}

/**
 * The turn of the session running now: one the person or the agent
 * started, not a request held between turns with none running.
 */
function runningTurn(state: AppState): string | undefined {
  const { turn } = state.transcript;

  // A request held inside an agent's own cycle leaves the cycle running
  // (CHD-426): its spend, too, comes when it ends.
  return turn.status === 'idle' ||
    (turn.status === 'awaiting_permission' &&
      turn.between === true &&
      turn.cycle !== true)
    ? undefined
    : turn.turnId;
}

/**
 * What `/cost` says of the turn running, none of whose spend has come yet:
 * an agent reports a turn's spend when it ends, so the totals leave it out
 * until then, and chord guesses nothing (the owner's Q51, CHD-405).
 */
const RUNNING_TURN: [string, string] = ['This turn', 'counted when it ends'];

export function report(
  command: ReportCommand,
  facts: ReportFacts,
): ReportRow[] {
  switch (command) {
    case 'cost':
      return costReport(facts);
    case 'context':
      return contextReport(facts);
    case 'status':
      return statusReport(facts);
  }
}

const TOKENS = new Intl.NumberFormat('en-US');

function tokens(count: number): string {
  return TOKENS.format(count);
}

/** Pads each label to the widest, so the values start in one column. */
function aligned(
  rows: readonly (readonly [string, string] | string)[],
): ReportRow[] {
  const width = Math.max(
    0,
    ...rows.map((row) => (typeof row === 'string' ? 0 : row[0].length + 1)),
  );

  return rows.map((row) =>
    typeof row === 'string'
      ? { text: row }
      : { label: `${row[0]}:`.padEnd(width + 1), text: row[1] },
  );
}

/**
 * The session's tokens, each turn's added up. A field no turn reported stays
 * out rather than reading as zero.
 */
export function sessionTokens(
  spent: Spent | undefined,
): TokenUsage | undefined {
  const each = Object.values(spent?.turns ?? {});
  const sum: Record<string, number> = {};

  for (const field of TOKEN_FIELDS) {
    const counts = each.flatMap((turn) => turn[field] ?? []);

    if (counts.length > 0) {
      sum[field] = counts.reduce((a, b) => a + b, 0);
    }
  }

  return Object.keys(sum).length === 0 ? undefined : sum;
}

/**
 * A cost as Claude Code writes one: dollars to the cent above half a dollar,
 * to a hundredth of a cent below; another currency by its own sign.
 */
export function formatCost(cost: Cost): string {
  const { amount, currency } = cost;
  const digits = amount > 0.5 ? 2 : 4;

  if (currency === 'USD') {
    return `$${amount.toFixed(digits)}`;
  }

  try {
    return new Intl.NumberFormat('en-US', {
      style: 'currency',
      currency,
      minimumFractionDigits: digits,
      maximumFractionDigits: digits,
    }).format(amount);
  } catch {
    // Not a currency code Intl knows; the agent's own words for it.
    return `${amount.toFixed(digits)} ${currency}`;
  }
}

/**
 * `/cost`: the session's tokens in and out, its cost as the last
 * `usage_update` gave it, and how long it ran.
 */
export function costReport(facts: ReportFacts): ReportRow[] {
  const spent = sessionTokens(facts.spent);
  const cost =
    facts.context?.cost === undefined
      ? undefined
      : facts.context.estimated?.includes('cost')
        ? `${formatCost(facts.context.cost)} ${ESTIMATE_NOTE}`
        : formatCost(facts.context.cost);
  const time: [string, string][] =
    facts.since === undefined
      ? []
      : [['Session time', formatElapsed(facts.now - facts.since)]];

  // Nothing of the running turn's spend has come while none of it is in.
  const running: [string, string][] =
    facts.running !== undefined &&
    facts.spent?.turns[facts.running] === undefined
      ? [RUNNING_TURN]
      : [];

  if (spent === undefined && cost === undefined) {
    return aligned([
      `${facts.agent} has not reported what this session has used.`,
      ...running,
      ...time,
    ]);
  }

  const counts: [string, string][] = [
    ['Tokens in', spent?.inputTokens],
    ['Tokens out', spent?.outputTokens],
    ['Cache read', spent?.cachedReadTokens],
    ['Cache written', spent?.cachedWriteTokens],
    ['Thinking', spent?.thoughtTokens],
  ].flatMap(([label, count]) =>
    typeof count === 'number' ? [[label as string, tokens(count)]] : [],
  );

  // An agent that gives only a total still said how many.
  if (counts.length === 0 && spent?.totalTokens !== undefined) {
    counts.push(['Tokens', tokens(spent.totalTokens)]);
  }

  return aligned([
    ['Total cost', cost ?? `not reported by ${facts.agent}`],
    ...running,
    ...(spent === undefined
      ? [['Tokens', `not reported by ${facts.agent}`] as [string, string]]
      : counts),
    ...time,
  ]);
}

/**
 * `/context`: how much of the window is used and how much is free, the used
 * share as the status line draws it, so the two never disagree.
 */
export function contextReport(facts: ReportFacts): ReportRow[] {
  const { context } = facts;

  if (context === undefined || context.size <= 0) {
    return aligned([
      `${facts.agent} has not reported how full its context window is.`,
    ]);
  }

  const used = contextUsed(context);
  const free = Math.max(0, context.size - context.used);
  const note = contextEstimated(context) ? ` ${ESTIMATE_NOTE}` : '';

  return aligned([
    [
      'Used',
      `${tokens(context.used)} of ${tokens(
        context.size,
      )} tokens (${used}%)${note}`,
    ],
    ['Free', `${tokens(free)} tokens (${100 - used}%)${note}`],
  ]);
}

/** `/status`: who and where the session is. */
export function statusReport(facts: ReportFacts): ReportRow[] {
  const mode =
    facts.mode === undefined
      ? undefined
      : (facts.modes.find(({ id }) => id === facts.mode)?.name ?? facts.mode);

  return aligned([
    ['Agent', facts.agent],
    ['Model', modelName(facts.models) ?? `not reported by ${facts.agent}`],
    ['Mode', mode ?? `not reported by ${facts.agent}`],
    ['Session', facts.sessionId ?? 'starting…'],
    ['Directory', facts.cwd],
    // As one session always read, until a second opens.
    ...(facts.sessions === undefined || facts.sessions.open < 2
      ? []
      : [sessionsRow(facts.sessions)]),
  ]);
}

/** `Sessions`' row: how many are open, and how many wait on the person. */
function sessionsRow({
  open,
  waits,
}: {
  readonly open: number;
  readonly waits: number;
}): [string, string] {
  return [
    'Sessions',
    `${open} open${
      waits === 0 ? '' : ` (${waits} ${waits === 1 ? 'waits' : 'wait'})`
    }`,
  ];
}
