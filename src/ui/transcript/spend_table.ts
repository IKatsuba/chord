/**
 * `/cost`'s table of what the window has spent, once it holds more than one
 * session: a row for each tab with its subtotal, then its own agent and
 * each agent under it, closed ones too, and the window's total, each with a
 * note in a long form, or a short one where the long does not fit (CHD-373
 * S4, CHD-378's C as settled for the build).
 */
import type { Cost } from '@agentclientprotocol/sdk';
import stringWidth from 'string-width';
import wrapAnsi from 'wrap-ansi';
import type { ReportRow } from '../../session/transcript/types.ts';
import { formatCost } from './reports.ts';
import { type Figure, type SpendPart, sum, type Summed } from './spend.ts';

/** A figure no part reported, in a cost or token column. */
const NONE = '—';

/** A note in its two forms: at 120 columns, and where that does not fit. */
interface Note {
  readonly long: string;
  readonly short: string;
}

/** A row before it is laid out: its name, figures and notes. */
interface Row {
  readonly name: string;
  readonly depth: number;
  readonly cost: string;
  readonly tokens: string;
  readonly notes: readonly Note[];
}

const TOKENS = new Intl.NumberFormat('en-US');

/** A day as `Oct 12`. */
const DAY = new Intl.DateTimeFormat('en-US', {
  month: 'short',
  day: 'numeric',
});

/** Whether the window holds more than one session, closed ones counted. */
export function manySessions(parts: readonly SpendPart[]): boolean {
  const count = (part: SpendPart): number =>
    (part.kind === 'tab' || part.kind === 'team' ? 0 : 1) +
    (part.parts ?? []).reduce((all, under) => all + count(under), 0);

  return parts.reduce((all, part) => all + count(part), 0) > 1;
}

/** `cost` as the table writes it: `~` ahead of chord's estimate. */
function costText(cost: Cost, estimated: boolean): string {
  return `${estimated ? '~' : ''}${formatCost(cost)}`;
}

/** What a figure says beside itself: whose estimate, older sums, turns left out. */
function figureNotes(figure: Figure | undefined): Note[] {
  const notes: Note[] = [];

  if (figure?.estimated === 'all') {
    const [model, ...more] = figure.models ?? [];

    notes.push({
      long:
        model !== undefined && more.length === 0
          ? `chord's estimate from ${model}'s price`
          : "chord's estimate from its models' prices",
      short: "chord's estimate",
    });
  } else if (figure?.estimated === 'part') {
    notes.push({ long: "part chord's estimate", short: 'part estimate' });
  }

  if (figure?.before !== undefined) {
    const until = figure.before.until;
    const day = until === undefined ? undefined : DAY.format(until);

    notes.push(
      day === undefined
        ? { long: 'as last reported', short: 'as last reported' }
        : { long: `as last reported before ${day}`, short: `before ${day}` },
    );
  }

  if (figure?.uncounted !== undefined && figure.uncounted > 0) {
    const turns = `${figure.uncounted} ${
      figure.uncounted === 1 ? 'turn' : 'turns'
    } not counted`;

    notes.push({ long: turns, short: turns });
  }

  return notes;
}

/** A session's or task's own row. */
function ownRow(
  name: string,
  depth: number,
  figure: Figure | undefined,
  kind: readonly Note[] = [],
): Row {
  return {
    name,
    depth,
    cost:
      figure?.cost === undefined
        ? 'not reported'
        : costText(figure.cost, figure.estimated !== undefined),
    tokens: figure?.tokens === undefined ? NONE : TOKENS.format(figure.tokens),
    notes: [...kind, ...figureNotes(figure)],
  };
}

/** A group's row: what is under it added up. */
function sumRow(
  name: string,
  depth: number,
  summed: Summed,
  notes: readonly Note[] = [],
): Row {
  return {
    name,
    depth,
    cost:
      summed.cost === undefined
        ? 'not reported'
        : costText(
            { amount: summed.cost, currency: 'USD' },
            summed.estimated !== 'none',
          ),
    tokens: summed.tokens === undefined ? NONE : TOKENS.format(summed.tokens),
    notes,
  };
}

/** A part with nothing under it: its own figure, as its row shows it. */
function alone(part: SpendPart): SpendPart {
  const { parts: _, ...own } = part;

  return own;
}

/**
 * A task agent's row, under the session that started it; `owner` names
 * that session where the row above is not it, as under a team run.
 */
function taskRows(task: SpendPart, depth: number, owner?: string): Row[] {
  const kind = owner === undefined ? 'task agent' : `task agent of ${owner}`;

  return [
    task.running === true
      ? {
          name: task.name,
          depth,
          cost: NONE,
          tokens: NONE,
          notes: [
            {
              long: `${kind}, running: counted when it ends`,
              short: 'running',
            },
          ],
        }
      : ownRow(task.name, depth, task.figure, [
          { long: `${kind}, ended`, short: 'ended' },
        ]),
    ...(task.parts ?? []).flatMap((under) => taskRows(under, depth + 1, owner)),
  ];
}

/** A session's row, its own spend, and its task agents' rows under it. */
function sessionRows(
  part: SpendPart,
  name: string,
  depth: number,
  kind: readonly Note[] = [],
): Row[] {
  return [
    ownRow(name, depth, part.figure, kind),
    ...(part.parts ?? []).flatMap((task) => taskRows(task, depth + 1)),
  ];
}

/**
 * A team run's rows: its lead and members added up, each named in the long
 * note, then the task agents they started, each with its owner.
 */
function teamRows(team: SpendPart, depth: number): Row[] {
  const members = team.parts ?? [];
  const each = members
    .map(
      (member) =>
        `${member.name} ${
          member.figure?.cost === undefined
            ? 'not reported'
            : costText(
                member.figure.cost,
                member.figure.estimated !== undefined,
              )
        }`,
    )
    .join(' · ');
  const ended = team.ended === true;

  return [
    sumRow(team.name, depth, sum(members.map(alone)), [
      {
        long: `team run${ended ? ', ended' : ''}: ${each}`,
        short: `team run of ${members.length}${ended ? ', ended' : ''}`,
      },
    ]),
    ...members.flatMap((member) =>
      (member.parts ?? []).flatMap((task) =>
        taskRows(task, depth + 1, member.name),
      ),
    ),
  ];
}

/** The rows of a long-lived agent, open or closed, or of a team run. */
function childRows(part: SpendPart, depth: number): Row[] {
  switch (part.kind) {
    case 'team':
      return teamRows(part, depth);
    case 'task':
      return taskRows(part, depth);
    default:
      return sessionRows(part, part.name, depth, [
        part.ended === true
          ? { long: 'agent, closed', short: 'closed' }
          : { long: 'agent', short: 'agent' },
      ]);
  }
}

/**
 * A tab's rows: one when its own session is all it holds, else its row
 * with the subtotal of everything under it, then its own session, the
 * sessions `/clear` let go in it as one row, `before /clear`, and each
 * agent and team run, every row its own spend, task agents under the
 * session that started them.
 */
function tabRows(tab: SpendPart): Row[] {
  const parts = tab.parts ?? [];
  const closed = tab.ended === true;
  const mains = parts.filter((part) => part.kind === 'main');
  // An open tab's main is open; a closed tab's is the one it closed with,
  // after any `/clear` let go before it.
  const own = closed ? mains.at(-1) : mains.find((part) => part.ended !== true);
  const cleared = mains.filter((part) => part !== own);
  const rest = parts.filter((part) => part.kind !== 'main');
  const mark: Note[] = closed ? [{ long: 'closed', short: 'closed' }] : [];

  if (cleared.length === 0 && rest.length === 0 && own?.parts === undefined) {
    return [ownRow(tab.name, 0, own?.figure, mark)];
  }

  return [
    sumRow(tab.name, 0, sum(parts), mark),
    ...(own === undefined ? [] : sessionRows(own, 'main', 1)),
    ...(cleared.length === 0
      ? []
      : [
          sumRow(
            'before /clear',
            1,
            sum(cleared.map(alone)),
            cleared.length > 1
              ? [
                  {
                    long: `${cleared.length} sessions`,
                    short: `${cleared.length} sessions`,
                  },
                ]
              : [],
          ),
          ...cleared.flatMap((session) =>
            (session.parts ?? []).flatMap((task) => taskRows(task, 2)),
          ),
        ]),
    ...rest.flatMap((part) => childRows(part, 1)),
  ];
}

/** The tasks still running anywhere under `parts`. */
function running(parts: readonly SpendPart[]): number {
  return parts.reduce(
    (all, part) =>
      all + (part.running === true ? 1 : 0) + running(part.parts ?? []),
    0,
  );
}

/** Whether a figure under `parts` holds an older record's sum. */
function lastReported(parts: readonly SpendPart[]): boolean {
  return parts.some(
    (part) =>
      part.figure?.before !== undefined || lastReported(part.parts ?? []),
  );
}

/** The Total row: the window's sum, and what its figures leave out. */
function totalRow(parts: readonly SpendPart[]): Row {
  const summed = sum(parts);
  const tasks = running(parts);
  const notes: Note[] = [
    ...(summed.estimated === 'all'
      ? [{ long: "chord's estimate", short: "chord's estimate" }]
      : summed.estimated === 'part'
        ? [{ long: "part chord's estimate", short: 'part estimate' }]
        : []),
    ...(lastReported(parts)
      ? [{ long: 'part as last reported', short: 'part as last reported' }]
      : []),
    ...(summed.uncounted === 0
      ? []
      : [
          {
            long: `${summed.uncounted} ${
              summed.uncounted === 1 ? 'turn' : 'turns'
            } not counted`,
            short: `${summed.uncounted} not counted`,
          },
        ]),
    ...(summed.missing.length === 0
      ? []
      : [
          {
            long: summed.missing
              .map((name) => `${name} not reported`)
              .join('; '),
            short: `${summed.missing.length} not reported`,
          },
        ]),
    ...(tasks === 0
      ? []
      : [{ long: `${tasks} running`, short: `${tasks} running` }]),
  ];

  return sumRow('Total', 0, summed, notes);
}

/**
 * `text` on one line, as a name a person or an agent gave may span several:
 * every run of whitespace one space, as a prompt's line is shown.
 */
function oneLine(text: string): string {
  return text.replace(/\s+/g, ' ').trim();
}

/** `text` cut to `cells` columns, an ellipsis where it was cut. */
function cut(text: string, cells: number): string {
  if (stringWidth(text) <= cells) {
    return text;
  }

  if (cells <= 1) {
    return cells === 1 ? '…' : '';
  }

  const [head = ''] = wrapAnsi(text, cells - 1, {
    hard: true,
    trim: false,
    wordWrap: false,
  }).split('\n');

  return `${head}…`;
}

/** `text` padded with spaces to `cells` columns, at its end or its start. */
function pad(text: string, cells: number, start = false): string {
  const fill = ' '.repeat(Math.max(0, cells - stringWidth(text)));

  return start ? fill + text : text + fill;
}

/** The header's name, which the name column is never narrower than. */
const NAME_LEAST = 'This window'.length;

/**
 * The table's lines for the window's spend in `width` cells, none wider:
 * names cut where the figures would not fit beside them, and each note in
 * its long form where the row then fits, else its short one, cut at the
 * row's end where even that does not; a note never wraps.
 */
export function spendTable(
  parts: readonly SpendPart[],
  width: number,
): ReportRow[] {
  const rows = [...parts.flatMap(tabRows), totalRow(parts)];
  const costWidth = Math.max(
    stringWidth('Cost'),
    ...rows.map((row) => stringWidth(row.cost)),
  );
  const tokenWidth = Math.max(
    stringWidth('Tokens'),
    ...rows.map((row) => stringWidth(row.tokens)),
  );
  const figures = 2 + costWidth + 2 + tokenWidth;
  const names = rows.map(
    (row) => `${'  '.repeat(row.depth)}${oneLine(row.name)}`,
  );
  // At most a third of the table, the figures never cut.
  const nameWidth = Math.min(
    Math.max(NAME_LEAST, ...names.map((name) => stringWidth(name))),
    Math.max(NAME_LEAST, Math.floor(width / 3)),
    Math.max(1, width - figures),
  );
  const line = (name: string, cost: string, tokens: string) =>
    `${pad(cut(name, nameWidth), nameWidth)}  ${pad(cost, costWidth, true)}  ${pad(
      tokens,
      tokenWidth,
      true,
    )}`;

  return [
    { text: cut(line('This window', 'Cost', 'Tokens'), width) },
    ...rows.map((row, index) => {
      const shown = line(names[index]!, row.cost, row.tokens);
      const room = width - stringWidth(shown) - 2;
      const long = oneLine(row.notes.map((note) => note.long).join('; '));
      const short = oneLine(row.notes.map((note) => note.short).join('; '));
      const note =
        long === '' ? '' : stringWidth(long) <= room ? long : cut(short, room);

      return {
        text: cut(note === '' ? shown : `${shown}  ${note}`, width),
      };
    }),
  ];
}
