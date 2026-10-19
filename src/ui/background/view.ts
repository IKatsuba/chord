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
import { endWord, timeoutWords } from '../../session/monitors.ts';
import type { BackgroundGroup, BackgroundItem } from './background.ts';

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

/** ↑ ↓: the item `by` rows from the focused one, stopping at either end. */
export function moveViewFocus(
  items: readonly BackgroundItem[],
  focus: ItemRef | undefined,
  by: number,
): ItemRef | undefined {
  const at = Math.max(0, items.indexOf(focusedItem(items, focus)!));
  const next = items[Math.min(Math.max(0, at + by), items.length - 1)];

  return next && { key: next.key, id: next.id };
}

/** The hint line on an agent item whose agent offers no stop of its own. */
export const NO_STOP_HINT = 'this agent offers no stop';

/** The hint line on a stop that could not be sent: its error's first line. */
export function stopRefused(error: unknown): string {
  const message = error instanceof Error ? error.message : String(error);

  return `could not stop: ${message.split('\n')[0]}`;
}

/** A name's column at most; a longer name wraps inside it. */
export const NAME_CELLS = 24;

const GAP = '  ';

/** What one way of fitting keeps, as the columns give way. */
interface Fit {
  /** A monitor's ` · N events` after its end. */
  readonly endedEvents: boolean;
  /** A task's model, then its runtime, after `task`. */
  readonly model: boolean;
  readonly runtime: boolean;
}

/** The fullest first: an end's events go, then a task's model, its runtime. */
const FITS: readonly Fit[] = [
  { endedEvents: true, model: true, runtime: true },
  { endedEvents: false, model: true, runtime: true },
  { endedEvents: false, model: false, runtime: true },
  { endedEvents: false, model: false, runtime: false },
];

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
  { endedEvents = true }: { readonly endedEvents?: boolean } = {},
): { readonly text: string; readonly group: BackgroundGroup } {
  const { status } = item;
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
      const tail = endedEvents ? events : '';

      if (status.group === 'stopped') {
        return {
          text: `■ ${status.word ?? 'stopped'} after ${ran}${tail}`,
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
          ? { text: `✓ reported after ${ran}`, group: 'done' }
          : { text: `✗ failed after ${ran}`, group: 'failed' };
      }

      const glyph = status.group === 'done' ? '✓' : '✗';
      const word =
        status.end === undefined ? status.group : endWord(status.end);

      return {
        text: `${glyph} ${word} after ${ran}${tail}`,
        group: status.group,
      };
    }
  }
}

/** An item's kind as its row says it: a task's with its runtime and model. */
function kindText(item: BackgroundItem, fit: Fit): string {
  return [
    item.kind,
    fit.runtime ? item.runtime : undefined,
    fit.runtime && fit.model ? item.model : undefined,
  ]
    .filter((part) => part !== undefined)
    .join(' · ');
}

/** A run of a row's line, by what it is, which its colour follows. */
export interface ViewCell {
  readonly text: string;
  readonly role: 'mark' | 'edge' | 'name' | 'kind' | 'state' | 'owner' | 'gap';
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
 * cells apart, giving way as `FITS` says; past the last, the state and the
 * owner go under the name, so nothing is cut.
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

  for (const fit of FITS) {
    const kinds = items.map((item) => kindText(item, fit));
    const states = items.map((item) =>
      stateText(item, now, { endedEvents: fit.endedEvents }),
    );
    const kindWidth = widest(kinds);
    const stateWidth = widest(states.map(({ text }) => text));
    const total =
      2 +
      nameWidth +
      GAP.length +
      kindWidth +
      GAP.length +
      stateWidth +
      GAP.length +
      ownerWidth;

    if (total > width && fit !== FITS[FITS.length - 1]) {
      continue;
    }

    if (total > width) {
      return stackedRows(items, {
        names,
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
      const state = states[index]!;

      return {
        item,
        focused: item === focused,
        lines: nameLines.map((line, at): ViewCell[] =>
          at === 0
            ? [
                mark(item),
                { text: pad(line, nameWidth), role: 'name' },
                { text: GAP, role: 'gap' },
                { text: pad(kinds[index]!, kindWidth), role: 'kind' },
                { text: GAP, role: 'gap' },
                {
                  text: pad(state.text, stateWidth),
                  role: 'state',
                  group: state.group,
                },
                { text: GAP, role: 'gap' },
                { text: owners[index]!, role: 'owner' },
              ]
            : [
                { text: '    ', role: 'gap' },
                { text: line, role: 'name' },
              ],
        ),
      };
    });
  }

  return [];
}

/** What every line of a row after its first starts with: under the name, two in. */
const UNDER: ViewCell = { text: '    ', role: 'gap' };

/**
 * Rows too wide for one line, two lines each: the name with its kind, its
 * parts giving way as `FITS` says, then the state and the owner, every line
 * after the first two cells further in than the name, so each name alone is
 * at the left edge. Where a name and even a bare kind do not fit, the kind
 * goes to a line of its own; a part longer than a line wraps, never cut. The
 * `❯` is the caller's, ahead of the first line.
 */
function stackedRows(
  items: readonly BackgroundItem[],
  {
    names,
    states,
    owners,
    nameWidth,
    width,
  }: {
    readonly names: readonly string[];
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
  // The fullest kinds that fit beside the names on every row.
  const kinds = FITS.map((fit) =>
    items.map((item) => kindText(item, fit)),
  ).find((each) => 2 + nameWidth + GAP.length + widest(each) <= width);
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
        ? under(kindText(item, FITS[FITS.length - 1]!), 'kind')
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

/** The rows in sight, and how many are out of it above and below. */
export interface ViewWindow {
  readonly rows: readonly ViewRow[];
  readonly above: number;
  readonly below: number;
}

/**
 * The rows that fit `height` lines with the `❯`'s in sight: from the top
 * while it is, else scrolled just far enough. What is out of sight is said
 * in the gutter, as the pickers say it (`edgeMarked`), so it takes no line.
 */
export function viewWindow(
  rows: readonly ViewRow[],
  height: number,
): ViewWindow {
  const lines = (row: ViewRow) => row.lines.length;
  const focused = Math.max(
    0,
    rows.findIndex((row) => row.focused),
  );

  for (let start = 0; start <= focused; start++) {
    let room = height;
    let end = start;

    while (end < rows.length && lines(rows[end]!) <= room) {
      room -= lines(rows[end]!);
      end += 1;
    }

    if (focused < end || start === focused) {
      const shown = rows.slice(start, Math.max(end, start + 1));

      return {
        rows: shown,
        above: start,
        below: rows.length - start - shown.length,
      };
    }
  }

  return { rows, above: 0, below: 0 };
}

/** A line in sight, with the row it is of. */
export interface ViewLine {
  readonly row: ViewRow;
  readonly cells: ViewCell[];
}

/**
 * The lines in sight, the pickers' `↑` on the first where rows are out of
 * sight above and `↓` on the last where rows are below, in the gutter the
 * `❯` stands in, which keeps its place (CHD-462).
 */
export function edgeMarked(shown: ViewWindow): ViewLine[] {
  const lines = shown.rows.flatMap((row) =>
    row.lines.map((line) => ({ row, cells: [...line] })),
  );
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

  if (shown.above > 0) {
    mark(lines[0], '↑ ');
  }

  if (shown.below > 0) {
    mark(lines.at(-1), '↓ ');
  }

  return lines;
}
