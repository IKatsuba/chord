/**
 * The pickers' choices — `/model`'s models, `/resume`'s earlier sessions
 * and `/config`'s options and their values —
 * where a picker's window onto them sits, and what each key does to it, kept
 * out of the component. The list is drawn by hand, as the slash command list
 * is: ink-select-input scrolls by rotating, so it can neither keep a long
 * list in order nor say where it has scrolled to.
 */
import stringWidth from 'string-width';
import wrapAnsi from 'wrap-ansi';
import { type AgentOption, valueName } from '../../session/config.ts';
import type { AgentModels } from '../../session/models.ts';
import type { EarlierSession } from '../../session/sessions.ts';
import { homePath } from '../../settings.ts';
import { visibleRange } from '../prompt/commands.ts';
import { cutPath } from './mcp.ts';
import type { KeyPress } from '../shortcuts/state.ts';
import type { Choice } from '../dialogs/permission.ts';

/** After the model in use, and the value an option is set to. */
export const CURRENT_MARK = '✔';

/**
 * One choice on a picker; `current` is the one the list opens on: the one in
 * use, or the one come back from, when there is one.
 */
export interface PickerChoice extends Choice {
  readonly current?: boolean;
  /**
   * Where in `label` the part that wraps starts, by its characters: a label
   * wider than its row wraps from there, its further lines under that
   * start, never cut. Without it the label is one line, cut at the edge.
   */
  readonly hang?: number;
}

/**
 * `choice`'s label laid into its lines in `width` cells: one for a choice
 * that does not hang its label, else the part from its hang wrapped at its
 * spaces, a word broken only where it alone is wider, each further line
 * starting under the first's (CHD-445).
 */
export function choiceLines(choice: PickerChoice, width: number): string[] {
  if (choice.hang === undefined) {
    return [choice.label];
  }

  const lead = choice.label.slice(0, choice.hang);
  const indent = stringWidth(lead);
  const [first = '', ...rest] = wrapAnsi(
    choice.label.slice(choice.hang),
    Math.max(1, width - indent),
    { hard: true, trim: true },
  ).split('\n');

  return [lead + first, ...rest.map((line) => ' '.repeat(indent) + line)];
}

/**
 * Each choice's lines in `width` cells, where a choice hangs its label:
 * beside its columns, wrapped under the label's start; or, when the room
 * left beside the widest columns is under half of `inner`, the box's width,
 * every label on lines of its own under its columns, from the row's start,
 * so a title is not stood on end in a few cells. The choice is the
 * picker's, every row alike, so the columns still read down (CHD-445).
 * None where no choice hangs its label.
 */
export function pickerLines(
  choices: readonly PickerChoice[],
  width: number,
  inner: number,
): string[][] | undefined {
  if (!choices.some((choice) => choice.hang !== undefined)) {
    return undefined;
  }

  const lead = Math.max(
    ...choices.map((choice) =>
      choice.hang === undefined
        ? 0
        : stringWidth(choice.label.slice(0, choice.hang)),
    ),
  );

  if (width - lead >= inner / 2) {
    return choices.map((choice) => choiceLines(choice, width));
  }

  return choices.map((choice) =>
    choice.hang === undefined
      ? [choice.label]
      : [
          choice.label.slice(0, choice.hang).trimEnd(),
          ...wrapAnsi(choice.label.slice(choice.hang), Math.max(1, width), {
            hard: true,
            trim: true,
          }).split('\n'),
        ],
  );
}

/**
 * Which choices are in sight when each takes `heights` lines and `lines`
 * are room, from `top` where it can stay: as `visibleRange` for rows of one
 * line each, the highlighted choice in sight and no room left empty below
 * the last; one taller than the room is shown alone (CHD-445).
 */
export function lineRange(
  heights: readonly number[],
  highlighted: number,
  lines: number,
  top = 0,
): { readonly start: number; readonly end: number } {
  const count = heights.length;
  const taken = (from: number, to: number) =>
    heights.slice(from, to).reduce((sum, height) => sum + height, 0);

  if (taken(0, count) <= lines) {
    return { start: 0, end: count };
  }

  let start = Math.min(Math.max(top, 0), highlighted);

  while (start < highlighted && taken(start, highlighted + 1) > lines) {
    start++;
  }

  while (start > 0 && taken(start - 1, count) <= lines) {
    start--;
  }

  let end = start;
  let used = 0;

  while (end < count && (end === start || used + heights[end]! <= lines)) {
    used += heights[end]!;

    end++;
  }

  return { start, end };
}

/** `visibleRange`, or `lineRange` where choices take more than a line. */
function rangeOf(
  count: number,
  highlighted: number,
  rows: number,
  top: number,
  heights: readonly number[] | undefined,
) {
  return heights === undefined
    ? visibleRange(count, highlighted, rows, top)
    : lineRange(heights, highlighted, rows, top);
}

/** One model on the list; `current` is the one the agent says it uses. */
export interface ModelChoice extends PickerChoice {
  readonly current: boolean;
}

/** The agent's models in its order, the one in use marked. */
export function modelChoices(models: AgentModels | undefined): ModelChoice[] {
  return (models?.available ?? []).map((model) => ({
    key: model.id,
    // The mark goes after the name, where Claude Code puts it.
    label: `${model.name}${
      model.id === models?.current ? ` ${CURRENT_MARK}` : ''
    }`,
    value: model.id,
    current: model.id === models?.current,
  }));
}

/**
 * `/config`'s first list: each option by the agent's name for it, padded so
 * the values line up, then the value it is set to. The value is its id.
 */
export function optionChoices(
  options: readonly AgentOption[],
  from?: string,
): PickerChoice[] {
  const width = Math.max(0, ...options.map(({ name }) => name.length));

  return options.map((option) => ({
    key: option.id,
    label: `${option.name.padEnd(width)}  ${valueName(option, option.current)}`,
    value: option.id,
    ...(option.id === from ? { current: true } : {}),
  }));
}

/** `/config`'s second list: one option's values, the one it is set to marked. */
export function valueChoices(option: AgentOption): PickerChoice[] {
  return option.values.map(({ value, name }) => ({
    key: value,
    label: `${name}${value === option.current ? ` ${CURRENT_MARK}` : ''}`,
    value,
    current: value === option.current,
  }));
}

/**
 * The value to ask the agent for when `value` is picked for `option`: none
 * for the one it is set to already, as there is nothing to change.
 */
export function valueToAsk(
  option: AgentOption,
  value: string,
): string | undefined {
  return value === option.current ? undefined : value;
}

/** The most columns `/resume`'s directory column takes; longer ones lose their start. */
export const DIRECTORY_WIDTH = 30;

/**
 * `/resume`'s rows, newest first: when each session was last used, padded
 * so the text lines up, then its label: the agent's title or its first
 * prompt, after a child's name (CHD-445). With `home`, as the list of
 * every directory draws them, each row names its directory between the two,
 * from `~` and cut from the start to `DIRECTORY_WIDTH`, where the name that
 * tells two apart is, and at a `/` so the segments left are whole. A label
 * wider than its row wraps under its own start (`hang`). A session open
 * now, as a child of this one, says `open now` after when it was used, as
 * picking it goes to the child rather than load it twice. The value is the
 * session's place in `sessions`.
 */
export function sessionChoices(
  sessions: readonly EarlierSession[],
  now: number,
  directories?: { readonly home: string | undefined },
  /** The ids of the sessions open now. */
  open: ReadonlySet<string> = new Set(),
): PickerChoice[] {
  const when = sessions.map((session) => lastUsed(session.lastUsedAt, now));
  const width = Math.max(0, ...when.map((text) => text.length));
  const opens = sessions.map((session) =>
    open.has(session.resume.sessionId) ? 'open now' : '',
  );
  const opensWidth = Math.max(0, ...opens.map((text) => text.length));
  const where =
    directories === undefined
      ? undefined
      : sessions.map((session) =>
          cutPath(
            homePath(session.resume.cwd, directories.home),
            DIRECTORY_WIDTH,
          ),
        );
  const whereWidth = Math.max(
    0,
    ...(where ?? []).map((text) => stringWidth(text)),
  );

  return sessions.map((session, index) => {
    const lead = [
      when[index]!.padEnd(width),
      ...(opensWidth === 0 ? [] : [opens[index]!.padEnd(opensWidth)]),
      ...(where === undefined
        ? []
        : [
            where[index]! + ' '.repeat(whereWidth - stringWidth(where[index]!)),
          ]),
    ].join('  ');

    return {
      key: session.resume.sessionId,
      label: `${lead}  ${session.prompt}`,
      // The title or prompt wraps under its own start (CHD-445).
      hang: lead.length + 2,
      value: String(index),
    };
  });
}

const RELATIVE = new Intl.RelativeTimeFormat('en', { numeric: 'auto' });

const UNITS: readonly [Intl.RelativeTimeFormatUnit, number][] = [
  ['year', 365 * 24 * 60 * 60],
  ['month', 30 * 24 * 60 * 60],
  ['week', 7 * 24 * 60 * 60],
  ['day', 24 * 60 * 60],
  ['hour', 60 * 60],
  ['minute', 60],
];

/**
 * When a session was last used, from `now`, epoch milliseconds: `just now`
 * inside a minute, then `5 minutes ago`, `yesterday`, `3 weeks ago`. A
 * timestamp that does not read as one is shown as it is.
 */
export function lastUsed(at: string, now: number): string {
  const time = Date.parse(at);

  if (Number.isNaN(time)) {
    return at;
  }

  const seconds = Math.max(0, Math.floor((now - time) / 1000));
  const unit = UNITS.find(([, size]) => seconds >= size);

  return unit
    ? RELATIVE.format(-Math.floor(seconds / unit[1]), unit[0])
    : 'just now';
}

/** Where the highlight starts: on the choice in use, or the first. */
export function initialChoice(choices: readonly PickerChoice[]): number {
  return Math.max(
    0,
    choices.findIndex((choice) => choice.current === true),
  );
}

/**
 * The highlighted choice and the first one shown. The window moves only when
 * the highlight leaves it, so the rows hold still while it walks among them.
 */
export interface PickerView {
  readonly highlighted: number;
  readonly top: number;
}

/** The view a picker opens on: the choice in use highlighted and in sight. */
export function openView(
  choices: readonly PickerChoice[],
  rows: number,
  /** Each choice's lines, where one may take more than one. */
  heights?: readonly number[],
): PickerView {
  const highlighted = initialChoice(choices);

  return {
    highlighted,
    top: rangeOf(choices.length, highlighted, rows, 0, heights).start,
  };
}

/** The parts of a press the picker reads. */
export interface PickerKey {
  readonly upArrow: boolean;
  readonly downArrow: boolean;
  readonly return: boolean;
  readonly shift: boolean;
}

/** What a key does to the picker: moves its highlight, or picks a choice. */
export type PickerStep =
  | { readonly type: 'move'; readonly view: PickerView }
  | { readonly type: 'pick'; readonly index: number };

/**
 * The picker's answer to a key, as the permission prompt's ink-select-input
 * answers it, so the two lists take the same keys: ↑/↓ and j/k move, a digit
 * picks the choice with that number, Enter picks the highlighted one. Unlike
 * that list, the highlight stops at either end rather than going round, as
 * the order would otherwise seem to start over. j and k are read whatever is
 * held with them and Enter likewise, as ink-select-input reads them;
 * shift+↑/↓ are the window's, which scrolls the transcript on them.
 */
export function pickerKey(
  view: PickerView,
  count: number,
  rows: number,
  input: string,
  key: PickerKey,
  /** Each choice's lines, where one may take more than one. */
  heights?: readonly number[],
): PickerStep | undefined {
  if (count === 0) {
    return undefined;
  }

  if (key.return) {
    return { type: 'pick', index: view.highlighted };
  }

  if (/^[1-9]$/.test(input)) {
    const index = Number(input) - 1;

    return index < count ? { type: 'pick', index } : undefined;
  }

  const step =
    (key.upArrow && !key.shift) || input === 'k'
      ? -1
      : (key.downArrow && !key.shift) || input === 'j'
        ? 1
        : 0;
  const highlighted = Math.min(Math.max(view.highlighted + step, 0), count - 1);

  if (highlighted === view.highlighted) {
    return undefined;
  }

  return {
    type: 'move',
    view: {
      highlighted,
      top: rangeOf(count, highlighted, rows, view.top, heights).start,
    },
  };
}

/** One row of the picker as drawn. */
export interface PickerRow<C extends PickerChoice = PickerChoice> {
  readonly choice: C;
  readonly highlighted: boolean;
  /** Its place in the whole list, which its digit picks: `1.`, `10.`. */
  readonly number: string;
  /**
   * `↑` on the first row when choices are hidden above it, `↓` on the last
   * when they are hidden below, `' '` on the others; absent when every
   * choice is in sight.
   */
  readonly edge?: '↑' | '↓' | ' ';
}

/**
 * The rows in sight and how many choices are not, numbered by their place in
 * the whole list and padded so the labels line up past `9.`.
 */
export function pickerRows<C extends PickerChoice>(
  choices: readonly C[],
  view: PickerView,
  rows: number,
  /** Each choice's lines, where one may take more than one. */
  heights?: readonly number[],
): { readonly rows: PickerRow<C>[]; readonly hidden: number } {
  const { start, end } = rangeOf(
    choices.length,
    view.highlighted,
    rows,
    view.top,
    heights,
  );
  const scrolls = end - start < choices.length;
  const width = `${choices.length}.`.length;

  return {
    rows: choices.slice(start, end).map((choice, offset) => {
      const index = start + offset;
      const edge =
        offset === 0 && start > 0
          ? '↑'
          : index === end - 1 && end < choices.length
            ? '↓'
            : ' ';

      return {
        choice,
        highlighted: index === view.highlighted,
        number: `${index + 1}.`.padEnd(width),
        ...(scrolls ? { edge } : {}),
      };
    }),
    hidden: choices.length - (end - start),
  };
}

/**
 * The model to ask the agent for when `id` is picked: none for the one it
 * already uses, as there is nothing to switch.
 */
export function modelToAsk(
  models: AgentModels | undefined,
  id: string,
): string | undefined {
  return id === models?.current ? undefined : id;
}

/**
 * What a key does to a numbered choice list with `count` choices and
 * `highlighted` lit: ↑ and ↓ (or k and j) move the highlight, round past
 * either end; Enter picks it; a choice's number, 1 to 9, picks that one.
 * Shift+arrows are the window's, so they do nothing here.
 */
export function choiceKey(
  input: string,
  key: KeyPress,
  highlighted: number,
  count: number,
  /**
   * ↓ on the last choice leaves the box for the agents list, rather than
   * wrapping to the first (Q194).
   */
  ends = false,
): { move: number } | { pick: number } | { leave: true } | undefined {
  if (count === 0 || (key.shift === true && (key.upArrow || key.downArrow))) {
    return undefined;
  }

  if (key.upArrow === true || input === 'k') {
    return { move: (highlighted + count - 1) % count };
  }

  if (key.downArrow === true || input === 'j') {
    return ends && highlighted === count - 1
      ? { leave: true }
      : { move: (highlighted + 1) % count };
  }

  if (key.return === true) {
    return { pick: highlighted };
  }

  const number = /^[1-9]$/.test(input) ? Number(input) - 1 : -1;

  return number >= 0 && number < count ? { pick: number } : undefined;
}
