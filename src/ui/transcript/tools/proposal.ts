/**
 * `propose_team`'s call as it is drawn, kept out of the component: the team
 * as a table of its agents (name, `runtime · model`, effort where any agent
 * sets one, mode, role), laid out by @cliffy/table after the cells are cut
 * to the width, the role first, then the effort's `was`, then the model, the
 * effort and mode never, or opened, each role whole on lines of its own
 * under its row; a change's rows marked against the team
 * saved before; the body folded, or a change's body as a diff cut to its
 * changed lines; and the line the person's answer leaves.
 */
import { Cell, Table } from '@cliffy/table';
import cliTruncate from 'cli-truncate';
import stringWidth from 'string-width';
import type { ChordCall } from '../../../session/transcript/types.ts';
import { type RowChange, type Team, teamChanges } from '../../../teams.ts';
import { wrapLine } from '../message.ts';
import type { CodeTones } from '../../theme/theme.ts';
import { type DiffView, diffView, lineCount, plural } from './diff.ts';

/** Between columns, as `chord agents` has it. */
const PADDING = 2;

/** The role is cut no narrower than this before the model is cut too. */
const MIN_ROLE = 12;

/** The lead's role, which the file has no line for. */
export const LEAD_ROLE =
  'Splits the job, says who edits which files, reports to main';

/** Modes that let an agent act without the person's ok, drawn as a warning. */
const UNASKED_MODES: ReadonlySet<string> = new Set([
  'bypassPermissions',
  'full-access',
]);

/** Whether `mode` skips the person's ok. */
export function skipsAsking(mode: string | undefined): boolean {
  return mode !== undefined && UNASKED_MODES.has(mode);
}

/** A proposal as the call holds it, once chord has checked and served it. */
export interface ProposalView {
  readonly name: string;
  readonly team: Team;
  readonly kind: 'new' | 'change';
  /** The team saved before, for a change whose file was a team. */
  readonly before?: Team;
  /** Where it was saved, false when it was not; none while the box is open. */
  readonly saved?: string | false;
}

function record(value: unknown): Record<string, unknown> {
  return typeof value === 'object' && value !== null
    ? (value as Record<string, unknown>)
    : {};
}

/**
 * The proposal a `propose_team` call drew, from what chord served: none for
 * another call, a refused one, or one not served yet. Its input passed the
 * check before it was served, so it is read as the team it is.
 */
export function proposalOf(call: ChordCall): ProposalView | undefined {
  if (
    call.tool !== 'propose_team' ||
    call.error !== undefined ||
    call.answer === undefined
  ) {
    return undefined;
  }

  const { name, body, ...rest } = record(call.input);
  const answer = record(call.answer);

  if (typeof name !== 'string' || typeof body !== 'string') {
    return undefined;
  }

  return {
    name,
    team: { ...(rest as unknown as Omit<Team, 'body'>), body: body.trim() },
    kind: answer.proposal === 'change' ? 'change' : 'new',
    ...(answer.before === undefined ? {} : { before: answer.before as Team }),
    ...(typeof answer.saved === 'string' || answer.saved === false
      ? { saved: answer.saved }
      : {}),
  };
}

/** One agent of the team, as its row reads before it is laid out. */
export interface AgentRow {
  readonly name: string;
  /** `claude · opus`, or the runtime alone. */
  readonly runtime: string;
  /** Its effort, or `—` where the runtime's own is used. */
  readonly effort: string;
  /** Its mode, or `—` where the runtime's own is used. */
  readonly mode: string;
  readonly role: string;
  /** Against the team saved before; none for a new team or an unchanged row. */
  readonly change?: RowChange;
  /** The effort it had before, on a changed row whose effort changed. */
  readonly effortWas?: string;
  /** The mode it had before, on a changed row whose mode changed. */
  readonly was?: string;
}

/** No mode or effort set: the runtime starts on its own. */
const OWN = '—';

interface Defined {
  readonly agent: string;
  readonly model?: string | undefined;
  readonly effort?: string | undefined;
  readonly mode?: string | undefined;
}

function agentRow(
  name: string,
  agent: Defined,
  role: string,
  change: RowChange | undefined,
  old?: Defined,
): AgentRow {
  const effort = agent.effort ?? OWN;
  const mode = agent.mode ?? OWN;
  const changed = change === 'changed';
  const effortWas = changed ? (old?.effort ?? OWN) : effort;
  const was = changed ? (old?.mode ?? OWN) : mode;

  return {
    name,
    runtime: [agent.agent, agent.model]
      .filter((part) => part !== undefined)
      .join(' · '),
    effort,
    mode,
    role,
    ...(change === undefined ? {} : { change }),
    ...(effortWas === effort ? {} : { effortWas }),
    ...(was === mode ? {} : { was }),
  };
}

/**
 * The team's rows, the lead first: against `before`, each marked by how it
 * changed, with the members it no longer has after the rest.
 */
export function agentRows(team: Team, before?: Team): AgentRow[] {
  const changes = before === undefined ? undefined : teamChanges(before, team);

  return [
    agentRow('lead', team.lead, LEAD_ROLE, changes?.lead, before?.lead),
    ...team.members.map((member) =>
      agentRow(
        member.name,
        member,
        member.role,
        changes?.members.get(member.name),
        before?.members.find((each) => each.name === member.name),
      ),
    ),
    ...(before?.members ?? [])
      .filter((member) => changes?.members.get(member.name) === 'removed')
      .map((member) => agentRow(member.name, member, member.role, 'removed')),
  ];
}

/** A change's mark, before its row: `+` new, `~` changed, `-` gone. */
const MARKS: Record<RowChange, string> = {
  added: '+',
  changed: '~',
  removed: '-',
};

/** One line of a row laid out: its text, and where in it the mode is. */
export interface TableLine {
  readonly text: string;
  /** The mode's cells, `[start, end)` in `text`; empty on a row's later lines. */
  readonly mode: readonly [number, number];
  /** The mode it had before, after the mode: `[start, end)` in `text`. */
  readonly was?: readonly [number, number];
  /** The effort it had before, after the effort: `[start, end)` in `text`. */
  readonly effortWas?: readonly [number, number];
  /** A line of the role under its row, as an opened table draws it. */
  readonly role?: true;
  readonly row: AgentRow;
}

/** Between a changed mode and the one it had: `bypassPermissions was —`. */
const WAS = ' was ';

/** A row's mode cell: its mode, and the one it had where that changed. */
function modeCell(row: AgentRow): string {
  return row.was === undefined ? row.mode : `${row.mode}${WAS}${row.was}`;
}

/**
 * A row's effort cell: its effort, and, where it changed and `was`, the one
 * it had.
 */
function effortCell(row: AgentRow, was = true): string {
  return row.effortWas === undefined || !was
    ? row.effort
    : `${row.effort}${WAS}${row.effortWas}`;
}

/**
 * Whether the table has an effort column: only where an agent sets one or
 * had one, so a team with none reads as it did before efforts.
 */
function hasEfforts(rows: readonly AgentRow[]): boolean {
  return rows.some((row) => row.effort !== OWN || row.effortWas !== undefined);
}

/**
 * A changed cell as cliffy gets it where it is wider than its column: broken
 * before `was`, so the new value has a line of its own and is not read as
 * the old one, which `acceptEdits was` / `bypassPermissions` would be.
 */
function brokenBeforeWas(cell: string, room: number): string {
  return stringWidth(cell) <= room
    ? cell
    : cell.replace(WAS, `\n${WAS.trim()} `);
}

function widest(cells: readonly string[]): number {
  return Math.max(0, ...cells.map((cell) => stringWidth(cell)));
}

/**
 * The rows laid out in columns no wider than `width`, a change's with its
 * mark first when `marked`: the role cut first, down to `MIN_ROLE`, then a
 * changed effort's `was …` dropped, then the runtime's model, the name,
 * effort and mode never, as the mode is the permission the person approves
 * and the effort what the agent spends on it. `whole`, as the person
 * reviewing a proposal reads all the file holds, each row's role is not cut
 * but goes on lines of its own under the row, from the runtime's column to
 * the right edge, wrapped there by @cliffy/table, and where the row would
 * not fit, the mode, then the effort, then the runtime wrap in their
 * columns, never cut, a changed cell broken before its `was` first.
 */
export function proposalTable(
  rows: readonly AgentRow[],
  width: number,
  marked = false,
  whole = false,
): TableLine[] {
  const mark = (row: AgentRow) =>
    row.change === undefined ? ' ' : MARKS[row.change];
  const names = widest(rows.map((row) => row.name));
  const modes = widest(rows.map(modeCell));
  const efforts = hasEfforts(rows);
  const effortsWhole = efforts ? widest(rows.map((row) => effortCell(row))) : 0;
  const named = marked ? 1 + PADDING : 0;
  const runtimes = widest(rows.map((row) => row.runtime));
  const roles = whole ? 0 : widest(rows.map((row) => row.role));
  const leastRole = Math.min(MIN_ROLE, roles);
  const base = named + names + PADDING + modes + PADDING;
  // Folded, a changed effort keeps its `was` only while the model stays
  // whole beside a role of `MIN_ROLE`: the `~` already says the row changed.
  const effortWas =
    whole ||
    width - base - effortsWhole - PADDING - runtimes - PADDING >= leastRole;
  const effortsWidth = efforts
    ? effortWas
      ? effortsWhole
      : widest(rows.map((row) => effortCell(row, false)))
    : 0;
  const fixed = base + (efforts ? effortsWidth + PADDING : 0);
  const roleRoom = Math.max(width - fixed - runtimes - PADDING, leastRole);
  const runtimeRoom = Math.max(
    1,
    Math.min(
      runtimes,
      width - fixed - (whole ? 0 : Math.min(roles, roleRoom) + PADDING),
    ),
  );
  const cut = (text: string, room: number) =>
    stringWidth(text) <= room ? text : cliTruncate(text, Math.max(1, room));

  if (rows.length === 0) {
    return [];
  }

  if (!whole) {
    const effortAt =
      named +
      names +
      PADDING +
      widest(rows.map((row) => cut(row.runtime, runtimeRoom))) +
      PADDING;
    const before = effortAt + (efforts ? effortsWidth + PADDING : 0);
    // The role is a tool result's words, so it wraps in its own column,
    // never cut (CHD-422); each row is laid out on its own in the same
    // columns, so a role's later lines are told from the next row.
    const columns = [
      ...(marked ? [1] : []),
      names,
      widest(rows.map((row) => cut(row.runtime, runtimeRoom))),
      ...(efforts ? [effortsWidth] : []),
      modes,
      Math.max(1, Math.min(roles, roleRoom)),
    ];

    return rows.flatMap((row) => {
      const [first = '', ...rest] = new Table()
        .body([
          [
            ...(marked ? [mark(row)] : []),
            row.name,
            cut(row.runtime, runtimeRoom),
            ...(efforts ? [effortCell(row, effortWas)] : []),
            modeCell(row),
            row.role,
          ],
        ])
        .minColWidth(columns)
        .maxColWidth(columns)
        .padding(PADDING)
        .toString()
        .split('\n');
      const from = effortAt + row.effort.length;
      const end = effortAt + effortCell(row, effortWas).length;

      return [
        {
          ...modeLine(first, row, before),
          ...(efforts && from < end ? { effortWas: [from, end] as const } : {}),
        },
        ...rest.map((line) => wrapped(line.trimEnd(), row)),
      ];
    });
  }

  // Where the row does not fit, the mode cell wraps first, at its spaces and
  // never narrower than its longest word, then the effort cell likewise,
  // then agent · model, which cliffy breaks at its spaces while the column
  // holds its longest word and inside a word only below that.
  const room = width - named - names - PADDING;
  const modeRoom = Math.min(
    modes,
    Math.max(
      widestWord(rows.map(modeCell)),
      room - runtimes - PADDING - (efforts ? effortsWhole + PADDING : 0),
    ),
  );
  const effortRoom = efforts
    ? Math.min(
        effortsWhole,
        Math.max(
          widestWord(rows.map((row) => effortCell(row))),
          room - runtimes - PADDING - modeRoom - PADDING,
        ),
      )
    : 0;
  const agentRoom = Math.max(
    1,
    Math.min(
      runtimes,
      room - modeRoom - PADDING - (efforts ? effortRoom + PADDING : 0),
    ),
  );
  const effortAt = named + names + PADDING + agentRoom + PADDING;
  const before = effortAt + (efforts ? effortRoom + PADDING : 0);
  // An empty last column takes what the row leaves of the width, so the role
  // spanning it and the runtime's and mode's reaches the right edge. Where a
  // mode leaves none, the row is wider than the width, as the mode is never
  // cut, and the role spans the runtime's and mode's columns only.
  const filler = width - before - modeRoom - PADDING;
  const widths = [
    ...(marked ? [1] : []),
    names,
    agentRoom,
    ...(efforts ? [effortRoom] : []),
    modeRoom,
    ...(filler >= 0 ? [filler] : []),
  ];
  // Each row and its role is laid out on its own, in the same columns, so a
  // runtime wrapped in its column is told from the role under it.
  const laid = (body: (string | Cell)[]) =>
    new Table()
      .body([body])
      .minColWidth(widths)
      .maxColWidth(widths)
      .padding(PADDING)
      .toString()
      .split('\n')
      .map((line) => line.trimEnd());

  return rows.flatMap((row) => {
    const lines = laid([
      ...(marked ? [mark(row)] : []),
      row.name,
      row.runtime,
      ...(efforts ? [brokenBeforeWas(effortCell(row), effortRoom)] : []),
      brokenBeforeWas(modeCell(row), modeRoom),
      ...(filler >= 0 ? [''] : []),
    ]);
    const modeWases = wasesIn(lines, modeCell(row), row.mode, before);
    const effortWases = efforts
      ? wasesIn(lines, effortCell(row), row.effort, effortAt, effortRoom)
      : [];

    return [
      ...lines.map((line, index): TableLine => {
        const mode =
          index === 0
            ? ([before, before + row.mode.length] as const)
            : undefined;
        const was = modeWases[index];
        const effortWas = effortWases[index];

        return {
          text: line,
          mode: mode ?? (was === undefined ? [0, 0] : [was[0], was[0]]),
          ...(row.was === undefined || was === undefined ? {} : { was }),
          ...(row.effortWas === undefined || effortWas === undefined
            ? {}
            : { effortWas }),
          row,
        };
      }),
      ...laid([
        ...Array<string>(marked ? 2 : 1).fill(''),
        new Cell(row.role).colSpan(widths.length - (marked ? 2 : 1)),
      ]).map((line) => ({ ...wrapped(line, row), role: true as const })),
    ];
  });
}

function widestWord(cells: readonly string[]): number {
  return widest(cells.flatMap((cell) => cell.split(' ')));
}

/**
 * Where a changed cell's `was …` landed on each of its row's lines, the
 * cell wrapped in its column of `room` from `start`: `[start, end)` in the
 * line, none on a line it is not on. Each line's part is found in the cell
 * again, as cliffy only wraps it at its spaces and at the break before
 * `was`, after `value`, the new one.
 */
function wasesIn(
  lines: readonly string[],
  cell: string,
  value: string,
  start: number,
  room = Infinity,
): (readonly [number, number] | undefined)[] {
  let read = 0;

  return lines.map((line) => {
    const part = line.slice(start, start + room).trimEnd();
    const at = part === '' ? -1 : cell.indexOf(part, read);

    if (at < 0) {
      return undefined;
    }

    read = at + part.length;

    const from = start + Math.max(value.length, at) - at;
    const end = start + part.length;

    return from < end ? [from, end] : undefined;
  });
}

/** A row's first line, its mode at `before` and what it was after that. */
function modeLine(line: string, row: AgentRow, before: number): TableLine {
  const end = before + row.mode.length;

  return {
    text: line.trimEnd(),
    mode: [before, end],
    ...(row.was === undefined
      ? {}
      : { was: [end, end + WAS.length + row.was.length] as const }),
    row,
  };
}

/** A row's line after its first, which holds no mode. */
function wrapped(line: string, row: AgentRow): TableLine {
  return { text: line, mode: [0, 0], row };
}

/** The line the person's answer leaves under the call, and how it is drawn. */
export function savedLine(
  view: ProposalView,
): { readonly text: string; readonly saved: boolean } | undefined {
  if (view.saved === undefined) {
    return undefined;
  }

  return view.saved === false
    ? { text: 'Not saved · the person will say what to change', saved: false }
    : {
        text:
          `Saved to ${view.saved} · /team run ${view.name} <job> hands ` +
          'it a job',
        saved: true,
      };
}

/**
 * How many of the body's lines a folded proposal shows: a couple where the
 * window has the rows, so the body's start reads, and none on a short one,
 * where the table and the save box must fit with the prompt.
 */
export function bodyLines(windowRows: number): number {
  return windowRows >= 30 ? 2 : 0;
}

/**
 * The lines ctrl+o adds after the table: each agent's instructions, under
 * its name, wrapped to `width` whole, as the person reviewing a proposal
 * reads all that the file will hold.
 */
export function instructionLines(team: Team, width: number): string[] {
  const agents = [
    { name: 'lead', instructions: team.lead.instructions },
    ...team.members,
  ];

  return agents.flatMap(({ name, instructions }) =>
    instructions === undefined
      ? []
      : [
          '',
          `${name}'s instructions`,
          ...instructions.trim().split('\n'),
        ].flatMap((line) => wrapLine(line, width)),
  );
}

/**
 * The lines after the table and how many ctrl+o adds: expanded, each
 * agent's instructions, then the body's `blocks` with a blank line between
 * them; folded, the body's first `keep` lines read on without the blank
 * lines. A change whose body is drawn as a diff has none of the body here.
 */
export function proposalBody({
  instructions,
  blocks,
  keep,
  expanded,
}: {
  instructions: readonly string[];
  /** The body rendered, a block each; none when a diff draws it. */
  blocks: readonly string[];
  keep: number;
  expanded: boolean;
}): { readonly lines: readonly string[]; readonly hidden: number } {
  const body = blocks.flatMap((block, index) => [
    ...(index === 0 ? [] : ['']),
    ...block.split('\n'),
  ]);
  const whole = [...instructions, ...(body.length === 0 ? [] : ['', ...body])];

  if (expanded) {
    return { lines: whole, hidden: 0 };
  }

  const preview = blocks
    .flatMap((block) => block.split('\n'))
    .filter((line) => line.trim() !== '')
    .slice(0, keep);
  const lines = preview.length === 0 ? [] : ['', ...preview];

  return { lines, hidden: Math.max(whole.length - lines.length, 0) };
}

/**
 * Rows of a change's body diff a folded proposal shows: a few where the
 * window has the rows, and none on a short one, where the table, the line
 * that counts the change and the save box must fit with the prompt.
 */
export function changeRows(windowRows: number): number {
  return windowRows >= 30 ? 5 : 0;
}

/**
 * `bugfix.md's body · 1 addition, 1 removal`: a change the person has not
 * saved yet, so not an edit's `Updated …`, which reads as written.
 */
export function bodyChangeLine(name: string, view: DiffView): string {
  return `${name}.md's body · ${plural(view.added, 'addition')}, ${plural(
    view.removed,
    'removal',
  )}`;
}

/**
 * A change's body as jsdiff's diff: expanded, whole, as an edit's is;
 * folded, its changed lines with a line of context each, the first `rows`
 * of them, and how many lines ctrl+o adds, which the view does not fold.
 */
export function bodyChange({
  name,
  before,
  after,
  expanded,
  rows,
  tones,
}: {
  name: string;
  before: string;
  after: string;
  expanded: boolean;
  rows: number;
  tones?: CodeTones | undefined;
}): { readonly view: DiffView; readonly hidden: number } {
  const path = `${name}.md`;
  const whole = diffView(path, before, after, true, tones);

  if (expanded) {
    return { view: whole, hidden: 0 };
  }

  const folded = diffView(path, before, after, false, tones, {
    context: 1,
    rows,
  });

  // The proposal's one fold line counts these, with the instructions.
  return {
    view: { ...folded, hidden: 0 },
    hidden: lineCount(whole.rows) - lineCount(folded.rows),
  };
}
