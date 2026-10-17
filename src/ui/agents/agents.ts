/**
 * The list of a session's agents under the prompt, kept out of the
 * component: `main` and each long-lived child, one row each with its
 * runtime, model and state, a team's members nested under its lead or
 * folded into its row, cut to the window's height and width; and where
 * ↑ ↓ move the `❯` in it, on to the background's summary line after it.
 */
import cliTruncate from 'cli-truncate';
import stringWidth from 'string-width';
import {
  type Failure,
  failedSince,
  failureOf,
  repliedSince,
  type TabWait,
} from '../../session/tabs.ts';
import { GLYPHS } from '../app/strip.ts';
import { queueRowLimit } from '../prompt/queue.ts';
import { formatElapsed } from '../../session/elapsed.ts';
import type { LeftOpen } from '../../session/transcript/types.ts';

/** One agent of the front session, as the list is asked to draw it. */
export interface AgentRow {
  /** Its session's key: the tab's own for `main`, the child's for a child. */
  readonly key: number;
  /** `main`, or the child's name. */
  readonly name: string;
  readonly runtime: string;
  /** The model as the status line names it; none until known. */
  readonly model?: string | undefined;
  /** The effort it is on, by its id; none for a runtime with none. */
  readonly effort?: string | undefined;
  /** Its place among the theme's agent colours; none for `main`. */
  readonly colour?: number;
  readonly wait: TabWait;
  /** The prompt goes to it. */
  readonly picked: boolean;
  /** Its agent never came up. */
  readonly failed: boolean;
  /** A team's lead and each of its members: the lead's key. */
  readonly team?: number;
  /** A member's place in its lead's tree, as `teamRows` draws it. */
  readonly branch?: '├─' | '└─';
  /** A lead folded with its open members: they, in their order. */
  readonly folded?: readonly AgentRow[];
}

/** How a state is painted: the theme's role, or dim. */
export type AgentTone = 'warning' | 'error' | 'success' | 'dim';

/** What a row says of its agent: the glyph, then the words. */
export interface AgentState {
  readonly glyph: string;
  readonly words: string;
  readonly tone: AgentTone;
}

/** `41s`, `2m`: the first unit of an elapsed time. */
function briefly(ms: number): string {
  return formatElapsed(ms).split(' ')[0]!;
}

/**
 * What failed for an agent, gravest first: its process exited, it never came
 * up, or its turn failed while it stayed open, which only an unseen failure
 * says; none when nothing did.
 */
function failureFor(row: AgentRow): Failure | undefined {
  return row.wait.exited
    ? 'exited'
    : row.failed
      ? 'start'
      : failureOf(row.wait);
}

/**
 * Where an agent stands, most urgent first, as the strip's glyphs and the
 * sessions picker's words say it, with `←` for a message not yet seen;
 * none while it is idle and seen. A failed turn is told apart from an agent
 * that is gone, as the agent is still open (CHD-264).
 */
export function agentState(row: AgentRow, now: number): AgentState | undefined {
  if (row.folded !== undefined) {
    return teamState(row, row.folded, now);
  }

  const { wait } = row;

  if (wait.asking) {
    return {
      glyph: GLYPHS.asking,
      words: `${wait.asking.on.kind === 'input' ? 'input' : 'permission'} ${formatElapsed(
        now - wait.asking.since,
      )}`,
      tone: 'warning',
    };
  }

  const failure = failureFor(row);

  if (failure !== undefined) {
    return {
      glyph: GLYPHS.failed,
      words:
        failure === 'exited'
          ? 'exited'
          : failure === 'start'
            ? 'failed to start'
            : `turn failed ${briefly(now - (failedSince(wait) ?? now))} ago`,
      tone: 'error',
    };
  }

  if (wait.unseen?.kind === 'message') {
    return {
      glyph: '←',
      words: `message from ${wait.unseen.from ?? '@main'}`,
      tone: 'dim',
    };
  }

  if (wait.unseen?.kind === 'replied') {
    return {
      glyph: GLYPHS.replied,
      words: `replied ${briefly(now - (repliedSince(wait) ?? now))} ago`,
      tone: 'success',
    };
  }

  return wait.working === undefined
    ? undefined
    : {
        glyph: GLYPHS.working,
        words: `working ${formatElapsed(now - wait.working)}`,
        tone: 'dim',
      };
}

/**
 * How urgent an agent's state is, as `agentState` orders them, lowest
 * first, then how long it has stood, longest first; none while it is idle
 * and seen.
 */
function urgency(row: AgentRow): readonly [number, number] | undefined {
  const { wait } = row;

  if (wait.asking) {
    return [0, wait.asking.since];
  }

  const failure = failureFor(row);

  if (failure !== undefined) {
    return [
      failure === 'exited' ? 1 : failure === 'start' ? 2 : 3,
      wait.unseen?.since ?? 0,
    ];
  }

  if (wait.unseen !== undefined) {
    return [wait.unseen.kind === 'message' ? 4 : 5, wait.unseen.since];
  }

  return wait.working === undefined ? undefined : [6, wait.working];
}

/**
 * A folded team's state: the most urgent among its lead and members, as the
 * sessions picker gives a tab's children's, naming the member whose it is:
 * `● tester: permission 12s`.
 */
function teamState(
  lead: AgentRow,
  members: readonly AgentRow[],
  now: number,
): AgentState | undefined {
  const { folded: _, ...own } = lead;
  const first = [own, ...members]
    .flatMap((row) => {
      const rank = urgency(row);

      return rank === undefined ? [] : [{ row, rank }];
    })
    .sort((a, b) => a.rank[0] - b.rank[0] || a.rank[1] - b.rank[1])[0]?.row;

  if (first === undefined) {
    return undefined;
  }

  const state = agentState(first, now)!;

  return first === own
    ? state
    : { ...state, words: `${first.name}: ${state.words}` };
}

/**
 * The agents as the list draws them: each member under its lead with
 * CHD-149's `├─` and `└─`, and, with `fold`, each team but the one whose
 * agent is picked folded into its lead's row, its members kept for its
 * size and its state. A lead with no member open has nothing to fold.
 */
export function teamRows(
  agents: readonly AgentRow[],
  { fold }: { readonly fold: boolean },
): AgentRow[] {
  const picked = agents.find((row) => row.picked)?.team;
  const membersOf = (lead: number) =>
    agents.filter((row) => row.team === lead && row.key !== lead);

  return agents.flatMap((row): AgentRow[] => {
    if (row.team === undefined) {
      return [row];
    }

    const members = membersOf(row.team);

    if (row.key !== row.team) {
      return fold && row.team !== picked
        ? []
        : [
            {
              ...row,
              branch: row === members[members.length - 1] ? '└─' : '├─',
            },
          ];
    }

    return fold && row.team !== picked && members.length > 0
      ? [{ ...row, folded: members }]
      : [row];
  });
}

/**
 * Whether a time on the list goes on counting, so the list ticks: an agent
 * asking, working or with a reply or failed turn not yet seen, a folded
 * team's members among them, since their state stands on the lead's row.
 */
export function listTimed(rows: readonly AgentRow[]): boolean {
  const timed = (row: AgentRow): boolean =>
    row.wait.asking !== undefined ||
    row.wait.working !== undefined ||
    row.wait.unseen?.kind === 'replied' ||
    failureFor(row) === 'turn' ||
    (row.folded ?? []).some(timed);

  return rows.some(timed);
}

/** At most this many rows, the queue's own limit: 4 at 24 rows, 6 at 40. */
export function agentsRowLimit(rows: number): number {
  return queueRowLimit(rows);
}

/**
 * The list's rows: the agents, drawn only while there is a child. When they
 * all do not fit `limit` rows, each team the pick is not in folds to its
 * lead's row.
 */
export function listRows(
  agents: readonly AgentRow[],
  limit = Infinity,
): AgentRow[] {
  return teamRows(agents, { fold: agents.length > limit });
}

/**
 * Where the `❯` goes: an agent, which is picked, or the background's
 * summary line after the agents, the list's last stop.
 */
export type ListTarget =
  | { readonly kind: 'agent'; readonly key: number }
  | { readonly kind: 'summary' };

/**
 * ↑ ↓ in the list: the stop `by` from the focused one, the summary line
 * (when `summary` is drawn) after the agents; the last stays the last, and
 * none above the first hands the keys back to the box. With no agents drawn
 * the summary line is the one stop.
 */
export function moveListFocus(
  rows: readonly AgentRow[],
  by: number,
  {
    summary,
    onSummary,
  }: { readonly summary: boolean; readonly onSummary: boolean },
): ListTarget | undefined {
  const stops = rows.length + (summary ? 1 : 0);
  const from =
    summary && (onSummary || rows.length === 0)
      ? rows.length
      : Math.max(
          0,
          rows.findIndex((row) => row.picked),
        );
  const at = Math.min(from + by, stops - 1);

  if (stops === 0 || at < 0) {
    return undefined;
  }

  return at === rows.length
    ? { kind: 'summary' }
    : { kind: 'agent', key: rows[at]!.key };
}

/** One row laid out: its columns, each padded to the widest. */
export interface LaidRow {
  readonly row: AgentRow;
  /** `❯ ` on the focused row while the list has the keys, else two spaces. */
  readonly mark: string;
  /** A member's `├─ ` or `└─ `, drawn dim ahead of its name. */
  readonly branch?: string;
  /** The name, padded so that with the branch it fills the column. */
  readonly name: string;
  /** Its runtime and model. */
  readonly detail: string;
  readonly state?: { readonly text: string; readonly tone: AgentTone };
}

export interface AgentsLayout {
  readonly rows: readonly LaidRow[];
  /** How many rows `… +N more` stands for; 0 when all are drawn. */
  readonly more: number;
}

/** The least a name is ever cut to, so one stays readable. */
const NAME_FLOOR = 12;

/** The gap between the columns. */
const GAP = '  ';

/**
 * What one way of fitting the rows keeps: an agent's model and its effort,
 * and its state words and a folded team's size.
 */
interface Fit {
  readonly model: boolean;
  readonly effort: boolean;
  readonly words: boolean;
}

/**
 * Each way of fitting, the fullest first: an agent's effort goes first,
 * then its model, then its state words, leaving its glyph.
 */
const FITS: readonly Fit[] = [
  { model: true, effort: true, words: true },
  { model: true, effort: false, words: true },
  { model: false, effort: false, words: true },
  { model: false, effort: false, words: false },
];

/**
 * The rows drawn in `limit` at `width`: past the limit, the last row is
 * `… +N more`, and while the list has the keys the rows shown move so the
 * picked one is among them. `focused` marks the picked row with the `❯`,
 * which is elsewhere while the summary line has it. A row that does not fit
 * gives way as `FITS` says; the name is cut last, never below twelve
 * columns.
 */
export function agentsLayout(
  rows: readonly AgentRow[],
  {
    limit,
    width,
    focused,
    now,
  }: {
    readonly limit: number;
    readonly width: number;
    readonly focused: boolean;
    readonly now: number;
  },
): AgentsLayout {
  const room = Math.max(1, limit);
  const fits = rows.length <= room;
  const shown = fits ? rows.length : room - 1;
  const at = Math.max(
    0,
    rows.findIndex((row) => row.picked),
  );
  const start =
    fits || !focused
      ? 0
      : Math.min(Math.max(0, at - shown + 1), rows.length - shown);
  const visible = rows.slice(start, start + shown);
  const states = new Map(rows.map((row) => [row, agentState(row, now)]));
  // Widths over every row, drawn or not, so scrolling never moves a column.
  const widest = (texts: readonly string[]) =>
    Math.max(0, ...texts.map((text) => stringWidth(text)));
  const branchOf = (row: AgentRow) =>
    row.branch === undefined ? '' : `${row.branch} `;
  // A folded team's members count too, under their branch as unfolded, so
  // folding never moves a column.
  const nameWidth = widest(
    rows.flatMap((row) => [
      branchOf(row) + row.name,
      ...(row.folded ?? []).map((member) => `├─ ${member.name}`),
    ]),
  );

  for (const fit of FITS) {
    // A folded lead's size stands where its model would, and stays while
    // the states keep their words: it says more than a model.
    const runtimeOf = (row: AgentRow) =>
      [
        row.runtime,
        row.folded !== undefined
          ? fit.words
            ? `${row.folded.length + 1} agents`
            : undefined
          : fit.model
            ? row.model
            : undefined,
        // After its model, which it tunes; a folded lead says its size.
        row.folded === undefined && fit.model && fit.effort
          ? row.effort
          : undefined,
      ]
        .filter((part) => part !== undefined)
        .join(' · ');
    const stateOf = (row: AgentRow): LaidRow['state'] => {
      const state = states.get(row);

      return (
        state && {
          text: fit.words ? `${state.glyph} ${state.words}` : state.glyph,
          tone: state.tone,
        }
      );
    };

    const runtimeWidth = widest(rows.map(runtimeOf));
    const stateWidth = widest(rows.map((row) => stateOf(row)?.text ?? ''));
    const fixed =
      2 +
      nameWidth +
      GAP.length +
      (stateWidth === 0 ? 0 : GAP.length + stateWidth);
    const last = fit === FITS[FITS.length - 1];

    if (fixed + runtimeWidth > width && !last) {
      continue;
    }

    // Past the last fallback the name gives way, down to its floor.
    const names = Math.max(
      Math.min(nameWidth, NAME_FLOOR),
      nameWidth - Math.max(0, fixed + runtimeWidth - width),
    );

    return {
      more: rows.length - shown,
      rows: visible.map((row) => {
        const state = stateOf(row);
        const branch = branchOf(row);
        const room = names - stringWidth(branch);

        return {
          row,
          mark: focused && row.picked ? '❯ ' : '  ',
          ...(branch === '' ? {} : { branch }),
          name: pad(cliTruncate(row.name, room), room),
          detail: pad(runtimeOf(row), runtimeWidth),
          ...(state === undefined ? {} : { state }),
        };
      }),
    };
  }

  return { rows: [], more: 0 };
}

function pad(text: string, width: number): string {
  return text + ' '.repeat(Math.max(0, width - stringWidth(text)));
}

/** What the status line's right side takes beside the hint. */
const RIGHT_ROOM = 40;

/**
 * The status line's hint while the list has the keys, as a picker's last
 * line says what its keys do; shortened where the full one does not fit.
 */
export function agentsHint(width: number, close: string | undefined): string {
  const full = [
    '↑ ↓ to pick',
    'enter to write to it',
    ...(close === undefined ? [] : [`${close} to close`]),
    'esc to go back',
  ].join(' · ');

  // Room left for the model and the context beside it, as the status line
  // keeps them; at 80 columns that takes the short words.
  return stringWidth(full) + RIGHT_ROOM <= width
    ? full
    : [
        '↑ ↓ pick',
        'enter write',
        ...(close === undefined ? [] : [`${close} close`]),
        'esc back',
      ].join(' · ');
}

/**
 * The status line's hint while the summary line has the `❯`: it is opened,
 * not written to; shortened where the full one does not fit.
 */
export function summaryHint(width: number): string {
  const full = '↑ ↓ to move · enter to open · esc to go back';

  return stringWidth(full) + RIGHT_ROOM <= width
    ? full
    : '↑ ↓ move · enter open · esc back';
}

/**
 * The line that stands in a child's transcript where the startup header
 * would: `parser · codex · gpt-5.3-codex · opened by main 4m ago`; a team's
 * lead's says `team` and a member's names its run, each opened by an agent
 * that `send_message` reaches by that name: `tester · claude · Sonnet ·
 * bugfix's member · opened by @bugfix 6m ago`.
 */
export function childLine(
  child: {
    readonly name: string;
    readonly runtime: string;
    readonly openedAt: number;
    readonly team?: string | undefined;
    /** A member's lead, by its name. */
    readonly leadName?: string | undefined;
  },
  model: string | undefined,
  now: number,
): { readonly name: string; readonly rest: string } {
  const ago = briefly(Math.max(0, now - child.openedAt));
  const team = child.team !== undefined;

  return {
    name: child.name,
    rest: [
      '',
      ...(team && child.leadName === undefined ? ['team'] : []),
      child.runtime,
      ...(model === undefined ? [] : [model]),
      ...(child.leadName === undefined ? [] : [`${child.leadName}'s member`]),
      team
        ? `opened by @${child.leadName ?? 'main'} ${ago} ago`
        : `opened by main ${ago} ago`,
    ].join(' · '),
  };
}

/**
 * The note a resumed session's transcript closes with when long-lived agents
 * were open as it was left: `parser (codex) and team bugfix (4 agents) were
 * open when this session was left and are not reopened · /resume lists them ·
 * /team run bugfix starts the team again`. Each team run is one item, and
 * each team's way back is named once, however many of its runs were open.
 */
export function leftOpenLine(agents: readonly LeftOpen[]): string {
  const list = new Intl.ListFormat('en', { type: 'conjunction' });
  const names = list.format(
    agents.map(({ name, runtime, team, agents: count = 1 }) =>
      team === undefined
        ? `${name} (${runtime})`
        : `team ${name} (${count} ${count === 1 ? 'agent' : 'agents'})`,
    ),
  );
  const teams = [
    ...new Set(
      agents.flatMap(({ team }) => (team === undefined ? [] : [team])),
    ),
  ];
  const left =
    agents.length === 1
      ? 'was open when this session was left and is not reopened'
      : 'were open when this session was left and are not reopened';
  // A run is its lead and its members, each a session /resume lists.
  const listed = agents.length === 1 && teams.length === 0 ? 'it' : 'them';
  const back =
    teams.length === 0
      ? ''
      : ` · ${list.format(teams.map((team) => `/team run ${team}`))} ${
          teams.length === 1 ? 'starts the team again' : 'start the teams again'
        }`;

  return `${names} ${left} · /resume lists ${listed}${back}`;
}
