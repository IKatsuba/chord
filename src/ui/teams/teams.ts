/**
 * `/team`, kept out of the window: the words chord hands main, the teams
 * picker's rows, and `/team show`'s table of a running team. Nothing here
 * reads a file or a session; the window gathers what each needs.
 */
import { Table } from '@cliffy/table';
import stringWidth from 'string-width';
import wrapAnsi from 'wrap-ansi';
import {
  briefly,
  type ListedTeam,
  NO_TEAMS,
  newTeamPrompt,
  type TeamRun,
  teamsSaved,
  type TeamWords,
} from '../../session/team_command.ts';
import type {
  MessageFrom,
  TeamAgentShown,
  TeamRunShown,
} from '../../session/transcript/types.ts';
import type { FoundTeam, Team } from '../../teams.ts';
import { GLYPHS } from '../agents/glyphs.ts';
import type { PickerChoice } from '../pickers/picker.ts';
import { messageHeader } from '../transcript/message.ts';

export { NO_TEAMS, newTeamPrompt };

/** What `/team` says of runs, in the window's words. */
export const TEAM_WORDS: TeamWords = {
  whichRun: 'Which run? The list under the prompt names them',
  closedLead: '/resume lists it',
  closedRun: '/resume lists them',
  noRun: 'the list under the prompt names them',
};

/** A call's headline as one line: `Edit(src/a.ts)`, `→ to @coder`. */
export function headlineText({
  name,
  arg,
  tag = '',
  sent,
}: {
  name: string;
  arg?: string;
  tag?: string;
  sent?: true;
}): string {
  return sent
    ? `→ to @${name}`
    : arg === undefined
      ? `${name}${tag}`
      : `${name}${tag}(${arg})`;
}

/**
 * An incoming message's headline, as its row's header:
 * `← from @tester · claude`.
 */
export function messageHeadline(from: MessageFrom): string {
  const { word, name, rest } = messageHeader(from);

  return `← ${word}${name}${rest}`;
}

/** `✻ working 6m` for one run, `✻ 2 runs` for more, nothing for none. */
export function runningWords(runs: readonly TeamRun[], now: number): string {
  if (runs.length === 0) {
    return '';
  }

  return runs.length === 1
    ? `${GLYPHS.working} working ${briefly(now - runs[0]!.since)}`
    : `${GLYPHS.working} ${runs.length} runs`;
}

/** Below this many columns the picker drops the runtimes and half its hint. */
export const NARROW = 100;

/** Between columns, as `chord agents` has it. */
const GAP = '  ';

function padded(text: string, width: number): string {
  return text + ' '.repeat(Math.max(0, width - stringWidth(text)));
}

/**
 * The picker's rows, a team each, by name: its size and runtimes, where it
 * is saved, whether it runs in this window and its description, in columns;
 * a broken file's problem across them and its path where the description
 * goes. Below `NARROW` columns the runtimes and a broken file's path go.
 * The value is the team's name.
 */
export function teamChoices(
  teams: readonly ListedTeam[],
  runs: readonly TeamRun[],
  now: number,
  columns: number,
): PickerChoice[] {
  const narrow = columns < NARROW;
  const sizeOf = (team: Team) => {
    const runtimes = [
      ...new Set([team.lead.agent, ...team.members.map(({ agent }) => agent)]),
    ];
    const size = `${team.members.length + 1} agents`;

    return narrow ? size : `${size} · ${runtimes.join(', ')}`;
  };

  const placeOf = (found: ListedTeam) =>
    found.place === 'user'
      ? 'every project'
      : found.hides
        ? "this project · hides every project's"
        : 'this project';

  const running = teams.map((found) =>
    runningWords(
      runs.filter(({ team }) => team === found.name),
      now,
    ),
  );
  const names = Math.max(0, ...teams.map(({ name }) => stringWidth(name)));
  const sizes = Math.max(
    0,
    ...teams
      .flatMap((found) => ('team' in found ? [sizeOf(found.team)] : []))
      .map((text) => stringWidth(text)),
  );
  const places = Math.max(
    0,
    ...teams
      .filter((found) => 'team' in found)
      .map((found) => stringWidth(placeOf(found))),
  );
  const runnings = Math.max(0, ...running.map((text) => stringWidth(text)));
  const problemOf = (problem: string) =>
    `${GLYPHS.failed} not read: ${problem}`;
  // Where the description starts, for a broken file's path to start there
  // too: after the columns before it, or a wider problem.
  const before = Math.max(
    [sizes, places, runnings]
      .filter((width) => width > 0)
      .reduce((sum, width) => sum + width + GAP.length, 0),
    ...teams.flatMap((found) =>
      'problem' in found && !narrow
        ? [stringWidth(problemOf(found.problem)) + GAP.length]
        : [],
    ),
  );

  return teams.map((found, index) => {
    const name = padded(found.name, names);

    if ('problem' in found) {
      const problem = problemOf(found.problem);

      return {
        key: found.name,
        label: narrow
          ? `${name}${GAP}${problem}`
          : `${name}${GAP}${padded(
              problem,
              before - GAP.length,
            )}${GAP}${found.shown}`,
        value: found.name,
      };
    }

    const head = [
      padded(sizeOf(found.team), sizes),
      padded(placeOf(found), places),
      ...(runnings === 0 ? [] : [padded(running[index]!, runnings)]),
    ].join(GAP);

    return {
      key: found.name,
      label: [
        name,
        padded(head, before - GAP.length),
        found.team.description,
      ].join(GAP),
      value: found.name,
    };
  });
}

/** The picker's line under its title: where teams are saved. */
export function teamsWhere(
  dirs: { readonly project: string; readonly user?: string | undefined },
  columns: number,
): string {
  return dirs.user !== undefined && columns < NARROW
    ? `For this project in ${dirs.project}, for every project in ${dirs.user}.`
    : teamsSaved(dirs);
}

/**
 * The picker's hint for the team under the highlight, before its close
 * hint. A broken file takes no job, so its hint says how it gets fixed
 * instead of offering Enter: teams are changed by asking main.
 */
export function teamsHint(
  found: FoundTeam | undefined,
  columns: number,
): string[] {
  const narrow = columns < NARROW;

  if (found === undefined) {
    return [];
  }

  if ('problem' in found) {
    return [
      narrow
        ? `Ask main to fix ${found.name}`
        : `Fix the file, or ask main to fix ${found.name}`,
    ];
  }

  return narrow
    ? ['Enter to hand it a job']
    : ['Enter to hand it a job', '/team show <name>'];
}

/**
 * What Enter on a team puts in the draft: a run's start. A broken file has
 * nothing to start, so Enter on it leaves the picker open.
 */
export function pickedDraft(found: FoundTeam): string | undefined {
  return 'problem' in found ? undefined : `/team run ${found.name} `;
}

/**
 * The lines `/team show` opens a running team with: its name, its file and
 * how long it has worked on what, the whole job wrapped to `width`
 * (CHD-471).
 */
export function runningHeader(
  name: string,
  file: string,
  run: TeamRunShown,
  width: number,
): string[] {
  const job = run.job.replaceAll(/\s+/g, ' ').trim();

  return wrapAnsi(
    `${name} · ${file} · working ${briefly(run.at - run.since)} on "${job}"`,
    Math.max(1, width),
    { hard: true, trim: true },
  ).split('\n');
}

/** One running agent's row laid out, and where its state is in it. */
export interface RunningLine {
  readonly text: string;
  /**
   * The state, `[start, end)` as string indices in its line, to paint by
   * its tone: `text`, or the line of `under` that `stateLine` names.
   */
  readonly state: readonly [number, number];
  /** Which line the state is on: 0 for `text`, else `under`'s, from 1. */
  readonly stateLine: number;
  /** Its mark after the state, in the line `markLine` names. */
  readonly mark?: readonly [number, number];
  readonly markLine: number;
  /**
   * The row's further lines: its wrapped cells, its state where the row
   * had no room for it, and its latest headline, wrapped.
   */
  readonly under: readonly string[];
  readonly agent: TeamAgentShown;
}

/** What a member not open says in the state column. */
export const NOT_OPENED = 'not opened';

/**
 * The least of the latest headline's column kept beside the row; with less
 * the headline goes under the row.
 */
const BESIDE = 20;

/**
 * `/team show`'s running table: each agent's name, `runtime · model ·
 * effort` and mode from the file, then its state, its mark and its latest
 * headline. Nothing is cut (CHD-471): the headline wraps in its column
 * while that keeps `BESIDE` cells, and under the row from the runtime's
 * column where it would not. Where the row's own columns are wider than
 * `width`, the runtime's and then the name's wrap in a third of it, after a
 * ` · ` where they can; if that is not enough the state and mark go whole
 * under the row, and then the mode before them, that line wrapping between
 * its parts. The mode never wraps.
 */
export function runningTable(
  team: Team,
  agents: readonly TeamAgentShown[],
  width: number,
): RunningLine[] {
  const defined = (agent: TeamAgentShown) =>
    agent.lead
      ? team.lead
      : team.members.find((member) => member.name === agent.name);
  const ownState = (agent: TeamAgentShown) =>
    !agent.open
      ? NOT_OPENED
      : agent.state === undefined
        ? 'idle'
        : `${agent.state.glyph} ${agent.state.words}`;
  const markOf = (agent: TeamAgentShown) =>
    agent.open && agent.mark !== undefined
      ? `${agent.mark.glyph} ${agent.mark.words}`
      : undefined;
  // Each state padded where a mark follows, so the marks start in one column.
  const stateWidth = Math.max(
    0,
    ...agents.map((agent) => stringWidth(ownState(agent))),
  );
  const stateOf = (agent: TeamAgentShown) => {
    const mark = markOf(agent);

    return mark === undefined
      ? ownState(agent)
      : `${padded(ownState(agent), stateWidth)}${GAP}${mark}`;
  };

  if (agents.length === 0) {
    return [];
  }

  // Name, runtime · model · effort, mode, then state and mark.
  const cells = agents.map((agent) => {
    const file = defined(agent);

    return [
      agent.name,
      [file?.agent, file?.model, file?.effort]
        .filter((part) => part !== undefined)
        .join(' · '),
      file?.mode ?? '—',
      stateOf(agent),
    ];
  });

  const widths = cells[0]!.map((_, column) =>
    Math.max(0, ...cells.map((row) => stringWidth(row[column]!))),
  );
  const across = (some: readonly number[]) =>
    some.reduce((sum, each) => sum + each + GAP.length, 0) - GAP.length;
  const third = Math.max(1, Math.floor(width / 3));

  // The runtime's column, then the name's, wrap in a third of the width
  // while the row's own columns are wider than it.
  for (const column of [1, 0]) {
    if (across(widths) > width && widths[column]! > third) {
      widths[column] = third;
    }
  }

  // Still wider, the state goes under the row, and then the mode with it.
  const kept =
    across(widths) <= width ? 4 : across(widths.slice(0, 3)) <= width ? 3 : 2;
  const room = kept === 4 ? width - across(widths) - GAP.length : 0;
  const beside = room >= BESIDE;
  const runtimeAt = widths[0]! + GAP.length;
  // Beside, after the state's column; under, from the runtime's.
  const latestAt = beside ? width - room : runtimeAt;
  // Each row its own table, its columns as wide as all the rows' are: a
  // cell wider than its column wraps in it, after a ` · ` where it can.
  const columns = widths.slice(0, kept).map((each) => ({
    minWidth: each,
    maxWidth: each,
  }));

  return agents.map((agent, index) => {
    const row = cells[index]!;
    const own = new Table()
      .body([row.slice(0, kept)])
      .columns(columns)
      .padding(GAP.length)
      .toString()
      .split('\n')
      .map((line) => line.trimEnd());
    const state = ownState(agent);
    const mark = markOf(agent);
    // Under the row from the runtime's column: the mode where it went too,
    // the state and the mark, each whole, a line wrapping between them.
    const parts = [
      ...(kept === 2 ? [padded(row[2]!, widths[2]!)] : []),
      mark === undefined ? state : padded(state, stateWidth),
      ...(mark === undefined ? [] : [mark]),
    ];
    const placed: { line: number; at: number }[] = [];
    const down: string[] = [];

    if (kept < 4) {
      const indent = ' '.repeat(runtimeAt);

      for (const part of parts) {
        const last = down.at(-1);

        // String indices, not cells, for the paint: what goes before a
        // part in its line is as many code units as it is long.
        if (
          last !== undefined &&
          stringWidth(`${last}${GAP}${part}`.trimEnd()) <= width
        ) {
          placed.push({ line: down.length - 1, at: last.length + GAP.length });

          down[down.length - 1] = `${last}${GAP}${part}`;
        } else {
          placed.push({ line: down.length, at: indent.length });
          down.push(indent + part);
        }
      }
    } else {
      // The state's cell ends the row's first line, before a headline
      // beside it; a wide character before it is two cells and one or two
      // code units, so its place is counted from the end.
      const cell = row[3]!;
      const at = own[0]!.length - cell.length;

      placed.push(
        { line: 0, at },
        { line: 0, at: at + cell.length - (mark?.length ?? 0) },
      );
    }

    const latest = (agent.latest ?? '').replaceAll(/\s+/g, ' ').trim();
    const wrapped =
      latest === ''
        ? []
        : wrapAnsi(latest, Math.max(1, width - latestAt), {
            hard: true,
            trim: true,
          }).split('\n');
    const lines = beside
      ? Array.from({ length: Math.max(own.length, wrapped.length) }, (_, at) =>
          at < wrapped.length
            ? padded(own[at] ?? '', latestAt) + wrapped[at]!
            : own[at]!,
        )
      : [
          ...own,
          ...down.map((line) => line.trimEnd()),
          ...wrapped.map((line) => ' '.repeat(latestAt) + line),
        ];
    const below = kept < 4 ? own.length : 0;
    const [statePlace, markPlace] = [
      placed[kept === 2 ? 1 : 0]!,
      placed.at(-1)!,
    ];

    return {
      text: lines[0]!,
      state: [statePlace.at, statePlace.at + state.length],
      stateLine: below + statePlace.line,
      ...(mark === undefined
        ? {}
        : { mark: [markPlace.at, markPlace.at + mark.length] }),
      markLine: below + markPlace.line,
      under: lines.slice(1),
      agent,
    };
  });
}
