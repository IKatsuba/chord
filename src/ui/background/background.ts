/**
 * The background of a tab, kept out of the components: every monitor and
 * `spawn_task` task its agents run, as items in start order, and the
 * summary line under the agents list that counts them by state, wrapped
 * between its groups and never cut (CHD-424).
 */
import stringWidth from 'string-width';
import type { EndedMonitor, RunningMonitor } from '../../session/monitors.ts';
import type {
  Entry,
  MonitorEnd,
  Subagent,
  Transcript,
} from '../../session/transcript/types.ts';
import { GLYPHS } from '../app/strip.ts';
import { agentGroup } from '../transcript/agents/subagents.ts';

/**
 * What an item is, in the order the summary line names them; CHD-2 adds an
 * agent's own background `bash` and `agent` after them.
 */
export const KINDS = ['monitor', 'task'] as const;

export type BackgroundKind = (typeof KINDS)[number];

const KIND_WORDS: Record<BackgroundKind, readonly [string, string]> = {
  monitor: ['monitor', 'monitors'],
  task: ['task', 'tasks'],
};

/** Where an item stands, as the summary line groups them, most urgent first. */
export const GROUPS = [
  'asking',
  'failed',
  'running',
  'done',
  'stopped',
] as const;

export type BackgroundGroup = (typeof GROUPS)[number];

/** An item's state: at work, asking the person, or ended and how. */
export type ItemStatus =
  | { readonly group: 'running' }
  | {
      readonly group: 'asking';
      readonly on: 'permission' | 'input';
      /** When it asked, epoch milliseconds. */
      readonly since: number;
    }
  | {
      readonly group: 'failed' | 'done' | 'stopped';
      /** When it ended, epoch milliseconds, which its time stands still at. */
      readonly endedAt: number;
      /** A monitor's end, which its row words. */
      readonly end?: MonitorEnd;
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
  /** A task's `spawn_task` call, which `enter` scrolls to. */
  readonly callId?: string;
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
}

/**
 * The tab's items, oldest first, each keeping its place as it changes: the
 * running ones, and those ended after `clearedAt`, the person's last prompt
 * in the tab. Two that started in the same millisecond keep the order of
 * their agents, then of each agent's monitors by id and tasks as its
 * transcript has them, which no change of state moves.
 */
export function backgroundItems(
  agents: readonly BackgroundAgent[],
  clearedAt = -Infinity,
): BackgroundItem[] {
  return agents
    .flatMap((agent) => [...monitorItems(agent), ...taskItems(agent)])
    .filter(
      ({ status }) =>
        status.group === 'running' ||
        status.group === 'asking' ||
        status.endedAt > clearedAt,
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

/** One state's group on the summary line: its words, with its glyph. */
export interface SummaryGroup {
  readonly group: BackgroundGroup;
  /** `● 1 task asking`, `2 monitors and 1 task running`. */
  readonly text: string;
}

const GROUP_GLYPHS: Record<BackgroundGroup, string | undefined> = {
  asking: GLYPHS.asking,
  failed: GLYPHS.failed,
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
      const count = items.filter(
        (item) => item.kind === kind && item.status.group === group,
      ).length;

      return count === 0
        ? []
        : [`${count} ${KIND_WORDS[kind][count === 1 ? 0 : 1]}`];
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

/**
 * The entry of its owner's transcript that draws the call that started
 * `item`: a monitor's `Monitor(…)`, by the id its answer gave, or a task's
 * `Agent(…)`, which stands where its `spawn_task` call was, or the group
 * of tasks that draws it; none once the call is gone. A call inside a
 * subagent's work is drawn by the subagent's entry.
 */
export function callEntry(
  entries: readonly Entry[],
  item: BackgroundItem,
): number | undefined {
  const own = (entry: Entry): boolean =>
    item.kind === 'monitor'
      ? entry.kind === 'tool' &&
        entry.call.chord?.tool === 'monitor' &&
        isRecord(entry.call.chord.answer) &&
        entry.call.chord.answer.id === item.id
      : entry.kind === 'subagent' && entry.subagent.id === item.id;
  const holds = (entry: Entry): boolean =>
    own(entry) ||
    (entry.kind === 'subagent' && entry.subagent.entries.some(holds));
  let at = entries.findIndex(holds);

  if (at === -1) {
    return undefined;
  }

  // A group of tasks is drawn by its first.
  while (agentGroup(entries, at)?.length === 0) {
    at -= 1;
  }

  return at;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null;
}
