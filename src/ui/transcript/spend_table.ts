/**
 * `/cost`'s table of what the window has spent, once it holds more than one
 * session: a row for each tab with its subtotal, then its own agent and
 * each agent under it, closed ones too, and the window's total, each with a
 * note in a long form, or a short one where the long does not fit (CHD-373
 * S4, CHD-378's C as settled for the build).
 */
import type { Cost } from '@agentclientprotocol/sdk';
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

/** A team run's row: its members added up, each named in the long note. */
function teamRow(team: SpendPart, depth: number): Row {
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

  return sumRow(team.name, depth, sum(members), [
    {
      long: `team run${ended ? ', ended' : ''}: ${each}`,
      short: `team run of ${members.length}${ended ? ', ended' : ''}`,
    },
  ]);
}

/** The row of a task agent, of a long-lived agent, or of a team run. */
function childRow(part: SpendPart, depth: number): Row {
  switch (part.kind) {
    case 'task':
      return part.running === true
        ? {
            name: part.name,
            depth,
            cost: NONE,
            tokens: NONE,
            notes: [
              {
                long: 'task agent, running: counted when it ends',
                short: 'running',
              },
            ],
          }
        : ownRow(part.name, depth, part.figure, [
            { long: 'task agent, ended', short: 'ended' },
          ]);
    case 'team':
      return teamRow(part, depth);
    default:
      return ownRow(part.name, depth, part.figure, [
        part.ended === true
          ? { long: 'agent, closed', short: 'closed' }
          : { long: 'agent', short: 'agent' },
      ]);
  }
}

/**
 * A tab's rows: one when its own session is all it holds, else its row
 * with its subtotal and each part under it; the sessions `/clear` let go
 * in it as one row, `before /clear`.
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

  if (cleared.length === 0 && rest.length === 0) {
    return [ownRow(tab.name, 0, own?.figure, mark)];
  }

  const before = cleared.length === 0 ? undefined : sum(cleared);

  return [
    sumRow(tab.name, 0, sum(parts), mark),
    ...(own === undefined ? [] : [ownRow('main', 1, own.figure)]),
    ...(before === undefined
      ? []
      : [
          sumRow(
            'before /clear',
            1,
            before,
            cleared.length > 1
              ? [
                  {
                    long: `${cleared.length} sessions`,
                    short: `${cleared.length} sessions`,
                  },
                ]
              : [],
          ),
        ]),
    ...rest.map((part) => childRow(part, 1)),
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
    ...(summed.estimated === 'none'
      ? []
      : [{ long: "part chord's estimate", short: 'part estimate' }]),
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
 * The table's lines for the window's spend, laid out in `width` columns:
 * each note in its long form where the row then fits, else its short one.
 */
export function spendTable(
  parts: readonly SpendPart[],
  width: number,
): ReportRow[] {
  const rows = [...parts.flatMap(tabRows), totalRow(parts)];
  const names = rows.map((row) => `${'  '.repeat(row.depth)}${row.name}`);
  const nameWidth = Math.max(
    'This window'.length,
    ...names.map((n) => n.length),
  );
  const costWidth = Math.max(
    'Cost'.length,
    ...rows.map((row) => row.cost.length),
  );
  const tokenWidth = Math.max(
    'Tokens'.length,
    ...rows.map((row) => row.tokens.length),
  );
  const line = (name: string, cost: string, tokens: string) =>
    `${name.padEnd(nameWidth)}  ${cost.padStart(costWidth)}  ${tokens.padStart(
      tokenWidth,
    )}`;

  return [
    { text: line('This window', 'Cost', 'Tokens') },
    ...rows.map((row, index) => {
      const figures = line(names[index]!, row.cost, row.tokens);
      const long = row.notes.map((note) => note.long).join('; ');
      const short = row.notes.map((note) => note.short).join('; ');
      const note =
        long === '' || figures.length + 2 + long.length <= width ? long : short;

      return { text: note === '' ? figures : `${figures}  ${note}` };
    }),
  ];
}
