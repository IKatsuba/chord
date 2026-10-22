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
import { type Figure, sessionFigure, type SpendPart } from './spend.ts';
import { manySessions, spendTable } from './spend_table.ts';

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
  /**
   * What the whole window has spent, its closed agents and tabs too, and
   * the columns its table is laid out in (CHD-373 S4).
   */
  readonly window?: {
    readonly spend: readonly SpendPart[];
    readonly width: number;
  };
}

/** The facts the window holds, for a report run now. */
export function reportFacts(
  state: AppState,
  agent: string,
  cwd: string,
  now: number,
  sessions?: { readonly open: number; readonly waits: number },
  window?: ReportFacts['window'],
): ReportFacts {
  return {
    ...(sessions === undefined ? {} : { sessions }),
    ...(window === undefined ? {} : { window }),
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
 * The session's tokens, each turn's added up, or the running total its agent
 * last gave (CHD-472). A field no turn reported stays out rather than reading
 * as zero.
 */
export function sessionTokens(
  spent: Spent | undefined,
): TokenUsage | undefined {
  const each =
    spent?.total === undefined
      ? Object.values(spent?.turns ?? {})
      : [spent.total];
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

/** Said after a cost chord worked out only some of. */
export const PART_ESTIMATE_NOTE = "(part chord's estimate)";

/** A day as `Oct 12`, as the row of an older record's sum names it. */
const DAY = new Intl.DateTimeFormat('en-US', {
  month: 'short',
  day: 'numeric',
});

/**
 * `/cost`: the session's whole cost, each of its turns' added up, from
 * before a resume too, and its marks, its tokens in and out, and how long
 * it ran; then, once the window holds more than one session, what the
 * whole window has spent (CHD-373).
 */
export function costReport(facts: ReportFacts): ReportRow[] {
  const own = sessionReport(facts);
  const window = facts.window;

  return window === undefined || !manySessions(window.spend)
    ? own
    : [...own, { text: '' }, ...spendTable(window.spend, window.width)];
}

/** A model by the name its agent gives it, else by its id. */
function modelNamed(facts: ReportFacts, id: string | undefined): string {
  return id === undefined
    ? 'its model'
    : (facts.models?.available.find((model) => model.id === id)?.name ?? id);
}

/**
 * What `/cost` says after the rows of an agent that gives running totals
 * (CHD-472): how its figures were read, and, where it gave no cost and chord
 * priced its tokens, why.
 */
function totalsLines(
  facts: ReportFacts,
  figure: Figure | undefined,
): ReportRow[] {
  if (figure?.totals === undefined) {
    return [];
  }

  const { agent } = facts;
  const [model, ...more] = figure.models ?? [];
  const unpriced = figure.totals.unpriced ?? [];
  // One model: its price. Several, or some unpriced: each answer at its
  // own, as Q133 prices them.
  const one = model !== undefined && more.length === 0 && unpriced.length === 0;
  const price = one
    ? `these tokens at ${modelNamed(facts, model)}'s price`
    : `each answer's tokens at the price of the model that gave it${
        unpriced.length === 0
          ? ''
          : `; it has no price for ${unpriced
              .map((each) => modelNamed(facts, each))
              .join(' and ')}`
      }`;

  return [
    {
      text: `${agent} reports these as the session's running total; chord shows the last it sent.`,
    },
    ...(figure.estimated === 'all'
      ? [
          {
            text: `${agent}'s provider reports no cost, so chord priced ${price}.`,
          },
        ]
      : []),
  ];
}

/** The session's own rows of `/cost`. */
function sessionReport(facts: ReportFacts): ReportRow[] {
  const spent = sessionTokens(facts.spent);
  const figure = sessionFigure(facts.spent);
  // An agent that gives running totals and no cost, whose model chord has no
  // price for: both reasons, in the cost's cell (CHD-472).
  const unpriced =
    figure?.totals !== undefined && figure.cost === undefined
      ? `not reported: ${facts.agent}'s provider reports none, and chord has no price for ${(figure.totals.unpriced ?? [figure.totals.model ?? facts.models?.current]).map((each) => modelNamed(facts, each)).join(' and ')}`
      : undefined;
  const cost =
    figure?.cost === undefined
      ? undefined
      : figure.estimated === 'all'
        ? `${formatCost(figure.cost)} ${ESTIMATE_NOTE}`
        : figure.estimated === 'part'
          ? `${formatCost(figure.cost)} ${PART_ESTIMATE_NOTE}`
          : formatCost(figure.cost);
  // An older record's sum, and turns left out, each a row of its own.
  const marks: [string, string][] = [
    ...(figure?.before === undefined
      ? []
      : [
          [
            figure.before.until === undefined
              ? 'Before'
              : `Before ${DAY.format(figure.before.until)}`,
            `${formatCost(figure.before.cost)} as last reported`,
          ] as [string, string],
        ]),
    // Turns no model's price counted, on an agent that gives running totals
    // and no cost at all, are said in the cost's cell instead (CHD-472).
    ...(figure?.uncounted === undefined || unpriced !== undefined
      ? []
      : [
          [
            'Not counted',
            `${figure.uncounted} ${figure.uncounted === 1 ? 'turn' : 'turns'}`,
          ] as [string, string],
        ]),
  ];
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

  // Nothing to say, but a turn left out or an older sum still is said.
  if (spent === undefined && cost === undefined && marks.length === 0) {
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

  return [
    ...aligned([
      ['Total cost', unpriced ?? cost ?? `not reported by ${facts.agent}`],
      ...marks,
      ...running,
      ...(spent === undefined
        ? [['Tokens', `not reported by ${facts.agent}`] as [string, string]]
        : counts),
      ...time,
    ]),
    ...totalsLines(facts, figure),
  ];
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
