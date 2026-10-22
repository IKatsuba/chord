/**
 * What the window's sessions have spent, kept out of `/cost`'s drawing: a
 * figure for each session, its whole life as its record and this window
 * found it turn by turn, and for each task agent, and the sums of them, with
 * what was chord's estimate and what was never reported said rather than
 * guessed (CHD-373, CHD-378's option C, the owner's Q58).
 */
import type { Cost } from '@agentclientprotocol/sdk';
import { isLead, membersOf, type Tab } from '../../session/tabs.ts';
import type { TaskSpent, Transcript } from '../../session/transcript/types.ts';
import {
  type Spent,
  TOKEN_FIELDS,
  type TokenUsage,
} from '../../session/usage.ts';

/** The one currency costs are added up in; any other is not counted. */
const SUMMED = 'USD';

/** How much of a cost is chord's estimate rather than the agent's figure. */
export type Estimated = 'none' | 'part' | 'all';

/** One session's or task's spend: its cost, and its tokens in all. */
export interface Figure {
  readonly cost?: Cost;
  /** None, part or all of the cost is chord's estimate; none when absent. */
  readonly estimated?: Exclude<Estimated, 'none'>;
  readonly tokens?: number;
  /**
   * Turns whose cost could not be told, or came in another currency: left
   * out of the cost, and said to be (the owner's Q61).
   */
  readonly uncounted?: number;
  /**
   * Of the cost, what an older record spent before it kept each turn's, as
   * last reported, and up to when (the owner's Q62).
   */
  readonly before?: { readonly cost: Cost; readonly until?: number };
  /** The models whose prices chord's estimate came from, where it says. */
  readonly models?: readonly string[];
  /**
   * Its figures are the running totals its agent last gave, not turns added
   * up (CHD-472); the model the last came on, where it said.
   */
  readonly totals?: {
    readonly model?: string;
    /**
     * The models chord had no price for, whose turns its estimate left out,
     * in the order they first answered.
     */
    readonly unpriced?: readonly string[];
  };
}

/** A turn's tokens, or a session's, in all: the total, else each kind. */
export function tokensIn(tokens: TokenUsage | undefined): number | undefined {
  if (tokens === undefined) {
    return undefined;
  }

  if (tokens.totalTokens !== undefined) {
    return tokens.totalTokens;
  }

  const each = TOKEN_FIELDS.flatMap((field) =>
    field === 'totalTokens' ? [] : (tokens[field] ?? []),
  );

  return each.length === 0 ? undefined : each.reduce((a, b) => a + b, 0);
}

/** What a session of an agent that gives running totals says of its figures. */
function totalsOf(spent: Spent): NonNullable<Figure['totals']> {
  const unpriced = [
    ...new Set(
      Object.values(spent.costs ?? {}).flatMap((each) =>
        each.uncounted === true && each.model !== undefined ? [each.model] : [],
      ),
    ),
  ];

  return {
    ...(spent.totalModel === undefined ? {} : { model: spent.totalModel }),
    ...(unpriced.length === 0 ? {} : { unpriced }),
  };
}

/** `estimated` of `some` out of `of` costs. */
function share(some: number, of: number): Estimated {
  return some === 0 ? 'none' : some === of ? 'all' : 'part';
}

/**
 * A session's figure, its whole life: its turns' own costs added up, each
 * once by its turn, the record's before it kept them among them, and its
 * turns' tokens; none when it reported neither.
 */
export function sessionFigure(spent: Spent | undefined): Figure | undefined {
  const costs = Object.values(spent?.costs ?? {});
  const added = costs.filter((each) => each.cost?.currency === SUMMED);
  const estimated = share(
    added.filter((each) => each.estimated === true).length,
    added.length,
  );
  const uncounted = costs.length - added.length;
  const before = costs.find((each) => each.before !== undefined);
  const models = [
    ...new Set(
      added.flatMap((each) =>
        each.estimated === true && each.model !== undefined ? [each.model] : [],
      ),
    ),
  ];
  // Each turn's in all first: one that gave a total and one that gave
  // only its kinds each count whole. A running total is the whole session's.
  const each = (
    spent?.total === undefined
      ? Object.values(spent?.turns ?? {})
      : [spent.total]
  ).flatMap((turn) => tokensIn(turn) ?? []);
  const tokens =
    each.length === 0 ? undefined : each.reduce((a, b) => a + b, 0);
  const figure: Figure = {
    ...(added.length === 0
      ? {}
      : {
          cost: {
            amount: added.reduce((sum, each) => sum + each.cost!.amount, 0),
            currency: SUMMED,
          },
        }),
    ...(estimated === 'none' ? {} : { estimated }),
    ...(tokens === undefined ? {} : { tokens }),
    ...(uncounted === 0 ? {} : { uncounted }),
    ...(models.length === 0 ? {} : { models }),
    ...(spent?.total === undefined ? {} : { totals: totalsOf(spent) }),
    ...(before?.cost === undefined
      ? {}
      : {
          before: {
            cost: before.cost,
            ...(before.before?.until === undefined
              ? {}
              : { until: before.before.until }),
          },
        }),
  };

  return Object.keys(figure).length === 0 ? undefined : figure;
}

/** A task agent's figure, from what its block keeps (S1). */
export function taskFigure(spent: TaskSpent | undefined): Figure | undefined {
  if (spent === undefined) {
    return undefined;
  }

  const tokens = tokensIn(spent.tokens);
  const figure: Figure = {
    ...(spent.cost === undefined ? {} : { cost: spent.cost }),
    ...(spent.estimated ? { estimated: 'all' as const } : {}),
    ...(tokens === undefined ? {} : { tokens }),
  };

  return Object.keys(figure).length === 0 ? undefined : figure;
}

/** What a part of the window's spend is, which its row says in words. */
export type SpendKind = 'tab' | 'main' | 'agent' | 'team' | 'member' | 'task';

/**
 * A part of the window's spend: a session or task with its own figure, or
 * a tab or a team run, whose figure is only what is under it.
 */
export interface SpendPart {
  readonly name: string;
  readonly kind: SpendKind;
  /** The agent a tab's own session is, which says what reported nothing. */
  readonly agent?: string;
  /**
   * The agent a long-lived agent or team member runs on, as chord starts it,
   * which its notes name, as `agent` is a tab's own (CHD-472).
   */
  readonly runtime?: string;
  /** Its own figure; none when it reported nothing. */
  readonly figure?: Figure;
  readonly parts?: readonly SpendPart[];
  /** A task still at work, whose figure comes when it ends: not counted yet. */
  readonly running?: true;
  /** A task that has ended, or an agent or tab that has closed. */
  readonly ended?: true;
}

/** A tab or a team run: what is under it is its spend, nothing of its own. */
function grouping(part: SpendPart): boolean {
  return part.kind === 'tab' || part.kind === 'team';
}

/** The figures of a part and those under it, added up. */
export interface Summed {
  /** In USD, the only currency added up; none when no part had a cost. */
  readonly cost?: number;
  /** How much of the cost is chord's estimate. */
  readonly estimated: Estimated;
  readonly tokens?: number;
  /**
   * The parts that reported no cost, or one in another currency: by name, a
   * tab's own session by its agent.
   */
  readonly missing: readonly string[];
  /**
   * The agents, each once, whose running totals came with no cost, as their
   * provider gives none: said apart from `missing` (CHD-472).
   */
  readonly providers?: readonly string[];
  /** Turns left out of the cost of the parts that had one (Q61). */
  readonly uncounted: number;
}

/**
 * `parts` and all under them added up: costs in USD only, a part with no
 * cost, or another currency, named as missing rather than read as zero; a
 * task still at work is not counted until its figure comes.
 */
export function sum(parts: readonly SpendPart[]): Summed {
  let cost: number | undefined;
  let tokens: number | undefined;
  let costed = 0;
  let estimated = 0;
  let partly = false;
  let uncounted = 0;
  const missing: string[] = [];
  const providers = new Set<string>();

  const add = (part: SpendPart) => {
    const own = part.figure;

    if (!grouping(part) && part.running !== true) {
      if (own?.cost !== undefined && own.cost.currency === SUMMED) {
        cost = (cost ?? 0) + own.cost.amount;
        costed += 1;
        estimated += own.estimated === 'all' ? 1 : 0;
        partly ||= own.estimated === 'part';
      } else if (own?.totals !== undefined) {
        providers.add(part.runtime ?? part.agent ?? part.name);
      } else {
        missing.push(part.agent ?? part.name);
      }

      if (own?.tokens !== undefined) {
        tokens = (tokens ?? 0) + own.tokens;
      }

      uncounted += own?.uncounted ?? 0;
    }

    for (const under of part.parts ?? []) {
      add(under);
    }
  };

  for (const part of parts) {
    add(part);
  }

  return {
    ...(cost === undefined ? {} : { cost }),
    estimated: partly && estimated < costed ? 'part' : share(estimated, costed),
    ...(tokens === undefined ? {} : { tokens }),
    missing,
    ...(providers.size === 0 ? {} : { providers: [...providers] }),
    uncounted,
  };
}

/** A session as the window holds it, as much of it as its spend needs. */
export interface SpendSession {
  /** The agent's id for it, once it is up. */
  readonly sessionId?: string | undefined;
  readonly spent?: Spent | undefined;
  readonly transcript: Transcript;
}

/**
 * A closed agent's spend, kept for the window's total (the owner's Q59:
 * closed agents count): the tab it was in, by key, the team lead it worked
 * for, by chord's id, and its part as it was when it closed.
 */
export interface KeptSpend {
  /**
   * The agent's id for its session: a session resumed since counts its
   * whole spend where it is open, and one closed again where it closed last.
   */
  readonly sessionId?: string | undefined;
  readonly tab: number;
  /** The tab's name as it was then, `1 fake`, for a tab that has closed. */
  readonly tabName?: string | undefined;
  /** The lead of the team run it was of, by chord's id, itself for a lead. */
  readonly lead?: string | undefined;
  /** That team's name, for a run whose lead has closed. */
  readonly team?: string | undefined;
  readonly part: SpendPart;
}

/**
 * Kept parts grouped as they were: each closed team run's, whose lead has
 * gone, as one team part; the rest as they are.
 */
function regrouped(
  kept: readonly KeptSpend[],
  open: ReadonlySet<string>,
): SpendPart[] {
  const runs = new Map<string, SpendPart[]>();
  const loose: SpendPart[] = [];
  const names = new Map<string, string>();

  for (const each of kept) {
    if (each.lead === undefined || open.has(each.lead)) {
      loose.push(each.part);
      continue;
    }

    runs.set(each.lead, [...(runs.get(each.lead) ?? []), each.part]);

    if (each.team !== undefined) {
      names.set(each.lead, each.team);
    }
  }

  return [
    ...loose,
    ...[...runs].map(([lead, parts]): SpendPart => ({
      name: names.get(lead) ?? lead,
      kind: 'team',
      ended: true,
      parts,
    })),
  ];
}

/** A session's own part and its task agents'. */
export function sessionParts(
  name: string,
  kind: SpendKind,
  session: SpendSession | undefined,
  agent?: string,
  runtime?: string,
): SpendPart[] {
  const figure = sessionFigure(session?.spent);
  const tasks = (session?.transcript.entries ?? []).flatMap(
    (entry): SpendPart[] => {
      if (entry.kind !== 'subagent' || entry.subagent.task === undefined) {
        return [];
      }

      const { subagent } = entry;
      const own = taskFigure(subagent.task?.spent);
      const running = subagent.state === 'running';

      return [
        {
          name: subagent.task!.name,
          kind: 'task',
          ...(own === undefined ? {} : { figure: own }),
          ...(running ? { running: true as const } : { ended: true as const }),
        },
      ];
    },
  );

  return [
    {
      name,
      kind,
      ...(agent === undefined ? {} : { agent }),
      ...(runtime === undefined ? {} : { runtime }),
      ...(figure === undefined ? {} : { figure }),
    },
    ...tasks,
  ];
}

/**
 * A session's part, a tab's own, a long-lived agent's or a team member's,
 * its task agents under it, as a closed one's is kept.
 */
function ownPart(
  name: string,
  kind: SpendKind,
  session: SpendSession | undefined,
  agent?: string,
  runtime?: string,
): SpendPart {
  const [own, ...tasks] = sessionParts(name, kind, session, agent, runtime);

  return tasks.length === 0 ? own! : { ...own!, parts: tasks };
}

/**
 * The window's spend, tab by tab: each tab's own agent and its task agents,
 * then each long-lived agent, a team run as one part with its lead and
 * members under it; then the agents and tabs closed since the window opened,
 * each under its tab while that is open and its team while that runs.
 */
export function windowSpend<C>(
  tabs: readonly Tab<C>[],
  sessions: Readonly<Record<number, SpendSession | undefined>>,
  everKept: readonly KeptSpend[],
): SpendPart[] {
  const open = new Set(tabs.map((tab) => tab.key));
  const live = new Set(
    Object.values(sessions).flatMap((each) =>
      each?.sessionId === undefined ? [] : [each.sessionId],
    ),
  );
  // Each session once, its whole spend: where it is open, else where it
  // closed last.
  const kept = everKept.filter(
    (each, index) =>
      each.sessionId === undefined ||
      (!live.has(each.sessionId) &&
        !everKept
          .slice(index + 1)
          .some((later) => later.sessionId === each.sessionId)),
  );
  const parts = tabs.map((tab, index): SpendPart => {
    const keptHere = kept.filter((each) => each.tab === tab.key);
    const leads = tab.children.filter(isLead);
    const running = new Set(leads.map((lead) => lead.id));
    const runs = leads.map((lead): SpendPart => ({
      name: lead.team ?? lead.name,
      kind: 'team',
      parts: [
        // Its row is named by the team; its lead is `lead` under it.
        ownPart('lead', 'member', sessions[lead.key], undefined, lead.runtime),
        ...membersOf(tab, lead.id).map((member) =>
          ownPart(
            member.name,
            'member',
            sessions[member.key],
            undefined,
            member.runtime,
          ),
        ),
        ...keptHere
          .filter((each) => each.lead === lead.id)
          .map((each) => each.part),
      ],
    }));
    const agents = tab.children
      .filter((child) => child.team === undefined)
      .map((child) =>
        ownPart(
          child.name,
          'agent',
          sessions[child.key],
          undefined,
          child.runtime,
        ),
      );

    return {
      name: `${index + 1} ${tab.agent}`,
      kind: 'tab',
      parts: [
        ownPart('main', 'main', sessions[tab.key], tab.agent),
        ...agents,
        ...runs,
        // What closed under a team still running is in its part above.
        ...regrouped(
          keptHere.filter(
            (each) => each.lead === undefined || !running.has(each.lead),
          ),
          running,
        ),
      ],
    };
  });

  // Each tab closed since the window opened, with all that closed in it.
  const closed = [
    ...new Set(
      kept.filter((each) => !open.has(each.tab)).map((each) => each.tab),
    ),
  ].map((key): SpendPart => {
    const here = kept.filter((each) => each.tab === key);

    return {
      name:
        here.find((each) => each.tabName !== undefined)?.tabName ??
        'closed tab',
      kind: 'tab',
      ended: true,
      parts: regrouped(here, new Set()),
    };
  });

  return [...parts, ...closed];
}
