/**
 * The background view, kept out of its component: a row per item with its
 * name, kind, state with time and owner, the name wrapping inside its column,
 * the columns giving way at a narrow width and nothing cut; which rows are in
 * sight around the `❯`; and where ↑ ↓ move it (CHD-424).
 */
import stringWidth from 'string-width';
import stripAnsi from 'strip-ansi';
import wrapAnsi from 'wrap-ansi';
import { formatElapsed } from '../../session/elapsed.ts';
import { endSentence, endWord, timeoutWords } from '../../session/monitors.ts';
import { spentParts } from '../transcript/agents/subagents.ts';
import { wrapLine } from '../transcript/message.ts';
import {
  type BackgroundGroup,
  type BackgroundItem,
  leavesList,
} from './background.ts';

/** An item by its owner's session and its id there. */
export interface ItemRef {
  readonly key: number;
  readonly id: string;
}

export function sameItem(item: BackgroundItem, ref: ItemRef): boolean {
  return item.key === ref.key && item.id === ref.id;
}

/** The item with the `❯`: the one `focus` names, else the first. */
export function focusedItem(
  items: readonly BackgroundItem[],
  focus: ItemRef | undefined,
): BackgroundItem | undefined {
  return (focus && items.find((item) => sameItem(item, focus))) ?? items[0];
}

/**
 * Where the `❯` goes once `focus`'s row has left `before`, the rows now
 * being `items`: to the row that took its place, or the one above when it
 * was the last; none while its row is still listed, or with no row left
 * (docs/design/CHD-479.md).
 */
export function focusAfter(
  before: readonly BackgroundItem[],
  items: readonly BackgroundItem[],
  focus: ItemRef | undefined,
): ItemRef | undefined {
  if (
    focus === undefined ||
    items.length === 0 ||
    items.some((item) => sameItem(item, focus))
  ) {
    return undefined;
  }

  const was = before.findIndex((item) => sameItem(item, focus));

  if (was === -1) {
    return undefined;
  }

  // The rows above it that are still listed, the first after them being
  // the one that took its place.
  const above = before
    .slice(0, was)
    .filter((item) => items.some((each) => sameItem(each, item))).length;
  const next = items[Math.min(above, items.length - 1)]!;

  return { key: next.key, id: next.id };
}

/**
 * Where ↑ ↓ (`by`) take an open detail on `detail` over `items`: the
 * item `by` on, whole items, not lines, as a page key scrolls a tall one;
 * at an end, nowhere, unless its item has ended and leaves once left, when
 * it goes to the item that takes its place under CHD-479's rule, or, none
 * left, `closed` (docs/design/CHD-481.md, Q126).
 */
export function stepDetail(
  items: readonly BackgroundItem[],
  detail: ItemRef,
  by: 1 | -1,
): ItemRef | 'closed' | undefined {
  const at = items.findIndex((item) => sameItem(item, detail));
  const item = items[at];
  const next = at === -1 ? undefined : items[at + by];

  if (next !== undefined) {
    return { key: next.key, id: next.id };
  }

  if (item === undefined || !leavesList(item)) {
    return undefined;
  }

  return (
    focusAfter(
      items,
      items.filter((each) => each !== item),
      detail,
    ) ?? 'closed'
  );
}

/** The hint line on an agent item whose agent offers no stop of its own. */
export const NO_STOP_HINT = 'this agent offers no stop';

/**
 * What the frame says of a stop that could not be sent: its error whole,
 * every line of it (CHD-462 f929ae37).
 */
export function stopRefused(error: unknown): string {
  const message = error instanceof Error ? error.message : String(error);

  return `could not stop: ${message}`;
}

/** A name's column at most; a longer name wraps inside it. */
export const NAME_CELLS = 24;

const GAP = '  ';

/** `no events`, `1 event`, `3 events`. */
function eventsWords(events: number): string {
  return events === 0
    ? 'no events'
    : `${events} ${events === 1 ? 'event' : 'events'}`;
}

/** How long, as an end says it: `3m`, `3m 12s`. */
function after(ms: number): string {
  return timeoutWords(Math.max(0, ms));
}

/** An item's state with its time, in its group's colour. */
export function stateText(
  item: BackgroundItem,
  now: number,
): { readonly text: string; readonly group: BackgroundGroup } {
  const { status } = item;
  // An ended task's money, after its state (CHD-373).
  const money = item.kind === 'task' ? spentParts(item.spent).money : undefined;
  const paid = money === undefined ? '' : ` · ${money}`;
  const events =
    item.events === undefined ? '' : ` · ${eventsWords(item.events)}`;

  switch (status.group) {
    case 'running': {
      const ran = formatElapsed(now - item.startedAt);

      return {
        text:
          item.kind === 'monitor'
            ? `running ${ran}${events}`
            : item.kind === 'agent'
              ? status.stopping
                ? `■ stopping ${ran}`
                : `running ${ran}`
              : `working ${ran}`,
        group: 'running',
      };
    }
    case 'untracked':
      return {
        text: `? untracked ${formatElapsed(status.endedAt - item.startedAt)}`,
        group: 'untracked',
      };
    case 'asking':
      return {
        text: `● ${status.on} ${formatElapsed(now - status.since)}`,
        group: 'asking',
      };
    default: {
      const ran = after(status.endedAt - item.startedAt);

      if (status.group === 'stopped') {
        // A monitor's timeout is a stop in its own words (CHD-482's Q85).
        const word =
          status.word ??
          (status.end === undefined ? 'stopped' : endWord(status.end));

        return {
          text: `■ ${word} after ${ran}${events}${paid}`,
          group: 'stopped',
        };
      }

      if (item.kind === 'agent') {
        return status.group === 'done'
          ? { text: `✓ done in ${ran}`, group: 'done' }
          : {
              text: `✗ ${status.word ?? 'failed'} after ${ran}`,
              group: 'failed',
            };
      }

      if (item.kind === 'task') {
        return status.group === 'done'
          ? { text: `✓ reported after ${ran}${paid}`, group: 'done' }
          : { text: `✗ failed after ${ran}${paid}`, group: 'failed' };
      }

      const glyph = status.group === 'done' ? '✓' : '✗';
      const word =
        status.end === undefined ? status.group : endWord(status.end);

      return {
        text: `${glyph} ${word} after ${ran}${events}`,
        group: status.group,
      };
    }
  }
}

/** `text` on one line: every run of whitespace one space, as a title is shown. */
function oneLine(text: string): string {
  return text.replace(/\s+/g, ' ').trim();
}

/**
 * An item's kind as its row says it: a monitor's with its id, which tells
 * monitors of one description apart and names it as its messages do
 * (CHD-481); a task's with its runtime and model; each on one line, as the
 * row is laid out by the lines it makes itself.
 */
function kindText(item: BackgroundItem): string {
  return [
    item.kind,
    item.kind === 'monitor' ? item.id : undefined,
    item.runtime,
    item.model,
  ]
    .filter((part) => part !== undefined)
    .map(oneLine)
    .join(' · ');
}

/**
 * A kind in lines of at most `width` cells: broken after a ` · `, the `·`
 * ending the line, or starting the next where even it does not fit; a part
 * wider than a line wraps at its spaces (CHD-473).
 */
function kindIn(kind: string, width: number): string[] {
  const lines: string[] = [];

  for (const part of kind.split(' · ')) {
    const last = lines.at(-1);

    if (last === undefined) {
      lines.push(...wrapped(part, width));
    } else if (stringWidth(`${last} · ${part}`) <= width) {
      lines[lines.length - 1] = `${last} · ${part}`;
    } else if (stringWidth(`${last} ·`) <= width) {
      lines[lines.length - 1] = `${last} ·`;

      lines.push(...wrapped(part, width));
    } else {
      lines.push(...wrapped(`· ${part}`, width));
    }
  }

  return lines;
}

/**
 * The frame's hint, or an error in its place, in lines of at most `width`
 * cells: its own line breaks kept, each line broken after a ` · ` and at
 * its spaces, never cut (CHD-473, CHD-462 3a1cf656, f929ae37).
 */
export function hintLines(text: string, width: number): string[] {
  // An error's own line breaks stay lines; within each, a tab is a space.
  return text
    .split(/\r\n|\r|\n/)
    .flatMap((line) => kindIn(oneLine(line), Math.max(1, width)));
}

/** The least a state's column holds: its widest word, with a `·` beside it. */
function stateLeast(states: readonly string[]): number {
  return Math.max(
    0,
    ...states.flatMap((state) =>
      state.split(' ').map((word) => stringWidth(word) + 2),
    ),
  );
}

/**
 * The least a kind's column holds: its widest part with a `·` beside it,
 * after it or, where the line before is full, ahead of it, so a part never
 * breaks inside itself there.
 */
function kindLeast(kinds: readonly string[]): number {
  return Math.max(
    0,
    ...kinds.flatMap((kind) => {
      const parts = kind.split(' · ');

      return parts.map(
        (part) => stringWidth(part) + (parts.length > 1 ? 2 : 0),
      );
    }),
  );
}

/** A run of a row's line, by what it is, which its colour follows. */
export interface ViewCell {
  readonly text: string;
  readonly role:
    | 'mark'
    | 'edge'
    | 'name'
    | 'kind'
    | 'state'
    | 'owner'
    | 'gap'
    /** A detail's command or event, in the text's colour (CHD-481). */
    | 'text';
  /** A state's group, for its colour. */
  readonly group?: BackgroundGroup;
}

/** One item's row, on as many lines as its name or a narrow width takes. */
export interface ViewRow {
  readonly item: BackgroundItem;
  readonly focused: boolean;
  readonly lines: readonly (readonly ViewCell[])[];
}

/** `main`, or the child's or member's name. */
function ownerText(item: BackgroundItem): string {
  return item.owner?.name ?? 'main';
}

function pad(text: string, width: number): string {
  return text + ' '.repeat(Math.max(0, width - stringWidth(text)));
}

/** `text` in lines of at most `width` cells, broken between words. */
function wrapped(text: string, width: number): string[] {
  return wrapAnsi(text, Math.max(1, width), { hard: true, trim: true }).split(
    '\n',
  );
}

/**
 * A name in its column: whole on one line where it fits, else wrapped two
 * cells short of the column, as every line after the first is drawn two
 * cells in, so a wrapped name reads as one and stays inside its column.
 */
function nameIn(name: string, width: number): string[] {
  return stringWidth(name) <= width && !name.includes('\n')
    ? [name]
    : wrapped(name, Math.max(1, width - 2));
}

/**
 * Every item's row in `width` cells: the columns padded to their widest, two
 * cells apart, and nothing gives way (CHD-473). Where they do not fit the
 * kind wraps in its column, after a ` · `, then the state in its own, and
 * the row grows a line; where even the kind's widest part or the state's
 * widest word does not fit, the state and the owner go under the name, so
 * nothing is cut.
 */
export function viewRows(
  items: readonly BackgroundItem[],
  {
    width,
    focus,
    now,
  }: {
    readonly width: number;
    readonly focus: ItemRef | undefined;
    readonly now: number;
  },
): ViewRow[] {
  const focused = focusedItem(items, focus);
  // An agent's string, cleaned: OpenTUI's text would draw its escapes.
  const names = items.map((item) => stripAnsi(item.name));
  const widest = (texts: readonly string[]) =>
    Math.max(0, ...texts.map((text) => stringWidth(text)));
  const nameWidth = Math.min(NAME_CELLS, widest(names));
  const owners = items.map(ownerText);
  const ownerWidth = widest(owners);
  const mark = (item: BackgroundItem): ViewCell => ({
    text: item === focused ? '❯ ' : '  ',
    role: 'mark',
  });
  const kinds = items.map(kindText);
  // A state's words on one line too: an agent's end word is its own.
  const states = items.map((item) => {
    const state = stateText(item, now);

    return { ...state, text: oneLine(state.text) };
  });

  const fullKind = widest(kinds);
  const fullState = widest(states.map(({ text }) => text));
  // What the kind and the state share, the name and owner columns kept.
  const room = width - (2 + nameWidth + GAP.length * 3 + ownerWidth);
  // The kind first: as narrow as it goes with no line of it starting with
  // a `·`, or as the state leaves it; then the state, in what is left.
  const neat = Array.from(
    { length: Math.max(0, fullKind - kindLeast(kinds) + 1) },
    (_, at) => kindLeast(kinds) + at,
  ).find((each) =>
    kinds.every((kind) =>
      kindIn(kind, each).every((line, at) => at === 0 || !line.startsWith('·')),
    ),
  );
  const kindWidth =
    fullKind + fullState <= room
      ? fullKind
      : Math.max(
          Math.min(fullKind, room - fullState),
          neat ?? kindLeast(kinds),
        );
  const stateWidth = Math.min(fullState, room - kindWidth);

  // Not even the kind's widest part, or the state's widest word, fits in
  // its column: the state and owner go under the name.
  if (
    kindWidth < kindLeast(kinds) ||
    stateWidth < stateLeast(states.map(({ text }) => text))
  ) {
    return stackedRows(items, {
      names,
      kinds,
      states,
      owners,
      nameWidth,
      width,
    }).map((lines, index) => ({
      item: items[index]!,
      focused: items[index] === focused,
      lines: [[mark(items[index]!), ...lines[0]!], ...lines.slice(1)],
    }));
  }

  return items.map((item, index) => {
    const nameLines = nameIn(names[index]!, nameWidth);
    const kindLines = kindIn(kinds[index]!, kindWidth);
    const state = states[index]!;
    const stateLines = kindIn(state.text, stateWidth);

    return {
      item,
      focused: item === focused,
      lines: Array.from(
        {
          length: Math.max(
            nameLines.length,
            kindLines.length,
            stateLines.length,
          ),
        },
        (_, at): ViewCell[] => {
          const name = nameLines[at] ?? '';
          const kind = kindLines[at];
          const said = stateLines[at];

          if (at === 0) {
            return [
              mark(item),
              { text: pad(name, nameWidth), role: 'name' },
              { text: GAP, role: 'gap' },
              { text: pad(kind ?? '', kindWidth), role: 'kind' },
              { text: GAP, role: 'gap' },
              {
                text: pad(said ?? '', stateWidth),
                role: 'state',
                group: state.group,
              },
              { text: GAP, role: 'gap' },
              { text: owners[index]!, role: 'owner' },
            ];
          }

          // Under the name two in, the kind's and the state's next lines in
          // their columns.
          return kind === undefined && said === undefined
            ? [UNDER, { text: name, role: 'name' }]
            : [
                UNDER,
                { text: pad(name, nameWidth - 2), role: 'name' },
                { text: GAP, role: 'gap' },
                { text: pad(kind ?? '', kindWidth), role: 'kind' },
                ...(said === undefined
                  ? []
                  : [
                      { text: GAP, role: 'gap' as const },
                      {
                        text: said,
                        role: 'state' as const,
                        group: state.group,
                      },
                    ]),
              ];
        },
      ),
    };
  });
}

/** What every line of a row after its first starts with: under the name, two in. */
const UNDER: ViewCell = { text: '    ', role: 'gap' };

/**
 * Rows too wide for one line, two lines each: the name with its kind, then
 * the state and the owner, every line after the first two cells further in
 * than the name, so each name alone is at the left edge. Where a name and
 * its kind do not fit, the kind goes to lines of its own, wrapped after a
 * ` · `; a part longer than a line wraps, never cut. The `❯` is the
 * caller's, ahead of the first line.
 */
function stackedRows(
  items: readonly BackgroundItem[],
  {
    names,
    kinds: full,
    states,
    owners,
    nameWidth,
    width,
  }: {
    readonly names: readonly string[];
    readonly kinds: readonly string[];
    readonly states: readonly {
      readonly text: string;
      readonly group: BackgroundGroup;
    }[];
    readonly owners: readonly string[];
    readonly nameWidth: number;
    readonly width: number;
  },
): ViewCell[][][] {
  const room = Math.max(1, width - UNDER.text.length);
  const widest = (texts: readonly string[]) =>
    Math.max(0, ...texts.map((text) => stringWidth(text)));
  // The kinds beside the names where every one fits there.
  const kinds =
    2 + nameWidth + GAP.length + widest(full) <= width ? full : undefined;
  const kindWidth = kinds === undefined ? 0 : widest(kinds);
  const under = (
    text: string,
    role: ViewCell['role'],
    group?: BackgroundGroup,
  ) =>
    wrapped(text, room).map((line): ViewCell[] => [
      UNDER,
      { text: line, role, ...(group === undefined ? {} : { group }) },
    ]);

  return items.map((item, index) => {
    const state = states[index]!;
    const owner = owners[index]!;
    const nameLines = nameIn(names[index]!, Math.min(nameWidth, width - 2));
    const first: ViewCell[] =
      kinds === undefined
        ? [{ text: nameLines[0]!, role: 'name' }]
        : [
            { text: pad(nameLines[0]!, nameWidth), role: 'name' },
            { text: GAP, role: 'gap' },
            { text: pad(kinds[index]!, kindWidth), role: 'kind' },
          ];
    const together =
      stringWidth(state.text) + GAP.length + stringWidth(owner) <= room;

    return [
      first,
      ...nameLines
        .slice(1)
        .map((line): ViewCell[] => [UNDER, { text: line, role: 'name' }]),
      ...(kinds === undefined
        ? kindIn(full[index]!, room).map((line): ViewCell[] => [
            UNDER,
            { text: line, role: 'kind' },
          ])
        : []),
      ...(together
        ? [
            [
              UNDER,
              { text: state.text, role: 'state', group: state.group },
              { text: GAP, role: 'gap' },
              { text: owner, role: 'owner' },
            ] satisfies ViewCell[],
          ]
        : [
            ...under(state.text, 'state', state.group),
            ...under(owner, 'owner'),
          ]),
    ];
  });
}

/**
 * The lines in sight: the rows they are of, how many rows are wholly out of
 * sight above and below, and which of those rows' lines are shown, `height`
 * of them from `from`, the frame keeping its height while it is open
 * (CHD-462, CHD-430).
 */
export interface ViewWindow {
  readonly rows: readonly ViewRow[];
  readonly above: number;
  readonly below: number;
  readonly from: number;
  readonly height: number;
}

/**
 * Where the frame is: the item with the `❯`, and the line of all the rows'
 * on top, for the size it was laid out at; at another size the window is
 * found again from the `❯`, a tall row from its first line (CHD-430).
 */
export interface ViewAt {
  readonly focus?: ItemRef;
  readonly top?: number;
  readonly laid?: string;
}

/** The size the rows' lines were laid out at, which a line on top is of. */
export function laidAt(width: number, height: number): string {
  return `${width}x${height}`;
}

/** Each row's first line among all the rows' lines, and how many there are. */
function lineStarts(rows: readonly ViewRow[]): {
  starts: number[];
  total: number;
} {
  const starts: number[] = [];
  let total = 0;

  for (const row of rows) {
    starts.push(total);

    total += row.lines.length;
  }

  return { starts, total };
}

/**
 * The line on top: `at`'s where it was laid out at this size, else the
 * first that shows the `❯`'s row, from its first line if it is taller than
 * the frame; moved only as far as keeps that row in sight.
 */
function topOf(
  rows: readonly ViewRow[],
  limit: number,
  at: ViewAt | undefined,
  laid: string | undefined,
): { top: number; height: number } {
  const { starts, total } = lineStarts(rows);
  const height = Math.min(total, limit);
  const focused = Math.max(
    0,
    rows.findIndex((row) => row.focused),
  );
  const first = starts[focused] ?? 0;
  const end = first + (rows[focused]?.lines.length ?? 0);
  const tall = end - first > height;
  const kept = laid !== undefined && at?.laid === laid ? at.top : undefined;
  let top = kept ?? (tall ? first : Math.max(0, end - height));

  if (tall) {
    top = Math.min(Math.max(top, first), end - height);
  } else {
    top = Math.min(top, first);
    top = Math.max(top, end - height);
  }

  return { top: Math.min(Math.max(0, top), total - height), height };
}

/**
 * The lines that fit `limit` with the `❯`'s row in sight, or as much of it
 * as fits where it is taller, from the line on top `at` keeps.
 */
export function viewWindow(
  rows: readonly ViewRow[],
  limit: number,
  at?: ViewAt,
  laid?: string,
): ViewWindow {
  const { starts } = lineStarts(rows);
  const { top, height } = topOf(rows, limit, at, laid);
  const inSight = (index: number) =>
    starts[index]! < top + height &&
    starts[index]! + rows[index]!.lines.length > top;
  const firstIn = rows.findIndex((_, index) => inSight(index));
  const first = firstIn < 0 ? 0 : firstIn;
  let end = first;

  while (end < rows.length && inSight(end)) {
    end += 1;
  }

  return {
    rows: rows.slice(first, end),
    above: first,
    below: rows.length - end,
    from: top - (starts[first] ?? 0),
    height,
  };
}

/**
 * ↑ ↓ in the frame: through the lines of a focused row taller than it first,
 * a line at a time, then to the next row, scrolling only as far as brings
 * that row whole into sight; a tall row reached with ↓ shows from its first
 * line, and with ↑ from its last. Undefined with nothing listed.
 */
export function moveView(
  items: readonly BackgroundItem[],
  at: ViewAt | undefined,
  by: 1 | -1,
  { width, height, now }: { width: number; height: number; now: number },
): ViewAt | undefined {
  const laid = laidAt(width, height);
  const rows = viewRows(items, { width, focus: at?.focus, now });
  const index = rows.findIndex((row) => row.focused);
  const row = rows[index];

  if (row === undefined) {
    return undefined;
  }

  const { starts } = lineStarts(rows);
  const { top, height: shown } = topOf(rows, height, at, laid);
  const ref = (of: ViewRow) => ({ key: of.item.key, id: of.item.id });
  const first = starts[index]!;
  const end = first + row.lines.length;

  if (row.lines.length > shown) {
    if ((by > 0 && top + shown < end) || (by < 0 && top > first)) {
      return { focus: ref(row), top: top + by, laid };
    }
  }

  const next = rows[index + by];

  if (next === undefined) {
    return { focus: ref(row), top, laid };
  }

  const nextFirst = starts[index + by]!;
  const nextEnd = nextFirst + next.lines.length;
  const nextTop =
    next.lines.length > shown
      ? by > 0
        ? nextFirst
        : nextEnd - shown
      : nextFirst < top
        ? nextFirst
        : nextEnd > top + shown
          ? nextEnd - shown
          : top;

  return { focus: ref(next), top: nextTop, laid };
}

/** A line in sight, with the row it is of. */
export interface ViewLine {
  readonly row: ViewRow;
  readonly cells: ViewCell[];
}

/**
 * The lines in sight, the pickers' `↑` on the first where anything is out
 * of sight above and `↓` on the last where anything is below, in the gutter
 * the `❯` stands in, which keeps its place (CHD-462, CHD-430).
 */
export function edgeMarked(shown: ViewWindow): ViewLine[] {
  const all = shown.rows.flatMap((row) =>
    row.lines.map((line) => ({ row, cells: [...line] })),
  );
  const lines = all.slice(shown.from, shown.from + shown.height);
  const above = shown.above > 0 || shown.from > 0;
  const below = shown.below > 0 || shown.from + shown.height < all.length;
  const mark = (line: ViewLine | undefined, edge: string) => {
    const [first, ...rest] = line?.cells ?? [];

    if (
      line === undefined ||
      first === undefined ||
      first.text.startsWith('❯')
    ) {
      return;
    }

    line.cells.splice(
      0,
      line.cells.length,
      { text: edge, role: 'edge' },
      { ...first, text: first.text.slice(edge.length) },
      ...rest,
    );
  };

  if (above) {
    mark(lines[0], '↑ ');
  }

  if (below) {
    mark(lines.at(-1), '↓ ');
  }

  return lines;
}

/**
 * How long ago, as the agents list says it, to the minute once past one:
 * `16m`, `3h 46m`, `41s` (CHD-481).
 */
function agoWords(ms: number): string {
  const words = formatElapsed(Math.max(0, ms)).split(' ');

  return (
    words.length > 1 ? words.filter((word) => !word.endsWith('s')) : words
  ).join(' ');
}

/**
 * `parts` joined by ` · ` in lines of at most `width` cells, broken as a
 * kind is (`kindIn`), each run keeping its part's role and the `·`s dim.
 */
function dotted(parts: readonly ViewCell[], width: number): ViewCell[][] {
  // Every character of the joined line with the cell it came from; the
  // wrapped lines hold the same characters less the spaces broken at.
  const source: { readonly char: string; readonly of: ViewCell }[] = [];
  const gap: ViewCell = { text: ' · ', role: 'kind' };

  for (const [at, part] of parts.entries()) {
    for (const piece of at === 0 ? [part] : [gap, part]) {
      for (const char of piece.text) {
        source.push({ char, of: piece });
      }
    }
  }

  let next = 0;

  return kindIn(
    source.map(({ char }) => char).join(''),
    Math.max(1, width),
  ).map((line) => {
    const cells: ViewCell[] = [];

    for (const char of line) {
      while (next < source.length && source[next]!.char !== char) {
        next++;
      }

      const { of } = source[next++] ?? { of: gap };
      const last = cells.at(-1);

      if (last !== undefined && last.role === of.role) {
        cells[cells.length - 1] = { ...last, text: last.text + char };
      } else {
        cells.push({ ...of, text: char });
      }
    }

    return cells;
  });
}

/**
 * `text` wrapped after `first`, a two-cell lead such as `$ `, its later
 * lines two in under it; with no lead, at the whole width.
 */
function wrappedIn(
  first: string,
  text: string,
  width: number,
  role: ViewCell['role'],
): ViewCell[][] {
  const indent = first === '' ? '' : '  ';

  // Its own indent on its first line, as an event's is part of what it said,
  // as a monitor's message wraps it.
  return wrapLine(text, Math.max(1, width - stringWidth(indent))).map(
    (line, at) => [{ text: `${at === 0 ? first : indent}${line}`, role }],
  );
}

/**
 * The lines of `item`'s detail in the background frame, in its place of the
 * rows (docs/design/CHD-481.md): a monitor's description whole, its state
 * with its events, start, timeout and owner, its command, its last batch
 * with how long ago it came, and, ended, chord's sentence for its end; a
 * task's or agent's, its list row alone.
 */
export function detailLines(
  item: BackgroundItem,
  { width, now }: { readonly width: number; readonly now: number },
): ViewCell[][] {
  if (item.kind !== 'monitor') {
    return viewRows([item], { width, focus: undefined, now })
      .flatMap((row) => row.lines)
      .map((line) => line.filter((cell) => cell.role !== 'mark'));
  }

  const { events: _, ...bare } = item;
  const state = stateText(bare, now);
  const name = wrapAnsi(stripAnsi(item.name), Math.max(1, width), {
    hard: true,
  })
    .split('\n')
    .map((line): ViewCell[] => [{ text: line, role: 'name' }]);
  const facts = dotted(
    [
      // The row's state in its colour, its events after it dim.
      { text: oneLine(state.text), role: 'state', group: state.group },
      { text: eventsWords(item.events ?? 0), role: 'kind' },
      { text: `started ${agoWords(now - item.startedAt)} ago`, role: 'kind' },
      ...(item.timeoutMs === undefined
        ? []
        : [
            {
              text: `timeout ${timeoutWords(item.timeoutMs)}`,
              role: 'kind' as const,
            },
          ]),
      { text: ownerText(item), role: 'owner' },
    ],
    width,
  );
  const command =
    item.command === undefined
      ? []
      : wrappedIn('$ ', stripAnsi(item.command), width, 'text');
  const last = item.lastEvent;
  const event =
    last === undefined || last.lines.length === 0
      ? wrappedIn('← ', 'no events yet', width, 'text')
      : last.lines.flatMap((line, at) =>
          wrappedIn(
            at === 0 ? '← ' : '  ',
            `${stripAnsi(line)}${
              at === last.lines.length - 1
                ? ` · ${agoWords(now - last.at)} ago`
                : ''
            }`,
            width,
            'text',
          ),
        );
  const { status } = item;
  const end =
    'end' in status && status.end !== undefined
      ? wrappedIn(
          '',
          endSentence(status.end, status.endedAt - item.startedAt),
          width,
          'kind',
        )
      : [];

  return [...name, ...facts, ...command, ...event, ...end];
}
