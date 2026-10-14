/**
 * What a subagent reads as in its parent's transcript, kept out of the
 * component: a block shaped like a tool call, `Agent(<title>)`, with the
 * latest few calls of its work under `⎿` while it runs and how it ended once
 * it has; subagents spawned back to back as one `Running N agents…` tree; the
 * row a child's permission prompt opens with; and the status line's words for
 * subagents that outlive their turn.
 */
import stringWidth from 'string-width';
import type { PlanEntry } from '@agentclientprotocol/sdk';
import type {
  Entry,
  PermissionWait,
  Subagent,
  SubagentState,
} from '../../../session/transcript/types.ts';
import { formatElapsed } from '../../../session/elapsed.ts';
import { type ArrowTone, outArrow } from '../message.ts';
import {
  type Headline,
  headline,
  SUMMARY_LINES,
  type Tone,
  toneOf,
} from '../tools/tools.ts';

/**
 * The subagents drawn together from `entries[index]` on: every subagent from
 * there up to the first entry that is not one, as nothing from the parent
 * came between their spawns. Empty for a subagent that a group starting
 * further up already holds, which draws nothing of its own; undefined for an
 * entry that is not a subagent.
 */
export function agentGroup(
  entries: readonly Entry[],
  index: number,
): readonly Subagent[] | undefined {
  const first = entries[index];

  if (first?.kind !== 'subagent') {
    return undefined;
  }

  // Task agents and the runtime's own subagents never share a group: they
  // come from different places.
  const task = first.subagent.task !== undefined;
  const sameKind = (entry: Entry | undefined) =>
    entry?.kind === 'subagent' && (entry.subagent.task !== undefined) === task;

  if (sameKind(entries[index - 1])) {
    return [];
  }

  const group: Subagent[] = [];

  for (let at = index; at < entries.length; at++) {
    const entry = entries[at]!;

    if (entry.kind !== 'subagent' || !sameKind(entry)) {
      break;
    }

    group.push(entry.subagent);
  }

  return group;
}

/**
 * One block of a subagent's work as ctrl+o draws it: an entry of its own, a
 * group of its subagents, or its plan, at the place it first came.
 */
export type WorkItem =
  | { readonly kind: 'entry'; readonly entry: Entry }
  | { readonly kind: 'agents'; readonly agents: readonly Subagent[] }
  | { readonly kind: 'plan'; readonly entries: readonly PlanEntry[] };

/** `subagent`'s work in order, its plan drawn once where it first came. */
export function workOf(subagent: Subagent): WorkItem[] {
  const { entries, plan, planAt } = subagent;

  if (plan.length === 0 || planAt === undefined) {
    return grouped(entries);
  }

  // The plan came between the entries either side of planAt, so subagents
  // spawned on both sides of it are two groups, not one.
  return [
    ...grouped(entries.slice(0, planAt)),
    { kind: 'plan', entries: plan },
    ...grouped(entries.slice(planAt)),
  ];
}

function grouped(entries: readonly Entry[]): WorkItem[] {
  return entries.flatMap((entry, index): WorkItem[] => {
    const group = agentGroup(entries, index);

    return group === undefined
      ? [{ kind: 'entry', entry }]
      : group.length === 0
        ? []
        : [{ kind: 'agents', agents: group }];
  });
}

/**
 * `Agent(<title>)`: the headline a subagent reads as, wherever it is named;
 * a task agent's says its runtime, model and effort after, dim, the one
 * thing that tells it apart. `full` false leaves the model and effort out.
 */
export function agentHeadline(subagent: Subagent, full = true): Headline {
  const title = subagent.title?.trim();
  const head: Headline = title
    ? { name: 'Agent', arg: title }
    : { name: 'Agent' };
  const { task } = subagent;

  if (task === undefined) {
    return head;
  }

  const parts = [
    task.runtime,
    ...(full && task.model ? [task.model] : []),
    ...(full && task.effort ? [task.effort] : []),
  ];

  return { ...head, note: ` · ${parts.join(' · ')}` };
}

/**
 * A block's headline in `width` cells: a task's model and effort go first,
 * then its title is cut, its brackets kept; the runtime is never dropped.
 */
export function blockHeadline(subagent: Subagent, width: number): Headline {
  const whole = agentHeadline(subagent);

  if (headlineWidth(whole) <= width) {
    return whole;
  }

  const short = agentHeadline(subagent, false);
  const room = width - headlineWidth(short);

  return room >= 0 || short.arg === undefined
    ? short
    : {
        ...short,
        arg: cutEnd(short.arg, Math.max(stringWidth(short.arg) + room, 1)),
      };
}

/**
 * The tools a subagent used: its tool calls and the subagents it started,
 * each of which counts as one.
 */
export function toolUses(subagent: Subagent): number {
  return subagent.entries.filter(
    (entry) => entry.kind === 'tool' || entry.kind === 'subagent',
  ).length;
}

/**
 * What a subagent did and how long it took, as its ending says them; a task
 * whose work was lost with its record says only how long.
 */
function countsOf(subagent: Subagent): string {
  return [
    subagent.task?.workLost ? undefined : uses(toolUses(subagent)),
    ranFor(subagent),
  ]
    .filter((part) => part !== undefined)
    .join(' · ');
}

function uses(count: number): string {
  return `${count} ${count === 1 ? 'tool use' : 'tool uses'}`;
}

/** How long it ran, from its spawn to its ending, once both were timed. */
export function ranFor(subagent: Subagent): string | undefined {
  const { startedAt, endedAt } = subagent;

  return startedAt === undefined || endedAt === undefined
    ? undefined
    : formatElapsed(endedAt - startedAt);
}

/** The block's marker: as a call's while it runs, then as it ended. */
export function agentTone(state: SubagentState): Tone {
  switch (state) {
    case 'running':
      return 'running';
    case 'completed':
      return 'done';
    case 'failed':
    case 'disconnected':
      return 'failed';
    // Dim, as the person stopped it.
    case 'cancelled':
      return 'pending';
  }
}

/** A word for how it ended, so its colour is never the only signal. */
export interface Ending {
  readonly word: 'Done' | 'Failed' | 'Cancelled' | 'Disconnected';
  readonly failed: boolean;
}

export function endingOf(state: SubagentState): Ending | undefined {
  switch (state) {
    case 'running':
      return undefined;
    case 'completed':
      return { word: 'Done', failed: false };
    case 'failed':
      return { word: 'Failed', failed: true };
    case 'cancelled':
      return { word: 'Cancelled', failed: false };
    case 'disconnected':
      return { word: 'Disconnected', failed: true };
  }
}

/** Said after the call a permission request on screen is about. */
export const WAITING_NOTE = ' · waiting for permission';

/**
 * Where an open task's work would be once its record has gone, so an empty
 * block never reads as a task that did nothing.
 */
export const WORK_LOST_NOTE =
  "Its work was not kept: the task's record is gone.";

/** One line of a subagent's work: a call it made, or a subagent it started. */
export interface WorkLine {
  readonly headline: Headline;
  readonly failed: boolean;
  /**
   * A message sent: how its `→` is drawn, by the rules of the row it opens to,
   * which carries the failure in place of the whole line.
   */
  readonly arrow?: ArrowTone;
  /** A permission request for it is on screen now. */
  readonly waiting: boolean;
}

function workLines(
  subagent: Subagent,
  waits: readonly PermissionWait[],
): WorkLine[] {
  return subagent.entries.flatMap((entry): WorkLine[] => {
    switch (entry.kind) {
      case 'tool': {
        const line = headline(entry.call);
        // chord's refusal fails a call its adapter reported completed.
        const tone = toneOf(entry.call);

        return [
          {
            headline: line,
            failed: !line.sent && tone === 'failed',
            ...(line.sent && { arrow: outArrow(tone) }),
            waiting: waits.some(
              (wait) =>
                wait.subagentId === subagent.id &&
                wait.toolCallId === entry.call.id,
            ),
          },
        ];
      }
      case 'subagent':
        return [
          {
            headline: agentHeadline(entry.subagent),
            failed: endingOf(entry.subagent.state)?.failed ?? false,
            waiting: false,
          },
        ];
      default:
        return [];
    }
  });
}

/** What hangs under a single block's `⎿`, folded. */
export type BlockFold =
  /** Running: its latest calls, oldest first, and how many came before. */
  | {
      readonly kind: 'work';
      readonly lines: readonly WorkLine[];
      readonly more: number;
    }
  /** Running, with no call made yet. */
  | { readonly kind: 'starting' }
  /** Ended: `Done (6 tool uses · 41s)`. */
  | { readonly kind: 'ended'; readonly text: string; readonly failed: boolean };

/**
 * A lone subagent's block folded: while it runs, the headlines of its latest
 * three calls, as many as a call's output shows before it folds; once it has
 * ended, one line of how, with what it did and how long it took. Its
 * messages and thoughts are left to ctrl+o, so they never read as its
 * parent's.
 */
export function blockFold(
  subagent: Subagent,
  waits: readonly PermissionWait[],
): BlockFold {
  const ending = endingOf(subagent.state);

  if (ending !== undefined) {
    const said = countsOf(subagent);

    return {
      kind: 'ended',
      text: said === '' ? ending.word : `${ending.word} (${said})`,
      failed: ending.failed,
    };
  }

  const lines = workLines(subagent, waits);

  return lines.length === 0
    ? { kind: 'starting' }
    : {
        kind: 'work',
        lines: lines.slice(-SUMMARY_LINES),
        more: Math.max(lines.length - SUMMARY_LINES, 0),
      };
}

/** The ending a block's last line says in ctrl+o's view, or none yet. */
export function endedLine(
  subagent: Subagent,
): { readonly text: string; readonly failed: boolean } | undefined {
  const fold = blockFold(subagent, []);

  return fold.kind === 'ended' ? fold : undefined;
}

/**
 * The group's first row and its marker: running while any child runs, then
 * finished when all are done, or ended with what went wrong, worst first.
 */
export function groupHeader(agents: readonly Subagent[]): {
  readonly text: string;
  readonly tone: Tone;
} {
  const count = agents.length;

  if (agents.some((agent) => agent.state === 'running')) {
    return { text: `Running ${count} agents…`, tone: 'running' };
  }

  if (agents.every((agent) => agent.state === 'completed')) {
    return { text: `${count} agents finished`, tone: 'done' };
  }

  const wrong = (['failed', 'disconnected', 'cancelled'] as const)
    .map((state) => ({
      state,
      count: agents.filter((agent) => agent.state === state).length,
    }))
    .filter(({ count }) => count > 0);

  return {
    text: `${count} agents ended · ${wrong
      .map(({ state, count }) => `${count} ${state}`)
      .join(', ')}`,
    tone: wrong.some(({ state }) => state !== 'cancelled')
      ? 'failed'
      : 'pending',
  };
}

/**
 * A child's row in a group, laid out for `width` cells: `Agent(<title>)`,
 * then what it did and, once it has ended, how long it took. The counts go
 * first when it does not fit, then the title is cut, its brackets kept.
 */
export function groupRow(
  subagent: Subagent,
  width: number,
): { readonly headline: Headline; readonly counts?: string } {
  const whole = agentHeadline(subagent);
  const head = agentHeadline(subagent, false);
  const said = countsOf(subagent);
  const counts = said === '' ? '' : ` · ${said}`;

  // A task's model goes first, then the counts, then the title is cut.
  if (width - headlineWidth(whole) >= stringWidth(counts)) {
    return { headline: whole, counts };
  }

  const room = width - headlineWidth(head);

  if (room >= stringWidth(counts)) {
    return { headline: head, counts };
  }

  if (room >= 0 || head.arg === undefined) {
    return { headline: head };
  }

  return {
    headline: {
      ...head,
      arg: cutEnd(head.arg, Math.max(stringWidth(head.arg) + room, 1)),
    },
  };
}

function headlineWidth({ name, arg, note }: Headline): number {
  return (
    stringWidth(name) +
    (arg === undefined ? 0 : stringWidth(arg) + 2) +
    (note === undefined ? 0 : stringWidth(note))
  );
}

/** `text` in at most `width` cells, `…` the last when it was cut. */
function cutEnd(text: string, width: number): string {
  if (stringWidth(text) <= width) {
    return text;
  }

  let kept = '';

  for (const char of text) {
    if (stringWidth(`${kept}${char}…`) > width) {
      break;
    }

    kept += char;
  }

  return `${kept.trimEnd()}…`;
}

/**
 * The line under a child's row in a group: once it has ended, how; before
 * its first call, that it is starting; otherwise its current call, the one a
 * permission request waits on ahead of any later.
 */
export type RowLine =
  | { readonly kind: 'call'; readonly line: WorkLine }
  | { readonly kind: 'starting' }
  | { readonly kind: 'ended'; readonly ending: Ending };

export function rowLine(
  subagent: Subagent,
  waits: readonly PermissionWait[],
): RowLine {
  const ending = endingOf(subagent.state);

  if (ending !== undefined) {
    return { kind: 'ended', ending };
  }

  const lines = workLines(subagent, waits);
  const line = lines.find((line) => line.waiting) ?? lines.at(-1);

  return line === undefined ? { kind: 'starting' } : { kind: 'call', line };
}

/** A piece of the row a child's permission prompt opens with. */
export interface AskerPiece {
  readonly text: string;
  readonly bold: boolean;
}

/**
 * `Agent(<child>) › Agent(<grandchild>) asks`: who a permission request
 * comes from, the way down to it from the session, in `width` cells, cut
 * from the left with `…` so the one asking stays. None when the session's own
 * agent asks: the missing row is how its requests differ.
 */
export function askerRow(
  path: readonly Subagent[],
  width: number,
): AskerPiece[] {
  if (path.length === 0) {
    return [];
  }

  const pieces = path.flatMap((subagent, index): AskerPiece[] => {
    const { name, arg, note } = agentHeadline(subagent, false);

    return [
      ...(index === 0 ? [] : [{ text: ' › ', bold: false }]),
      { text: name, bold: true },
      ...(arg === undefined ? [] : [{ text: `(${arg})`, bold: false }]),
      ...(note === undefined ? [] : [{ text: note, bold: false }]),
    ];
  });

  const whole = [...pieces, { text: ' asks', bold: false }];
  let over =
    whole.reduce((sum, piece) => sum + stringWidth(piece.text), 0) - width;

  if (over <= 0) {
    return whole;
  }

  // One cell more goes to the `…` that says it was cut.
  over += 1;

  const kept: AskerPiece[] = [];

  for (const piece of whole) {
    const cells = stringWidth(piece.text);

    if (over >= cells) {
      over -= cells;

      continue;
    }

    kept.push(
      over > 0 ? { ...piece, text: cutStart(piece.text, over) } : piece,
    );

    over = 0;
  }

  return [{ text: '…', bold: false }, ...kept];
}

/** `text` with at least `cells` cells cut from its start. */
function cutStart(text: string, cells: number): string {
  const chars = [...text];
  let cut = 0;

  while (chars.length > 0 && cut < cells) {
    cut += stringWidth(chars.shift()!);
  }

  return chars.join('');
}

/**
 * The status line's words once the turn has ended with subagents still at
 * work, as their blocks may be out of sight; none when none is.
 */
export function stillRunning(count: number): string | undefined {
  return count === 0
    ? undefined
    : `${count} ${count === 1 ? 'agent' : 'agents'} still running`;
}
