/**
 * The status line under the prompt. On the left, a message, the agent's mode
 * when it is not its default, or a key hint; on the right what the agent has
 * said about itself — model, effort, context used — each only once the agent
 * has reported it. A narrow window gets a shorter line rather than a second
 * one.
 * Above the prompt while a turn runs, the working line: what the turn waits
 * on, and for how long.
 */
import cliTruncate from 'cli-truncate';
import stringWidth from 'string-width';
import {
  type Failure,
  FAILURES,
  failureOf,
  type TabWait,
} from '../../session/tabs.ts';
import type { TurnState, Usage } from '../../session/transcript/types.ts';
import {
  type Action,
  type Binding,
  gotoAction,
  type Sequence,
  sequenceHint,
  TAB_NUMBERS,
} from '../shortcuts/bindings.ts';
import { SHORTCUTS } from '../shortcuts/keys.ts';
import { formatElapsed } from '../../session/elapsed.ts';
import { GLYPHS } from '../app/strip.ts';
import type { VimMode } from '../prompt/vim.ts';
import type { MarkTones } from '../theme/theme.ts';

/** How a part of the line is coloured; the component picks the colours. */
export type StatusTone =
  | 'plain'
  | 'plan'
  | 'edits'
  | 'auto'
  | 'bypass'
  | 'low'
  | 'bash'
  | 'failed'
  /** A copy that failed, which keeps its selection for another try. */
  | 'error'
  /** A session behind waits on a permission or form. */
  | 'waits'
  /** A session behind failed. */
  | 'ended';

export interface StatusPart {
  readonly text: string;
  readonly tone: StatusTone;
}

export interface StatusLineView {
  /** The left side's parts, drawn with a space between them. */
  readonly left: readonly StatusPart[];
  /** The right side's parts, drawn with `STATUS_SEPARATOR` between them. */
  readonly right: readonly StatusPart[];
}

export const STATUS_SEPARATOR = ' · ';

/** Said after a mode, as Claude Code says it, so the key is never hidden. */
export function cycleHint(key = 'shift+tab'): string {
  return `(${key} to cycle)`;
}

/** Space kept between the two sides. */
const GAP = 2;

/** Above this share of the window used, the context reads as running low. */
const HIGH_CONTEXT = 80;

/** Claude Code's words for Claude's modes. */
const MODES: Record<string, StatusPart> = {
  plan: { text: '⏸ plan mode on', tone: 'plan' },
  acceptEdits: { text: '⏵⏵ accept edits on', tone: 'edits' },
  auto: { text: '⏵⏵ auto mode on', tone: 'auto' },
  bypassPermissions: { text: '⏵⏵ bypass permissions on', tone: 'bypass' },
};

const QUIET_MODES = new Set(['default']);

/** What the line is made from. */
export interface StatusFacts {
  readonly model?: string | undefined;
  /** The id of the effort the agent is on; none for a runtime with none. */
  readonly effort?: string | undefined;
  /** The id of the mode the agent reports. */
  readonly mode?: string | undefined;
  /** The agent's own name for that mode, such as `Read Only`. */
  readonly modeName?: string | undefined;
  readonly usage?: Usage | undefined;
  /** The prompt takes a shell command; said in place of a mode or a hint. */
  readonly bash?: boolean | undefined;
  /** A message that must stay, such as the second ctrl+c's warning. */
  readonly notice?: string | undefined;
  /**
   * The notice says something asked for did not happen, so it is coloured
   * as a warning rather than dim like a hint or progress.
   */
  readonly failed?: boolean | undefined;
  /** The notice is a failure in the error colour, as a copy's is. */
  readonly error?: boolean | undefined;
  /**
   * A key hint, for when no mode is shown. It goes only once the right side
   * has shortened as far as it can short of dropping the model.
   */
  readonly hint?: string | undefined;
  /**
   * The key that cycles modes, named after a mode; shift+tab when not said,
   * and no hint at all when null, as nothing cycles them.
   */
  readonly cycleKey?: string | null | undefined;
  /** Vim mode's mode, marked first on the left while `/vim` has it on. */
  readonly vim?: VimMode | undefined;
  /** What the sessions behind want of the person, ahead of the mode or hint. */
  readonly waits?: WaitsNotice | undefined;
}

/**
 * The notice of the sessions behind that want the person: what it says, its
 * tone, and the key that goes to them, if one is bound.
 */
export interface WaitsNotice {
  readonly text: string;
  readonly tone: StatusTone;
  readonly key?: string | undefined;
}

/**
 * A tab behind the front one, or an agent of the front tab's not picked, as
 * the notice reads it.
 */
export interface TabBehind {
  /** Its place in the strip. */
  readonly number: number;
  readonly agent: string;
  readonly wait: TabWait;
  /**
   * An agent of the front tab's, by its own name: `docs`, or `main` while a
   * child is picked. A reply of one says nothing here, as the list under
   * the prompt already shows it.
   */
  readonly name?: string;
}

/** A failure's words after a name, `parser's turn failed`, and in a count. */
const FAILURE_WORDS: Record<
  Failure,
  {
    readonly named: (name: string) => string;
    readonly counted: (count: number) => string;
  }
> = {
  exited: {
    named: (name) => `${name} exited`,
    counted: (count) => `${count} exited`,
  },
  start: {
    named: (name) => `${name} failed to start`,
    counted: (count) => `${count} failed to start`,
  },
  turn: {
    named: (name) => `${name}'s turn failed`,
    counted: (count) => `${count} ${count === 1 ? 'turn' : 'turns'} failed`,
  },
};

/**
 * The notice for the tabs behind, or none when none wants the person. A
 * permission or form outranks a failure, which outranks a reply; within each,
 * the one waiting longest is named, or the count once there are more. Many
 * failures count each kind on its own, gravest first, with no noun, so an
 * agent still open is never said to have ended (CHD-264).
 */
export function waitsNotice(
  behind: readonly TabBehind[],
  key?: string,
): WaitsNotice | undefined {
  const oldest = (since: (tab: TabBehind) => number | undefined) =>
    behind
      .filter((tab) => since(tab) !== undefined)
      .sort((a, b) => since(a)! - since(b)! || a.number - b.number);
  const asking = oldest((tab) => tab.wait.asking?.since);
  const failed = oldest((tab) =>
    tab.wait.unseen?.kind === 'failed' ? tab.wait.unseen.since : undefined,
  );
  const replied = oldest((tab) =>
    tab.wait.unseen?.kind === 'replied' && tab.name === undefined
      ? tab.wait.unseen.since
      : undefined,
  );
  const named = (tab: TabBehind) => tab.name ?? `${tab.number} ${tab.agent}`;
  const notice = (text: string, tone: StatusTone): WaitsNotice =>
    key === undefined ? { text, tone } : { text, tone, key };
  const [first] = asking;

  if (first) {
    // The front tab's own agents are agents, not sessions.
    const what = asking.every((tab) => tab.name !== undefined)
      ? 'agents'
      : 'sessions';

    return asking.length > 1
      ? notice(`${GLYPHS.asking} ${asking.length} ${what} wait`, 'waits')
      : first.wait.asking?.on.kind === 'input'
        ? notice(`${GLYPHS.asking} ${named(first)} asks for input`, 'waits')
        : notice(
            `${GLYPHS.asking} ${named(first)} needs your permission`,
            'waits',
          );
  }

  if (failed.length > 1) {
    const counts = FAILURES.flatMap((failure) => {
      const count = failed.filter(
        (tab) => failureOf(tab.wait) === failure,
      ).length;

      return count === 0 ? [] : [FAILURE_WORDS[failure].counted(count)];
    });

    return notice(`${GLYPHS.failed} ${counts.join(' · ')}`, 'ended');
  }

  if (failed[0]) {
    return notice(
      `${GLYPHS.failed} ${FAILURE_WORDS[
        failureOf(failed[0].wait) ?? 'turn'
      ].named(named(failed[0]))}`,
      'ended',
    );
  }

  return replied.length > 1
    ? notice(`${GLYPHS.replied} ${replied.length} sessions replied`, 'plain')
    : replied[0]
      ? notice(`${GLYPHS.replied} ${named(replied[0])} replied`, 'plain')
      : undefined;
}

/** The notice's parts, with the key in full words or bare. */
function waitsParts(waits: WaitsNotice, wide: boolean): StatusPart[] {
  const key =
    waits.key === undefined
      ? ''
      : `${STATUS_SEPARATOR}${waits.key}${wide ? ' to go' : ''}`;

  return [{ text: `${waits.text}${key}`, tone: waits.tone }];
}

/**
 * The share of the context window taken, as a whole percentage: the
 * complement of the free share rounded down, as the line showed it when it
 * said what was left, so the number moves at the same token it always did.
 */
export function contextUsed(usage: Usage): number {
  if (usage.size <= 0) {
    return 100;
  }

  const left = ((usage.size - usage.used) / usage.size) * 100;

  return 100 - Math.min(100, Math.max(0, Math.floor(left)));
}

/**
 * The mode as the line names it, or undefined for the default, which says
 * nothing as in Claude Code. A mode chord has no words for reads as the
 * agent's name for it, the one its user knows; chord does not guess whether
 * it is safe, so it is not coloured.
 */
export function modePart(mode: string, name?: string): StatusPart | undefined {
  if (QUIET_MODES.has(mode)) {
    return undefined;
  }

  return (
    MODES[mode] ?? {
      text: `⏵⏵ ${(name || mode).toLowerCase()} mode on`,
      tone: 'plain',
    }
  );
}

/**
 * Whether the context figures are chord's estimate, from the model's window
 * or the turn's tokens, rather than what the agent said.
 */
export function contextEstimated(usage: Usage): boolean {
  return usage.estimated?.some((field) => field !== 'cost') ?? false;
}

/** The mark ahead of a figure chord worked out itself. */
export const ESTIMATE_MARK = '~';

function contextPart(usage: Usage, short: boolean): StatusPart {
  const used = contextUsed(usage);
  const mark = contextEstimated(usage) ? ESTIMATE_MARK : '';

  return {
    text: short ? `${mark}${used}% used` : `${mark}${used}% context used`,
    tone: used > HIGH_CONTEXT ? 'low' : 'plain',
  };
}

function rightParts(
  facts: StatusFacts,
  short: boolean,
  model: string | undefined,
  effort: string | undefined,
): StatusPart[] {
  return [
    ...(model ? [{ text: model, tone: 'plain' as const }] : []),
    // Wide, the word keeps a bare `high` beside the context from reading as
    // the context running high; short, it goes with the context's own word.
    ...(effort
      ? [{ text: short ? effort : `${effort} effort`, tone: 'plain' as const }]
      : []),
    // A window nobody knows leaves nothing to say how much of it is used.
    ...(facts.usage && facts.usage.size > 0
      ? [contextPart(facts.usage, short)]
      : []),
  ];
}

export function partsWidth(
  parts: readonly StatusPart[],
  separator = STATUS_SEPARATOR,
): number {
  return parts.length === 0
    ? 0
    : stringWidth(parts.map((part) => part.text).join(separator));
}

function leftWidth(left: readonly StatusPart[]): number {
  return partsWidth(left, ' ');
}

function fits(
  left: readonly StatusPart[],
  right: readonly StatusPart[],
  width: number,
) {
  const gap = left.length > 0 && right.length > 0 ? GAP : 0;

  return leftWidth(left) + gap + partsWidth(right) <= width;
}

/** A left side to try, and whether the model may be cut beside it. */
interface LeftSide {
  readonly parts: readonly StatusPart[];
  readonly cut: boolean;
}

/** The left sides to try, fullest first, each after vim's mark while it is on. */
function leftSides(facts: StatusFacts): LeftSide[] {
  const sides = waitingSides(facts);

  if (facts.vim === undefined) {
    return sides;
  }

  // Claude Code's mark, ahead of whatever else the line says, so the mode
  // the keys are in is never the part that goes.
  const mark: StatusPart = { text: VIM_MARKS[facts.vim], tone: 'plain' };

  return sides.map((side) => ({ ...side, parts: [mark, ...side.parts] }));
}

/** How the line marks each of vim's modes. */
export const VIM_MARKS: Record<VimMode, string> = {
  insert: '-- INSERT --',
  normal: '-- NORMAL --',
};

/**
 * The left sides but for vim's mark, each after the sessions behind's notice
 * while there is one: its key in full words beside the fullest side, then
 * bare, so the hint or the mode beside it goes as it would without it. The
 * words go before the model is cut, and the hint too, as the notice already
 * names a key. A
 * message stands alone, as it says what was just pressed.
 */
function waitingSides(facts: StatusFacts): LeftSide[] {
  const sides = unmarkedSides(facts);
  const { waits } = facts;
  const isHint = (part: StatusPart) =>
    facts.hint !== undefined && part.text === facts.hint;

  if (waits === undefined || facts.notice) {
    return sides;
  }

  return sides.flatMap((side) =>
    [true, false].map((wide) => ({
      cut: side.cut && !wide && !side.parts.some(isHint),
      parts: [
        ...waitsParts(waits, wide),
        ...(side.parts.length === 0
          ? []
          : [{ text: '·', tone: 'plain' as const }, ...side.parts]),
      ],
    })),
  );
}

/**
 * The left sides but for vim's mark and the waits. A notice stands alone, and bash mode
 * after it. A mode stays to
 * the last, its hint going before the model is cut. The shortcut hint stays
 * until the model has been cut, since it is the one way to find the keys.
 */
function unmarkedSides(facts: StatusFacts): LeftSide[] {
  if (facts.notice) {
    const tone = facts.error ? 'error' : facts.failed ? 'failed' : 'plain';

    return [{ parts: [{ text: facts.notice, tone }], cut: true }];
  }

  // Claude Code's words, in its colour, while the prompt is a command.
  if (facts.bash) {
    return [{ parts: [{ text: '! for bash mode', tone: 'bash' }], cut: true }];
  }

  const mode =
    facts.mode === undefined ? undefined : modePart(facts.mode, facts.modeName);

  if (mode) {
    return [
      ...(facts.cycleKey === null
        ? []
        : [
            {
              parts: [
                mode,
                {
                  text: cycleHint(facts.cycleKey),
                  tone: 'plain' as const,
                },
              ],
              cut: false,
            },
          ]),
      { parts: [mode], cut: true },
    ];
  }

  return [
    ...(facts.hint
      ? [{ parts: [{ text: facts.hint, tone: 'plain' as const }], cut: true }]
      : []),
    { parts: [], cut: true },
  ];
}

/**
 * The line for `width` cells: the first left side, from `leftSides`, beside
 * which the right side fits — whole; with the effort and the context in
 * short words; without the effort; with the model cut to the room left (`…`).
 * Last, the left side that stays without the model and the effort, and beside
 * a notice or a mode without the context either, so neither is ever the part
 * cut. What still does not fit is cut at the edge by the component.
 */
export function statusLine(facts: StatusFacts, width: number): StatusLineView {
  const sides = leftSides(facts);

  for (const side of sides) {
    const found = shortened(facts, side, width);

    if (found) {
      return found;
    }
  }

  const left = sides.at(-1)?.parts ?? [];
  const right = rightParts(facts, true, undefined, undefined);

  while (left.length > 0 && right.length > 0 && !fits(left, right, width)) {
    right.pop();
  }

  return { left, right };
}

/**
 * The right side shortened beside `side`, short of dropping the model. The
 * effort goes before the model is cut, as in the agent list, since the model
 * names the agent and the list shows the effort whenever it is open.
 */
function shortened(
  facts: StatusFacts,
  side: LeftSide,
  width: number,
): StatusLineView | undefined {
  const { model, effort } = facts;
  const left = side.parts;
  const tries: readonly (readonly [boolean, string | undefined])[] = [
    [false, effort],
    [true, effort],
    [true, undefined],
  ];

  for (const [short, shown] of tries) {
    const right = rightParts(facts, short, model, shown);

    if (fits(left, right, width)) {
      return { left, right };
    }
  }

  if (!model || !side.cut) {
    return undefined;
  }

  const bare = rightParts(facts, true, undefined, undefined);
  const room =
    width -
    leftWidth(left) -
    (left.length === 0 ? 0 : GAP) -
    partsWidth(bare) -
    (bare.length > 0 ? STATUS_SEPARATOR.length : 0);

  // A model cut to a letter or two names nothing; drop it instead.
  return room >= 6
    ? {
        left,
        right: rightParts(
          facts,
          true,
          cliTruncate(model, room, { preferTruncationOnSpace: true }),
          undefined,
        ),
      }
    : undefined;
}

/** One key the leader line offers and what it does: `c new`. */
export interface LeaderItem {
  readonly keys: string;
  /** None where the keys say it, as `1–9` does once the line is short. */
  readonly words: string;
}

/** The line after a chord's first keys: those keys, then what may follow. */
export interface LeaderLineView {
  /** The keys held, as `ctrl+x …`. */
  readonly held: string;
  readonly items: readonly LeaderItem[];
}

/** Between the keys held and the first item, wider than between items. */
export const LEADER_GAP = '  ';

/** The session actions' words, wide and short, in the order they are offered. */
const SESSION_WORDS: readonly {
  readonly action: Action;
  readonly wide: string;
  readonly short: string;
}[] = [
  { action: 'session:new', wide: 'new', short: 'new' },
  { action: 'session:next', wide: 'next', short: 'next' },
  { action: 'session:previous', wide: 'previous', short: 'prev' },
];

/** What the panel says an action does, without its `to` or `for`. */
function doesOf(action: Action): string {
  const does =
    SHORTCUTS.find((shortcut) => shortcut.actions?.includes(action))?.does ??
    action;

  return does.replace(/^(to|for) /, '');
}

/** The key after the held ones that runs each action, the first bound. */
function nextKeys(
  held: Sequence,
  bindings: readonly Binding[],
): Map<Action, string> {
  const next = new Map<Action, string>();

  for (const { action, keys } of bindings) {
    if (!next.has(action)) {
      next.set(action, sequenceHint(keys.slice(held.length)));
    }
  }

  return next;
}

function leaderItems(next: Map<Action, string>, short: boolean): LeaderItem[] {
  const items: LeaderItem[] = [];
  const sessions = SESSION_WORDS.filter(({ action }) => next.has(action));
  const forward = next.get('session:next');
  const back = next.get('session:previous');

  for (const { action, wide, short: brief } of sessions) {
    // Short, the pair reads as one item: `n p next prev`.
    if (short && forward !== undefined && back !== undefined) {
      if (action === 'session:next') {
        items.push({ keys: `${forward} ${back}`, words: 'next prev' });
      }

      if (action === 'session:next' || action === 'session:previous') {
        continue;
      }
    }

    items.push({ keys: next.get(action)!, words: short ? brief : wide });
  }

  const tabs = TAB_NUMBERS.flatMap((n) => next.get(gotoAction(n)) ?? []);

  if (tabs.length > 0) {
    const all = tabs.join('') === TAB_NUMBERS.join('');

    items.push({
      keys: all ? '1–9' : tabs.join(' '),
      words: short ? '' : 'go to',
    });
  }

  const list = next.get('session:list');

  if (list !== undefined) {
    items.push({ keys: list, words: 'list' });
  }

  const attention = next.get('session:attention');

  if (attention !== undefined) {
    items.push({
      keys: attention,
      words: short ? 'waits' : 'the one that waits',
    });
  }

  const close = next.get('session:close');

  if (close !== undefined) {
    items.push({ keys: close, words: 'close' });
  }

  const offered = new Set<Action>([
    ...SESSION_WORDS.map(({ action }) => action),
    ...TAB_NUMBERS.map(gotoAction),
    'session:list',
    'session:attention',
    'session:close',
  ]);

  for (const [action, keys] of next) {
    if (!offered.has(action)) {
      items.push({ keys, words: doesOf(action) });
    }
  }

  return short ? items : [...items, { keys: 'esc', words: 'never mind' }];
}

/** The leader line's text, as wide as it is drawn. */
export function leaderWidth(view: LeaderLineView): number {
  return stringWidth(
    view.held +
      LEADER_GAP +
      view.items
        .map(({ keys, words }) => (words === '' ? keys : `${keys} ${words}`))
        .join(STATUS_SEPARATOR),
  );
}

/**
 * What the status line says after a chord's first keys, `held`: each key
 * that can follow and what it does, from `bindings`, the chords that would
 * run now and start with `held`, so a rebound or removed action shows as it
 * is. The session actions come first, in a fixed order, then any other in
 * the order bound. Too wide, the line takes shorter words; still too wide,
 * it drops items from its end rather than cut one through.
 */
export function leaderLine(
  held: Sequence,
  bindings: readonly Binding[],
  width: number,
): LeaderLineView {
  const next = nextKeys(held, bindings);
  const view = (items: readonly LeaderItem[]): LeaderLineView => ({
    held: `${sequenceHint(held)} …`,
    items,
  });
  const wide = view(leaderItems(next, false));

  if (leaderWidth(wide) <= width) {
    return wide;
  }

  const items = leaderItems(next, true);

  while (items.length > 0 && leaderWidth(view(items)) > width) {
    items.pop();
  }

  return view(items);
}

/** The spinner line's words while a turn runs, or nothing when idle. */
export function workingLine(
  turn: TurnState,
  now: number,
  /** A form or link is open, below the line. */
  asking = false,
  /** The key that interrupts, named in the line; none when none is bound. */
  cancelKey: string | undefined,
  /** The agent is compacting the conversation within the turn. */
  compacting = false,
): { readonly label: string; readonly detail: string } | undefined {
  if (asking && turn.status === 'working') {
    // Esc answers the form below rather than interrupting the turn.
    return {
      label: 'Waiting for your input…',
      detail: formatElapsed(now - turn.since),
    };
  }

  switch (turn.status) {
    case 'idle':
      return undefined;
    case 'cancelling':
      return {
        label: 'Interrupting…',
        detail: formatElapsed(now - turn.since),
      };
    case 'awaiting_permission':
      return {
        // Esc answers the prompt below rather than interrupting the turn;
        // chord's own question asks no permission.
        label:
          turn.permissions[0]?.save === undefined
            ? 'Waiting for permission…'
            : 'Waiting for you…',
        detail: formatElapsed(now - turn.since),
      };
    case 'working':
      return {
        label: compacting ? 'Compacting conversation…' : 'Working…',
        detail:
          cancelKey === undefined
            ? formatElapsed(now - turn.since)
            : `${formatElapsed(now - turn.since)} · ${cancelKey} to interrupt`,
      };
  }
}

/** How many of Chorded's marks the working line's spinner turns. */
export const SPINNER_MARKS = 3;

/** The spinner's steps: the light one on each mark, then a rest. */
export const SPINNER_STEPS = SPINNER_MARKS + 1;

/** One `›` of the spinner: its colour, and whether it is drawn dim. */
export interface SpinnerMark {
  readonly colour: string | undefined;
  readonly dim: boolean;
}

/**
 * The spinner at `step`: the mark's light colour on one of three marks in
 * its dark one, or, where the theme gives the mark no gradient, its one
 * tone, the others dim.
 */
export function spinnerMarks(
  step: number,
  mark: MarkTones | undefined,
): SpinnerMark[] {
  return Array.from({ length: SPINNER_MARKS }, (_, index) => {
    const lit = index === step % SPINNER_STEPS;

    if (mark?.stops) {
      return { colour: lit ? mark.stops[0] : mark.stops[2], dim: false };
    }

    return { colour: mark?.tone, dim: !lit };
  });
}
