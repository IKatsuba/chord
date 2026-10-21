/**
 * The background of a tab, kept out of the components: every monitor and
 * `spawn_task` task its agents run, and every subagent of theirs that can be
 * stopped alone (CHD-2), as items in start order, and the
 * summary line under the agents list that counts them by state, wrapped
 * between its groups and never cut (CHD-424).
 */
import stringWidth from 'string-width';
import type { EndedMonitor, RunningMonitor } from '../../session/monitors.ts';
import type {
  Entry,
  MonitorEnd,
  Subagent,
  TaskSpent,
  Transcript,
} from '../../session/transcript/types.ts';
import { GLYPHS } from '../app/strip.ts';
import { agentGroup } from '../transcript/agents/subagents.ts';
import { agentTarget, callTarget } from '../transcript/targets.ts';

/**
 * What an item is, in the order the summary line names them; an agent's own
 * background `bash` waits on the adapters offering it without AIR (CHD-2).
 */
export const KINDS = ['monitor', 'task', 'agent'] as const;

export type BackgroundKind = (typeof KINDS)[number];

const KIND_WORDS: Record<BackgroundKind, readonly [string, string]> = {
  monitor: ['monitor', 'monitors'],
  task: ['task', 'tasks'],
  agent: ['agent', 'agents'],
};

/** Where an item stands, as the summary line groups them, most urgent first. */
export const GROUPS = [
  'asking',
  'failed',
  'untracked',
  'running',
  'done',
  'stopped',
] as const;

export type BackgroundGroup = (typeof GROUPS)[number];

/** An item's state: at work, asking the person, or ended and how. */
export type ItemStatus =
  | {
      readonly group: 'running';
      /** An agent the person stopped, until its agent says it ended. */
      readonly stopping?: true;
    }
  | {
      readonly group: 'asking';
      /**
       * What it asks for: a permission or a form chord holds, or, for an
       * agent, nothing of its that reaches the person.
       */
      readonly on: 'permission' | 'input' | 'waiting';
      /** When it asked, epoch milliseconds. */
      readonly since: number;
    }
  | {
      /**
       * Ended, or, `untracked`, an agent its agent lost sight of, which a
       * later state takes back.
       */
      readonly group: 'failed' | 'done' | 'stopped' | 'untracked';
      /** When it ended, epoch milliseconds, which its time stands still at. */
      readonly endedAt: number;
      /** A monitor's end, which its row words. */
      readonly end?: MonitorEnd;
      /**
       * An agent's end that its group does not word: no cause seen, or its
       * agent gone.
       */
      readonly word?: 'ended' | 'disconnected';
    };

/** Whose an item is: a child's or member's name and colour; none for `main`. */
export interface ItemOwner {
  readonly name: string;
  readonly colour: number;
}

/** One monitor or task of the tab's agents. */
export interface BackgroundItem {
  readonly kind: BackgroundKind;
  /** Its id in its owner's session: a monitor's `m1`, a task's own. */
  readonly id: string;
  /** Its owner's session key. */
  readonly key: number;
  readonly owner?: ItemOwner;
  /** A monitor's description, a task's title. */
  readonly name: string;
  /** When it started, epoch milliseconds. */
  readonly startedAt: number;
  readonly status: ItemStatus;
  /** A monitor's batches handed on so far. */
  readonly events?: number;
  /** A task's runtime and model, as the agents list names an agent's. */
  readonly runtime?: string;
  readonly model?: string;
  /** What a task spent, once it has ended (CHD-373). */
  readonly spent?: TaskSpent;
  /** A task's `spawn_task` call, which `enter` scrolls to. */
  readonly callId?: string;
  /** An agent's own stop: its agent still offers one. */
  readonly stoppable?: boolean;
  /**
   * An agent item's: the listed agent whose transcript announced it, by the
   * name the agents list gives it, `main` or a child's (CHD-479).
   */
  readonly parent?: string;
  /** Its parent's place in the agents list, which orders the parents. */
  readonly parentAt?: number;
}

/** One agent of the tab, as its items are read from its session. */
export interface BackgroundAgent {
  readonly key: number;
  readonly owner?: ItemOwner;
  /** When its session came up; a task from before is its past, not an item. */
  readonly since?: number | undefined;
  readonly monitors: readonly RunningMonitor[];
  readonly endedMonitors: readonly EndedMonitor[];
  readonly transcript: Transcript;
  /** Its agent items the person stopped, by id, that have not ended yet. */
  readonly stopping?: ReadonlySet<string>;
}

/**
 * The tab's items, oldest first, each keeping its place as it changes: the
 * running, asking and untracked ones, and those ended after `clearedAt`,
 * the person's last prompt in the tab, of a kind that stays once ended. Two that started in the same millisecond keep the order of
 * their agents, then of each agent's monitors by id and tasks as its
 * transcript has them, which no change of state moves.
 */
export function backgroundItems(
  agents: readonly BackgroundAgent[],
  clearedAt = -Infinity,
): BackgroundItem[] {
  return agents
    .flatMap((agent, at) => [
      ...monitorItems(agent),
      ...taskItems(agent),
      ...agentItems(agent, at),
    ])
    .filter(
      (item) =>
        !leavesList(item) &&
        // Untracked has not ended, so no prompt clears it (Q110).
        (item.status.group === 'running' ||
          item.status.group === 'asking' ||
          item.status.group === 'untracked' ||
          item.status.endedAt > clearedAt),
    )
    .sort((a, b) => a.startedAt - b.startedAt);
}

function monitorItems(agent: BackgroundAgent): BackgroundItem[] {
  const base = (monitor: RunningMonitor) => ({
    kind: 'monitor' as const,
    id: monitor.id,
    key: agent.key,
    ...(agent.owner === undefined ? {} : { owner: agent.owner }),
    name: monitor.description,
    startedAt: monitor.startedAt,
    events: monitor.events,
  });

  // In id order, which is start order, so two started in the same
  // millisecond keep their places whichever ends first.
  return [
    ...agent.endedMonitors.map((monitor): BackgroundItem => ({
      ...base(monitor),
      status: {
        group: monitorGroup(monitor.end),
        endedAt: monitor.endedAt,
        end: monitor.end,
      },
    })),
    ...agent.monitors.map((monitor): BackgroundItem => ({
      ...base(monitor),
      status: { group: 'running' },
    })),
  ].sort((a, b) => monitorNumber(a.id) - monitorNumber(b.id));
}

/** `m12`'s 12. */
function monitorNumber(id: string): number {
  return Number(id.slice(1)) || 0;
}

/** A monitor's end as a group: exit 0 is done, a stop stopped, else failed. */
function monitorGroup(end: MonitorEnd): 'failed' | 'done' | 'stopped' {
  return end.kind === 'stopped'
    ? 'stopped'
    : end.kind === 'exit' && end.code === 0
      ? 'done'
      : 'failed';
}

function taskItems(agent: BackgroundAgent): BackgroundItem[] {
  const { since, transcript } = agent;

  if (since === undefined) {
    return [];
  }

  return tasksIn(transcript.entries).flatMap(
    ({ subagent, task }): BackgroundItem[] => {
      const startedAt = subagent.startedAt;

      if (startedAt === undefined || startedAt < since) {
        return [];
      }

      return [
        {
          kind: 'task',
          id: subagent.id,
          key: agent.key,
          ...(agent.owner === undefined ? {} : { owner: agent.owner }),
          name: task.name,
          startedAt,
          status: taskStatus(subagent, startedAt, transcript),
          runtime: task.runtime,
          ...(task.model === undefined ? {} : { model: task.model }),
          ...(task.spent === undefined ? {} : { spent: task.spent }),
          ...(subagent.callId === undefined ? {} : { callId: subagent.callId }),
        },
      ];
    },
  );
}

/** Every task agent among `entries`, a subagent's own included. */
function tasksIn(
  entries: readonly Entry[],
): { subagent: Subagent; task: NonNullable<Subagent['task']> }[] {
  return entries.flatMap((entry) => {
    if (entry.kind !== 'subagent') {
      return [];
    }

    const { subagent } = entry;
    const inner = tasksIn(subagent.entries);

    return subagent.task === undefined
      ? inner
      : [{ subagent, task: subagent.task }, ...inner];
  });
}

function taskStatus(
  subagent: Subagent,
  startedAt: number,
  transcript: Transcript,
): ItemStatus {
  const endedAt = subagent.endedAt ?? startedAt;

  switch (subagent.state) {
    case 'running':
      return taskAsking(subagent.id, transcript) ?? { group: 'running' };
    case 'completed':
      return { group: 'done', endedAt };
    case 'cancelled':
      return { group: 'stopped', endedAt };
    case 'failed':
    case 'disconnected':
      return { group: 'failed', endedAt };
    // chord's own tasks never end so: only an adapter's subagents do.
    case 'ended':
    case 'untracked':
      return { group: 'stopped', endedAt };
  }
}

/** The request of task `id` the person has had longest, if one is open. */
function taskAsking(
  id: string,
  { turn, asking }: Transcript,
): ItemStatus | undefined {
  const since = turn.status === 'awaiting_permission' ? turn.since : 0;
  const asked = [
    ...(turn.status === 'awaiting_permission' ? turn.permissions : [])
      .filter((wait) => wait.subagentId === id)
      .map((wait) => ({
        on: 'permission' as const,
        since: wait.at ?? since,
      })),
    ...asking
      .filter((wait) => wait.subagentId === id)
      .map((wait) => ({ on: 'input' as const, since: wait.at ?? 0 })),
  ].sort((a, b) => a.since - b.since)[0];

  return asked && { group: 'asking', ...asked };
}

/**
 * Whether a subagent is an `agent` item: one announced with
 * `capabilities.cancel`, which can be stopped alone. The rule is open with
 * the owner (Q40), so it is here alone.
 */
export function isAgentItem(subagent: Subagent): boolean {
  return subagent.task === undefined && subagent.offeredCancel === true;
}

/**
 * The groups each kind's items leave the list in, at once, as they end (the
 * owner's Q83 and Q86, docs/design/CHD-479.md): an `agent` once done,
 * failed or stopped, and a monitor, whose end its agent's transcript says
 * already (CHD-266). `untracked`, which a later state takes back, is not
 * ended and stays (Q110).
 */
const LEAVES: Record<BackgroundKind, ReadonlySet<ItemStatus['group']>> = {
  monitor: new Set(['done', 'failed', 'stopped']),
  task: new Set(),
  agent: new Set(['done', 'failed', 'stopped']),
};

/** Whether `item` has ended in a way that takes it off the list. */
export function leavesList(
  item: Pick<BackgroundItem, 'kind' | 'status'>,
): boolean {
  return LEAVES[item.kind].has(item.status.group);
}

/** The name the agents list gives the tab's own agent. */
const MAIN_NAME = 'main';

/**
 * The subagents of an agent's that are items, a subagent's own included,
 * started since its session came up. One that lost its cancel since stays an
 * item, with no stop.
 */
function agentItems(agent: BackgroundAgent, at: number): BackgroundItem[] {
  const { since, transcript } = agent;

  if (since === undefined) {
    return [];
  }

  return agentsIn(transcript.entries).flatMap((subagent): BackgroundItem[] => {
    const { startedAt } = subagent;

    if (startedAt === undefined || startedAt < since) {
      return [];
    }

    return [
      {
        kind: 'agent',
        id: subagent.id,
        key: agent.key,
        ...(agent.owner === undefined ? {} : { owner: agent.owner }),
        name: subagent.description ?? subagent.title ?? 'agent',
        startedAt,
        status: agentStatus(
          subagent,
          startedAt,
          transcript,
          agent.stopping?.has(subagent.id) === true,
        ),
        stoppable: subagent.cancellable === true,
        parent: agent.owner?.name ?? MAIN_NAME,
        parentAt: at,
      },
    ];
  });
}

/** The ids of the agent items among `entries` the person stopped. */
export function stoppingIn(entries: readonly Entry[]): ReadonlySet<string> {
  return new Set(
    agentsIn(entries)
      .filter((subagent) => subagent.stopping === true)
      .map((subagent) => subagent.id),
  );
}

/** Every agent item among `entries`, a subagent's own included. */
function agentsIn(entries: readonly Entry[]): Subagent[] {
  return entries.flatMap((entry) => {
    if (entry.kind !== 'subagent') {
      return [];
    }

    const { subagent } = entry;
    const inner = agentsIn(subagent.entries);

    return isAgentItem(subagent) ? [subagent, ...inner] : inner;
  });
}

/** An agent item's state, as CHD-2's table says it. */
function agentStatus(
  subagent: Subagent,
  startedAt: number,
  transcript: Transcript,
  stopping: boolean,
): ItemStatus {
  const endedAt = subagent.endedAt ?? startedAt;

  switch (subagent.state) {
    case 'running': {
      // Stopped by the person, it reads so while its request stays up.
      if (stopping) {
        return { group: 'running', stopping: true };
      }

      const asked = taskAsking(subagent.id, transcript);

      if (asked !== undefined) {
        return asked;
      }

      if (subagent.waiting !== undefined) {
        return {
          group: 'asking',
          on: 'waiting',
          since: subagent.waiting.since ?? startedAt,
        };
      }

      return { group: 'running' };
    }
    case 'completed':
      return { group: 'done', endedAt };
    case 'failed':
      return { group: 'failed', endedAt };
    case 'disconnected':
      return { group: 'failed', endedAt, word: 'disconnected' };
    case 'cancelled':
      return { group: 'stopped', endedAt };
    case 'ended':
      return { group: 'stopped', endedAt, word: 'ended' };
    case 'untracked':
      return { group: 'untracked', endedAt };
  }
}

/** One state's group on the summary line: its words, with its glyph. */
export interface SummaryGroup {
  readonly group: BackgroundGroup;
  /** `● 1 task asking`, `2 monitors and 1 task running`. */
  readonly text: string;
}

const GROUP_GLYPHS: Record<BackgroundGroup, string | undefined> = {
  asking: GLYPHS.asking,
  failed: GLYPHS.failed,
  untracked: '?',
  running: undefined,
  done: GLYPHS.replied,
  stopped: '■',
};

/**
 * The summary line's groups, most urgent first, an empty one left out; in
 * each, its kinds in their order joined by `and`, each counted.
 */
export function summaryGroups(
  items: readonly BackgroundItem[],
): SummaryGroup[] {
  return GROUPS.flatMap((group) => {
    const counted = KINDS.flatMap((kind) => {
      const of = items.filter(
        (item) => item.kind === kind && item.status.group === group,
      );

      if (of.length === 0) {
        return [];
      }

      return kind === 'agent'
        ? agentPhrases(of)
        : [`${of.length} ${KIND_WORDS[kind][of.length === 1 ? 0 : 1]}`];
    });

    const glyph = GROUP_GLYPHS[group];

    return counted.length === 0
      ? []
      : [
          {
            group,
            text: `${glyph === undefined ? '' : `${glyph} `}${counted.join(
              ' and ',
            )} ${group}`,
          },
        ];
  });
}

/**
 * A group's agent items by their parent, in the agents list's order (`main`
 * first, then the rows under it): `main's agent`, `main's 2 agents`
 * (docs/design/CHD-479.md).
 */
function agentPhrases(agents: readonly BackgroundItem[]): string[] {
  const parents = new Map<string, { at: number; count: number }>();

  for (const { parent = MAIN_NAME, parentAt = 0 } of agents) {
    parents.set(parent, {
      at: parentAt,
      count: (parents.get(parent)?.count ?? 0) + 1,
    });
  }

  return [...parents]
    .sort(([, a], [, b]) => a.at - b.at)
    .map(([parent, { count }]) =>
      count === 1 ? `${parent}'s agent` : `${parent}'s ${count} agents`,
    );
}

/** The word the summary line opens with. */
export const SUMMARY_LABEL = 'background';

/** What the label and its two spaces take; a wrapped line starts past it. */
export const SUMMARY_INDENT = stringWidth(SUMMARY_LABEL) + 2;

/** A run of the summary line in one colour: the label, a group's, or dim. */
export interface SummaryPiece {
  readonly text: string;
  readonly tone: 'label' | 'plain' | BackgroundGroup;
}

/**
 * The summary line in `width` cells: `background`, then the groups joined
 * by ` · `, breaking between groups, a wrapped line starting under the
 * first group. A group longer than a line alone breaks between its words.
 */
export function summaryLines(
  groups: readonly SummaryGroup[],
  width: number,
): SummaryPiece[][] {
  const lines: SummaryPiece[][] = [
    [
      { text: SUMMARY_LABEL, tone: 'label' },
      { text: '  ', tone: 'plain' },
    ],
  ];
  let used = SUMMARY_INDENT;
  // Whether the line has a group on it yet, which the next one follows.
  let started = false;
  const newLine = () => {
    lines.push([{ text: ' '.repeat(SUMMARY_INDENT), tone: 'plain' }]);

    used = SUMMARY_INDENT;
    started = false;
  };

  const put = (piece: SummaryPiece) => {
    lines[lines.length - 1]!.push(piece);

    used += stringWidth(piece.text);
  };

  groups.forEach(({ group, text }, index) => {
    const sep = index < groups.length - 1 ? ' ·' : '';
    const size = stringWidth(text + sep);

    if (started && used + 1 + size > width) {
      newLine();
    }

    if (started) {
      put({ text: ' ', tone: 'plain' });
    }

    if (used + size <= width) {
      put({ text, tone: group });
    } else {
      // Alone and still too long: word by word, the separator kept with the
      // last word so it never starts a line.
      const words = text.split(' ');

      words.forEach((word, at) => {
        const tail = at === words.length - 1 ? sep : '';
        const room = stringWidth(word + tail);
        const first = used === SUMMARY_INDENT;

        if (!first && used + 1 + room > width) {
          newLine();
        } else if (!first) {
          put({ text: ' ', tone: group });
        }

        put({ text: word, tone: group });
      });
    }

    if (sep !== '') {
      put({ text: sep, tone: 'plain' });
    }

    started = true;
  });

  return lines;
}

/** Where the call that started an item is drawn in its owner's transcript. */
export interface CallPlace {
  /**
   * The entry that draws it: its own, the group of tasks that draws it, or
   * the subagent whose work holds it.
   */
  readonly entry: number;
  /**
   * The id of the call's own box inside that entry (`targets.ts`), drawn
   * there unless a folded subagent's work holds it.
   */
  readonly target: string;
}

/**
 * Where the call that started `item` is drawn: a monitor's `Monitor(…)`, by
 * the id its answer gave, or a task's `Agent(…)`, which stands where its
 * `spawn_task` call was; none once the call is gone.
 */
export function callPlace(
  entries: readonly Entry[],
  item: BackgroundItem,
): CallPlace | undefined {
  const own = (entry: Entry): string | undefined =>
    item.kind === 'monitor'
      ? entry.kind === 'tool' &&
        entry.call.chord?.tool === 'monitor' &&
        isRecord(entry.call.chord.answer) &&
        entry.call.chord.answer.id === item.id
        ? callTarget(entry.call.id)
        : undefined
      : entry.kind === 'subagent' && entry.subagent.id === item.id
        ? agentTarget(item.id)
        : undefined;
  const find = (entry: Entry): string | undefined =>
    own(entry) ??
    (entry.kind === 'subagent'
      ? entry.subagent.entries.map(find).find((found) => found !== undefined)
      : undefined);

  for (const [index, entry] of entries.entries()) {
    const target = find(entry);

    if (target !== undefined) {
      let at = index;

      // A group of tasks is drawn by its first.
      while (agentGroup(entries, at)?.length === 0) {
        at -= 1;
      }

      return { entry: at, target };
    }
  }

  return undefined;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null;
}
