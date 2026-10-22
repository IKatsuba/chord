/**
 * The permission prompt's choices and what they mean, kept out of the
 * component. ink-select-input moves the highlight and reads 1–9, ↑/↓, j/k
 * and Enter; this module says what is on the list and what a pick answers.
 */
import type { PermissionOption } from '@agentclientprotocol/sdk';
import stringWidth from 'string-width';
import type {
  Entry,
  PermissionWait,
  TurnState,
} from '../../session/transcript/types.ts';
import { wrapLine } from '../transcript/message.ts';
import type { ScrollStep } from '../transcript/scroll.ts';

/** One row of the list, in ink-select-input's item shape. */
export interface Choice {
  readonly key: string;
  /** `1. Allow`: the number is the key that picks it. */
  readonly label: string;
  /** The option's id, which is what the agent hears back. */
  readonly value: string;
}

/**
 * The request on screen: the oldest one the turn waits on. A second request
 * waits its turn behind the first, as in Claude Code.
 */
export function askedPermission(turn: TurnState): PermissionWait | undefined {
  return turn.status === 'awaiting_permission'
    ? turn.permissions[0]
    : undefined;
}

/** The agent's own options, numbered in the agent's order; none invented. */
export function choicesFor(wait: PermissionWait): Choice[] {
  return wait.options.map((option, index) => ({
    key: option.optionId,
    label: `${index + 1}. ${option.name}`,
    value: option.optionId,
  }));
}

/** Between a save box's choice and the file it writes. */
const FILE_GAP = 2;

/**
 * The choices of chord's own question, as `propose_team`'s save box asks
 * it: each numbered, the file it writes after it, in a column of its own.
 */
export function saveChoices(wait: PermissionWait): Choice[] {
  const files = wait.save?.files ?? {};
  const labels = wait.options.map(
    (option, index) => `${index + 1}. ${option.name}`,
  );
  const width = Math.max(
    ...labels
      .filter((_, index) => files[wait.options[index]!.optionId] !== undefined)
      .map((label) => label.length),
    0,
  );

  return wait.options.map((option, index) => {
    const file = files[option.optionId];

    return {
      key: option.optionId,
      label:
        file === undefined
          ? labels[index]!
          : `${labels[index]!.padEnd(width + FILE_GAP)}${file}`,
      value: option.optionId,
    };
  });
}

function allows(option: PermissionOption): boolean {
  return option.kind === 'allow_once' || option.kind === 'allow_always';
}

/**
 * The locations worth a line of their own. Agents often put the path in the
 * title already (`Write notes.txt`), and a second line saying `notes.txt`
 * only repeats it.
 */
export function locationsShown(wait: PermissionWait): string[] {
  const title = wait.title ?? '';

  return (wait.locations ?? [])
    .map((location) => location.path)
    .filter((path) => !title.endsWith(path));
}

/**
 * A request's arguments, one `key: value` per line, when it has no content to
 * say what it does: strings unquoted so a command reads as typed, anything
 * nested as compact JSON. Each line wraps at the indent it is drawn at.
 */
export function inputLines(wait: PermissionWait): string[] {
  const { rawInput } = wait;

  if (rawInput === undefined || rawInput === null) {
    return [];
  }

  if (typeof rawInput !== 'object' || Array.isArray(rawInput)) {
    return [shown(rawInput)];
  }

  return Object.entries(rawInput).map(
    ([key, value]) => `${key}: ${shown(value)}`,
  );
}

function shown(value: unknown): string {
  return typeof value === 'string' ? value : String(JSON.stringify(value));
}

/**
 * The transcript's line for an answered request. A reject option's name
 * (`Deny`) only says "Rejected" again, so the line names allow options alone.
 */
export function permissionOutcome(
  entry: Extract<Entry, { kind: 'permission' }>,
): { readonly text: string; readonly allowed: boolean } {
  const { option } = entry;
  const allowed = option !== undefined && allows(option);
  const what = entry.title ?? 'the tool call';
  const how = allowed ? ` · ${option.name}` : '';

  return { text: `${allowed ? 'Allowed' : 'Rejected'} ${what}${how}`, allowed };
}

/** A row of the request the box scrolls, and how it is drawn. */
export interface RequestRow {
  readonly text: string;
  readonly kind: 'title' | 'location' | 'input';
}

/** The cells an argument's rows hang in from the box's edge. */
export const INPUT_INDENT = 2;

/**
 * The request laid out in rows of `width` cells, each wrapped, never cut, as
 * `wrapLine` wraps it: the title's first row, pinned above the request so it
 * says what is asked while the rest scrolls, and the request itself, the
 * title's other rows, the locations, then the arguments, two cells in.
 */
export function requestRows(
  wait: PermissionWait,
  width: number,
  titleWidth = width,
): { readonly pinned: string; readonly rows: readonly RequestRow[] } {
  const wrapped = (text: string, room: number) =>
    text.split('\n').flatMap((line) => wrapLine(line, room));
  const [pinned = '', ...title] = wrapped(
    wait.title ?? 'Tool call',
    Math.max(titleWidth, 1),
  );

  return {
    pinned,
    rows: [
      ...title.map((text) => ({ text, kind: 'title' as const })),
      ...locationsShown(wait).flatMap((path) =>
        wrapped(path, width).map((text) => ({
          text,
          kind: 'location' as const,
        })),
      ),
      ...inputLines(wait).flatMap((line) =>
        wrapped(line, Math.max(width - INPUT_INDENT, 1)).map((text) => ({
          text,
          kind: 'input' as const,
        })),
      ),
    ],
  };
}

/**
 * The room a box was laid out to: its height once laid out, else `room`,
 * as read before. Yoga gives a box not laid out yet a height of `NaN`.
 */
export function laidRoom(height: number | undefined, room: number): number {
  return height !== undefined && Number.isFinite(height) ? height : room;
}

/**
 * What the request's room shows from row `top` of `total`: the rows it
 * shows and whether the `↑` and `↓` rules are drawn, each taking a row of
 * the room. The top view shows its first `room − 1` rows over the `↓`
 * rule, the end view the `↑` rule over its last `room − 1`, and a view
 * between them both rules round `room − 2`. A room of two rows has one
 * rule, `↓` while rows are below, else `↑`; a room of one row, none.
 * `top` is clamped to the views there are. A room not yet laid out, `NaN`
 * as Yoga gives it, shows it all, as a room not yet read does.
 */
export function requestView(
  total: number,
  room: number,
  top: number,
): {
  readonly top: number;
  readonly shown: number;
  readonly above: boolean;
  readonly below: boolean;
} {
  if (total <= room || Number.isNaN(room)) {
    return { top: 0, shown: total, above: false, below: false };
  }

  if (room <= 2) {
    const shown = Math.max(room, 0) === 0 ? 0 : 1;
    const at = Math.min(Math.max(top, 0), total - Math.max(shown, 1));
    const below = room === 2 && at < total - 1;

    return { top: at, shown, above: room === 2 && !below, below };
  }

  const end = total - (room - 1);

  if (top <= 0) {
    return { top: 0, shown: room - 1, above: false, below: true };
  }

  return top >= end
    ? { top: end, shown: room - 1, above: true, below: false }
    : { top, shown: room - 2, above: true, below: true };
}

/**
 * The top a scroll key leaves the request at. A page down starts at the
 * row after the last one shown; a page up ends at the row before the first
 * one shown, on a view of `room − 2` rows, or goes to the top view when that
 * reaches the row already, so no row is passed over. In a room of one row
 * a page is a row; home and end still jump (docs/design/CHD-246.md).
 */
export function requestStep(
  step: ScrollStep,
  total: number,
  room: number,
  top: number,
): number {
  const view = requestView(total, room, top);
  const to = (next: number) => requestView(total, room, next).top;

  if (room === 1 && step !== 'top' && step !== 'bottom') {
    return to(
      view.top + (step === 'page_down' || step === 'line_down' ? 1 : -1),
    );
  }

  switch (step) {
    case 'page_down':
      return to(view.top + view.shown);
    case 'page_up': {
      const between = Math.max(room - 2, 1);

      return room >= 3 && view.top - 1 <= room - 2 ? 0 : to(view.top - between);
    }
    case 'line_down':
      return to(view.top + 1);
    case 'line_up':
      return to(view.top - 1);
    case 'top':
      return 0;
    case 'bottom':
      return to(total);
  }
}

/**
 * The request's rows above and below its view, `view` rows from row `top`
 * of `total`; none where nothing is hidden.
 */
export function hiddenRows(
  total: number,
  top: number,
  view: number,
): { readonly above: number; readonly below: number } {
  return {
    above: Math.max(0, top),
    below: Math.max(0, total - top - Math.max(view, 0)),
  };
}

/**
 * How much of the request a room of one row leaves out of view, said on the
 * pinned title row, as that room has none for a rule: no key, as the row
 * has no room for one either.
 */
export function requestCount({
  above,
  below,
}: {
  readonly above: number;
  readonly below: number;
}): string {
  const lines = (count: number) => `${count} ${count === 1 ? 'line' : 'lines'}`;

  return above === 0
    ? `↓ ${lines(below)} below`
    : below === 0
      ? `↑ ${lines(above)} above`
      : `↑ ${above} above · ↓ ${below} below`;
}

/**
 * The cells the widest count a request of about `total` rows can say takes,
 * with room for the rows a narrower title adds: what a one-row room leaves
 * the title beside it, the same however far it is scrolled, so the title's
 * rows, and every row under them, stay where they are as the count changes.
 */
export function countRoom(total: number): number {
  const most = 10 ** String(total * 2).length - 1;

  return stringWidth(requestCount({ above: most, below: most }));
}

const RULE = '─';

/**
 * A dim rule row saying how much of the request is out of view, `↑` above
 * or `↓` below, and the key that scrolls to it when one is bound, drawn to
 * `width` cells as the transcript's rule is.
 */
export function requestRule(
  way: '↑' | '↓',
  count: number,
  key: string | undefined,
  width: number,
): string {
  const words = `${way} ${count} ${count === 1 ? 'line' : 'lines'} ${
    way === '↑' ? 'above' : 'below'
  }`;
  const whole = `${RULE}${RULE} ${words}${
    key === undefined ? '' : ` · ${key} to scroll`
  } `;
  const text = stringWidth(whole) < width ? whole : `${RULE}${RULE} ${words} `;

  return text + RULE.repeat(Math.max(0, width - stringWidth(text)));
}
