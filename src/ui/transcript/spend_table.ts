/**
 * `/cost`'s table of what the window has spent, once it holds more than one
 * session: a row for the main session, then each agent beside it, closed
 * ones too, and the window's total, each with a note (CHD-373 S4, CHD-378's C as settled for the build); a cell that does
 * not fit wraps inside itself, and nothing is cut (CHD-473).
 */
import type { Cost } from '@agentclientprotocol/sdk';
import stringWidth from 'string-width';
import wrapAnsi from 'wrap-ansi';
import type { ReportRow } from '../../session/transcript/types.ts';
import { formatCost } from './reports.ts';
import { type Figure, type SpendPart, sum, type Summed } from './spend.ts';

/** A figure no part reported, in a cost or token column. */
const NONE = '—';

/** A row before it is laid out: its name, figures and notes. */
interface Row {
  readonly name: string;
  readonly depth: number;
  readonly cost: string;
  readonly tokens: string;
  readonly notes: readonly string[];
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
    (part.kind === 'team' ? 0 : 1) +
    (part.parts ?? []).reduce((all, under) => all + count(under), 0);

  return parts.reduce((all, part) => all + count(part), 0) > 1;
}

/** `cost` as the table writes it: `~` ahead of chord's estimate. */
function costText(cost: Cost, estimated: boolean): string {
  return `${estimated ? '~' : ''}${formatCost(cost)}`;
}

/**
 * What a figure says beside itself: whose estimate, older sums, turns left
 * out; for an agent that gives running totals and no cost, that its
 * provider gives none, said of `runtime` (CHD-472).
 */
function figureNotes(figure: Figure | undefined, runtime?: string): string[] {
  const notes: string[] = [];
  const none =
    figure?.totals !== undefined
      ? `${runtime ?? 'its agent'}'s provider reports no cost; `
      : '';

  const unpriced = figure?.totals?.unpriced ?? [];

  if (figure?.estimated === 'all') {
    const [model, ...more] = figure.models ?? [];

    notes.push(
      none +
        (unpriced.length > 0
          ? `chord's estimate from its models' prices; no price for ${unpriced.join(' and ')}`
          : model !== undefined && more.length === 0
            ? `chord's estimate from ${model}'s price`
            : "chord's estimate from its models' prices"),
    );
  } else if (figure?.totals !== undefined && figure.cost === undefined) {
    notes.push(
      `${none}no price for ${figure.totals.unpriced?.join(' and ') ?? figure.totals.model ?? 'its model'}`,
    );
  } else if (figure?.estimated === 'part') {
    notes.push("part chord's estimate");
  }

  if (figure?.before !== undefined) {
    const until = figure.before.until;

    notes.push(
      until === undefined
        ? 'as last reported'
        : `as last reported before ${DAY.format(until)}`,
    );
  }

  // An agent that gives running totals says what it left out by the
  // models chord has no price for (CHD-472).
  if (
    figure?.uncounted !== undefined &&
    figure.uncounted > 0 &&
    figure.totals === undefined
  ) {
    notes.push(
      `${figure.uncounted} ${figure.uncounted === 1 ? 'turn' : 'turns'} not counted`,
    );
  }

  return notes;
}

/** A session's or task's own row. */
function ownRow(
  name: string,
  depth: number,
  figure: Figure | undefined,
  kind: readonly string[] = [],
  runtime?: string,
): Row {
  return {
    name,
    depth,
    cost:
      figure?.cost === undefined
        ? 'not reported'
        : costText(figure.cost, figure.estimated !== undefined),
    tokens: figure?.tokens === undefined ? NONE : TOKENS.format(figure.tokens),
    notes: [...kind, ...figureNotes(figure, runtime)],
  };
}

/** A group's row: what is under it added up. */
function sumRow(
  name: string,
  depth: number,
  summed: Summed,
  notes: readonly string[] = [],
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
          notes: [`${kind}, running: counted when it ends`],
        }
      : ownRow(task.name, depth, task.figure, [`${kind}, ended`]),
    ...(task.parts ?? []).flatMap((under) => taskRows(under, depth + 1, owner)),
  ];
}

/** A session's row, its own spend, and its task agents' rows under it. */
function sessionRows(
  part: SpendPart,
  name: string,
  depth: number,
  kind: readonly string[] = [],
): Row[] {
  return [
    ownRow(name, depth, part.figure, kind, part.runtime ?? part.agent),
    ...(part.parts ?? []).flatMap((task) => taskRows(task, depth + 1)),
  ];
}

/**
 * A team run's rows: its lead and members added up, each named in its note,
 * then the task agents they started, each with its owner.
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
      `team run${ended ? ', ended' : ''}: ${each}`,
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
        part.ended === true ? 'agent, closed' : 'agent',
      ]);
  }
}

/**
 * The window's rows: the main session open now, the sessions `/clear` let
 * go as one row, `before /clear`, and each agent and team run, every row
 * its own spend, task agents under the session that started them.
 */
function windowRows(parts: readonly SpendPart[]): Row[] {
  const mains = parts.filter((part) => part.kind === 'main');
  const own = mains.find((part) => part.ended !== true);
  const cleared = mains.filter((part) => part !== own);
  const rest = parts.filter((part) => part.kind !== 'main');

  return [
    ...(own === undefined ? [] : sessionRows(own, 'main', 0)),
    ...(cleared.length === 0
      ? []
      : [
          sumRow(
            'before /clear',
            0,
            sum(cleared.map(alone)),
            cleared.length > 1 ? [`${cleared.length} sessions`] : [],
          ),
          ...cleared.flatMap((session) =>
            (session.parts ?? []).flatMap((task) => taskRows(task, 1)),
          ),
        ]),
    ...rest.flatMap((part) => childRows(part, 0)),
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
  const notes = [
    ...(summed.estimated === 'all'
      ? ["chord's estimate"]
      : summed.estimated === 'part'
        ? ["part chord's estimate"]
        : []),
    ...(lastReported(parts) ? ['part as last reported'] : []),
    ...(summed.uncounted === 0
      ? []
      : [
          `${summed.uncounted} ${summed.uncounted === 1 ? 'turn' : 'turns'} not counted`,
        ]),
    ...summed.missing.map((name) => `${name} not reported`),
    ...(summed.providers ?? []).map(
      (name) => `${name}'s provider reports no cost`,
    ),
    ...(tasks === 0 ? [] : [`${tasks} running`]),
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

/** `text` wrapped to `cells` at its spaces, a word wider broken. */
function wrapped(text: string, cells: number): string[] {
  return wrapAnsi(text, Math.max(1, cells), { hard: true, trim: true }).split(
    '\n',
  );
}

/**
 * A note's lines in `cells`: it breaks between its parts, after a `; ` or a
 * ` · `, where it can, and inside a part only where that part alone is
 * wider, so `1 turn not counted` stays whole on a line (CHD-473).
 */
function noteLines(note: string, cells: number): string[] {
  const parts = note.split(/(?<=;|·) /);
  const lines: string[] = [];

  for (const part of parts) {
    const last = lines.at(-1);

    if (last !== undefined && stringWidth(`${last} ${part}`) <= cells) {
      lines[lines.length - 1] = `${last} ${part}`;
    } else {
      lines.push(...wrapped(part, cells));
    }
  }

  return lines;
}

/** `text` padded with spaces to `cells` columns, at its end or its start. */
function pad(text: string, cells: number, start = false): string {
  const fill = ' '.repeat(Math.max(0, cells - stringWidth(text)));

  return start ? fill + text : text + fill;
}

/**
 * The least a note's cell keeps beside the figures; narrower, the note goes
 * below them (CHD-473).
 */
const NOTE_LEAST = 20;

/** The name column's heading (the owner's Q182). */
const HEADING = 'This session';

/** The header's name, which the name column is never narrower than. */
const NAME_LEAST = HEADING.length;

/**
 * The table's lines for the window's spend in `width` cells: the cost and
 * token columns as wide as their widest figure, on a row's first line; the
 * name column at most a third of the table, a longer name wrapping in it
 * under its first letter; the note the rest, wrapping between its parts,
 * or below the figures where that leaves it fewer than `NOTE_LEAST` cells.
 * A row is as tall as its tallest cell, and nothing is cut (CHD-473).
 */
export function spendTable(
  parts: readonly SpendPart[],
  width: number,
): ReportRow[] {
  const rows = [...windowRows(parts), totalRow(parts)];
  const costWidth = Math.max(
    stringWidth('Cost'),
    ...rows.map((row) => stringWidth(row.cost)),
  );
  const tokenWidth = Math.max(
    stringWidth('Tokens'),
    ...rows.map((row) => stringWidth(row.tokens)),
  );
  const figures = 2 + costWidth + 2 + tokenWidth;
  const indent = (row: Row) => '  '.repeat(row.depth);
  // At most a third of the table, the figures never moved.
  const nameWidth = Math.min(
    Math.max(
      NAME_LEAST,
      ...rows.map((row) => stringWidth(indent(row) + oneLine(row.name))),
    ),
    Math.max(NAME_LEAST, Math.floor(width / 3)),
    Math.max(1, width - figures),
  );
  const noteWidth = width - nameWidth - figures - 2;
  const beside = noteWidth >= NOTE_LEAST;
  const line = (name: string, cost: string, tokens: string) =>
    `${pad(name, nameWidth)}  ${pad(cost, costWidth, true)}  ${pad(
      tokens,
      tokenWidth,
      true,
    )}`;

  return [
    { text: line(HEADING, 'Cost', 'Tokens') },
    ...rows.flatMap((row) => {
      // The name's next lines under its first letter, the indent held.
      const names = wrapped(
        oneLine(row.name),
        nameWidth - stringWidth(indent(row)),
      ).map((each) => indent(row) + each);
      const note = oneLine(row.notes.join('; '));

      // Too narrow beside the figures, the note goes below them: from the
      // row's second line, at the cost column's left edge, beside the
      // name's next lines, to the table's end; under the name it would read
      // as a row of its own.
      if (!beside) {
        const below = note === '' ? [] : noteLines(note, width - nameWidth - 2);

        return Array.from(
          { length: Math.max(names.length, 1 + below.length) },
          (_, at) => {
            const said = at === 0 ? undefined : below[at - 1];

            return {
              text: (at === 0
                ? line(names[0]!, row.cost, row.tokens)
                : said === undefined
                  ? (names[at] ?? '')
                  : `${pad(names[at] ?? '', nameWidth)}  ${said}`
              ).trimEnd(),
            };
          },
        );
      }

      const notes = note === '' ? [] : noteLines(note, noteWidth);

      return Array.from(
        { length: Math.max(names.length, notes.length) },
        (_, at) => {
          const shown =
            at === 0
              ? line(names[0]!, row.cost, row.tokens)
              : line(names[at] ?? '', '', '');
          const said = notes[at];

          return {
            text: (said === undefined ? shown : `${shown}  ${said}`).trimEnd(),
          };
        },
      );
    }),
  ];
}
