/**
 * What the prompt box does that its textarea does not: `\` before Enter as a
 * newline, where a recalled prompt puts the cursor, how tall the box grows,
 * and what its gutter shows once it scrolls.
 */

import {
  type Action,
  ALWAYS,
  bound,
  type Context,
  type Keymap,
  keystrokeOf,
  lineFeed,
  parseSequence,
  type Sequence,
  sequenceHint,
  startsChord,
  types,
} from '../shortcuts/bindings.ts';
import type { KeyPress } from '../shortcuts/state.ts';

/** One of the textarea's keys, as react-ink-textarea named it. */
export type TKeybinding = string;

/** The textarea's keys turned off, by name. */
export type TKeybindings = Partial<Record<TKeybinding, boolean>>;

/** A cursor in the box: line, then column, from zero. */
export type Cursor = readonly [line: number, column: number];

/** An empty box's cursor. */
export const START: Cursor = [0, 0];

/** The end of `text`, where a recalled prompt puts the cursor. */
export function endOf(text: string): Cursor {
  const lines = text.split('\n');

  return [lines.length - 1, lines.at(-1)?.length ?? 0];
}

// OpenTUI 0.6's textarea throws on these rather than hold them: C0 but tab,
// LF and CR, then DEL and C1. A paste it cleans itself; text put in with
// setText it does not, and the owner chose refusing over rewriting (CHD-323).
// eslint-disable-next-line no-control-regex
const UNHOLDABLE = /[\0-\x08\x0b\x0c\x0e-\x1f\x7f-\x9f]/;

/**
 * The first character in `text` the box cannot hold, named as `U+000C`;
 * undefined when the box can take all of it.
 */
export function unholdable(text: string): string | undefined {
  const found = UNHOLDABLE.exec(text)?.[0];

  return found === undefined
    ? undefined
    : `U+${found.charCodeAt(0).toString(16).toUpperCase().padStart(4, '0')}`;
}

/**
 * Enter right after a `\`: the `\` becomes a line break, as in Claude Code,
 * for the terminals that do not report shift+Enter. Undefined when Enter
 * should send.
 */
export function continued(
  text: string,
  [line, column]: Cursor,
): { text: string; cursor: Cursor } | undefined {
  const lines = text.split('\n');
  const current = lines[line];

  if (current === undefined || column === 0 || current[column - 1] !== '\\') {
    return undefined;
  }

  lines.splice(line, 1, current.slice(0, column - 1), current.slice(column));

  return { text: lines.join('\n'), cursor: [line + 1, 0] };
}

/**
 * The most rows the box shows before it scrolls: a third of the window, so the
 * transcript keeps the rest, but never fewer than three or more than ten.
 */
export function promptRows(windowRows: number): number {
  return Math.min(10, Math.max(3, Math.floor(windowRows / 3)));
}

/**
 * One row of the box: which line of the prompt it shows, which wrapped piece
 * of that line, and whether it is the prompt's last row.
 */
export interface Row {
  line: number;
  piece: number;
  last: boolean;
}

/** What a row's gutter shows. */
export type Mark = '›' | '↑' | '↓' | '';

function before(a: Row, b: Row): boolean {
  return a.line < b.line || (a.line === b.line && a.piece < b.piece);
}

/**
 * `›` where the prompt starts, as in the transcript, and nowhere else; once
 * the box scrolls, `↑` on the top row while rows are hidden above it and `↓`
 * on the bottom row while rows are hidden below.
 */
export function gutterMark(row: Row, shown: readonly Row[]): Mark {
  if (row.line === 0 && row.piece === 0) {
    return '›';
  }

  if (shown.every((other) => !before(other, row))) {
    return '↑';
  }

  if (!row.last && shown.every((other) => !before(row, other))) {
    return '↓';
  }

  return '';
}

/**
 * The rows the box shows: `height` of them from `top`, out of every row
 * the textarea wraps the text into, each by the line it shows (`sources`)
 * and which piece of that line (`wraps`).
 */
export function shownRows(
  sources: readonly number[],
  wraps: readonly number[],
  top: number,
  height: number,
): Row[] {
  const rows: Row[] = [];

  for (let at = top; at < Math.min(sources.length, top + height); at++) {
    rows.push({
      line: sources[at]!,
      piece: wraps[at] ?? 0,
      last: at === sources.length - 1,
    });
  }

  return rows.length === 0 ? [{ line: 0, piece: 0, last: true }] : rows;
}

/** A line break at `cursor`, as a key bound to `chat:newline` puts one. */
export function broken(
  text: string,
  [line, column]: Cursor,
): { text: string; cursor: Cursor } {
  const lines = text.split('\n');
  const current = lines[line] ?? '';

  lines.splice(line, 1, current.slice(0, column), current.slice(column));

  return { text: lines.join('\n'), cursor: [line + 1, 0] };
}

/**
 * The keys the textarea acts on itself, by their hint names, and the action
 * each is when it is one of chord's: the textarea sends, breaks the line,
 * and hands ↑ and ↓ at its edges to history. They are react-ink-textarea's,
 * which the box was first drawn with; any other key the textarea would act
 * on is kept from it (`textareaTakes`).
 */
const TEXTAREA: Record<string, { chord: TKeybinding; action?: Action }> = {
  enter: { chord: 'Enter', action: 'chat:submit' },
  'ctrl+j': { chord: 'Ctrl+J', action: 'chat:newline' },
  'ctrl+enter': { chord: 'Ctrl+Enter', action: 'chat:newline' },
  'shift+enter': { chord: 'Shift+Enter', action: 'chat:newline' },
  'alt+enter': { chord: 'Alt+Enter', action: 'chat:newline' },
  up: { chord: 'Up', action: 'history:previous' },
  down: { chord: 'Down', action: 'history:next' },
  left: { chord: 'Left' },
  right: { chord: 'Right' },
  'alt+b': { chord: 'Alt+B' },
  'alt+f': { chord: 'Alt+F' },
  'ctrl+a': { chord: 'Ctrl+A' },
  'ctrl+e': { chord: 'Ctrl+E' },
  'ctrl+w': { chord: 'Ctrl+W' },
  'ctrl+u': { chord: 'Ctrl+U' },
  'ctrl+k': { chord: 'Ctrl+K' },
  backspace: { chord: 'Backspace' },
  delete: { chord: 'Delete' },
  'alt+backspace': { chord: 'Alt+Backspace' },
  'ctrl+z': { chord: 'Ctrl+Z' },
  'ctrl+y': { chord: 'Ctrl+Y' },
};

/** Whether the textarea does `action` itself on `pressed`, so chord need not. */
export function textareaDoes(
  pressed: Sequence | undefined,
  action: Action,
): boolean {
  return (
    pressed?.length === 1 && TEXTAREA[sequenceHint(pressed)]?.action === action
  );
}

/** The contexts whose keys the box hears while it has them. */
const BOX: readonly Context[] = ['Chat', ...ALWAYS];

/**
 * The textarea's keys turned off for `keymap`: its send and line break on a
 * key no longer bound to them, which chord then does itself, any of its
 * editing keys a binding gives to the window, so the key does one thing, and
 * any that begins one of `chords`, the ones that would run now, so the first
 * key of `ctrl+k ctrl+e` does not cut the line before the box lets go of the
 * keys. ↑ and ↓ otherwise always move between lines; whether they reach
 * history at the edges is the box's to say.
 */
export function textareaKeys(
  keymap: Keymap,
  chords: readonly Sequence[] = [],
): TKeybindings {
  const off: Partial<Record<TKeybinding, boolean>> = {};

  for (const [name, { chord, action }] of Object.entries(TEXTAREA)) {
    const bindings = keymap.bindings.filter(
      ({ context, keys }) =>
        BOX.includes(context) &&
        keys.length === 1 &&
        sequenceHint(keys) === name,
    );
    const parsed = parseSequence(name);
    const keys = 'keys' in parsed ? parsed.keys : [];
    const kept = startsChord(chords, keys)
      ? false
      : action === 'history:previous' || action === 'history:next'
        ? true
        : action === undefined
          ? bindings.length === 0
          : bindings.some((binding) => binding.action === action);

    if (!kept) {
      off[chord] = false;
    }
  }

  return off;
}

/**
 * Whether the text the textarea typed for this key is taken back: the key
 * was one of chord's, or it is the line feed ctrl+j sends, which the textarea
 * types as text whatever its own ctrl+j is set to, and ctrl+j is not a line
 * break.
 */
export function typedTakenBack(
  input: string,
  key: KeyPress,
  keymap: Keymap,
  commanded: boolean,
): boolean {
  const stroke = keystrokeOf(input, key);

  if (stroke === undefined) {
    return false;
  }

  if (lineFeed(input, key)) {
    return commanded || !bound(keymap, 'chat:newline', [stroke]);
  }

  return commanded && types(stroke);
}

/** A press by its hint name, `ctrl+w`; none for one that is no keystroke. */
export function pressHint(input: string, key: KeyPress): string | undefined {
  const stroke = keystrokeOf(input, key);

  return stroke === undefined ? undefined : sequenceHint([stroke]);
}

/** The textarea's undo and redo, which change its text without a word. */
export const UNDOES: ReadonlySet<string> = new Set(['ctrl+z', 'ctrl+y']);

/**
 * Whether the textarea acts on this press: one of its keys that `off` leaves
 * on, or text typed with no ctrl or alt. Every other key is the window's, as
 * OpenTUI's textarea has more keys of its own than the box ever had (ctrl+d
 * deletes, home and end move), and each of those is one of chord's.
 */
export function textareaTakes(
  input: string,
  key: KeyPress,
  off: TKeybindings,
): boolean {
  const stroke = keystrokeOf(input, key);
  const own =
    stroke === undefined ? undefined : TEXTAREA[sequenceHint([stroke])];

  if (own !== undefined) {
    return off[own.chord] !== false;
  }

  return input !== '' && !key.ctrl && key.meta !== true && !key.tab;
}
