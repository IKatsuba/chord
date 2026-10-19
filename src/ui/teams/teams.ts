/**
 * `/team`, kept out of the window: which form was typed, the words chord
 * hands main and says under the command, the teams picker's rows, and
 * `/team show`'s table of a running team. Nothing here reads a file or a
 * session; the window gathers what each needs.
 */
import { Table } from '@cliffy/table';
import cliTruncate from 'cli-truncate';
import stringWidth from 'string-width';
import { formatElapsed } from '../../session/elapsed.ts';
import type {
  MessageFrom,
  TeamAgentShown,
  TeamRunShown,
} from '../../session/transcript/types.ts';
import type { FoundTeam, Team } from '../../teams.ts';
import { GLYPHS } from '../app/strip.ts';
import type { PickerChoice } from '../pickers/picker.ts';
import { messageHeader } from '../transcript/message.ts';

/** What `/team` was asked, by the words after it. */
export type TeamCommand =
  | { readonly form: 'list' }
  | { readonly form: 'new'; readonly words: string }
  | { readonly form: 'show'; readonly name: string }
  | { readonly form: 'run'; readonly name: string; readonly job: string }
  | { readonly form: 'stop'; readonly name: string }
  /** Words `/team` cannot read, and what it says of them. */
  | { readonly form: 'refused'; readonly problem: string };

/**
 * `/team`'s words read: the form, then a team's name, then the rest, which
 * is a new team's description or a job. `stop` takes a run's
 * name whole, as a second run is `bugfix 2`.
 */
export function teamCommand(args: string): TeamCommand {
  const [, form = '', rest = ''] =
    /^(\S*)\s*([\s\S]*)$/.exec(args.trim()) ?? [];
  const [, name = '', words = ''] = /^(\S*)\s*([\s\S]*)$/.exec(rest) ?? [];
  const which = 'Which team? /team lists them';

  switch (form) {
    case '':
    case 'list':
      return { form: 'list' };
    case 'new':
      return rest === ''
        ? {
            form: 'refused',
            problem: '/team new takes a few words about the work the team does',
          }
        : { form: 'new', words: rest };
    case 'show':
      return name === ''
        ? { form: 'refused', problem: which }
        : { form: 'show', name };
    case 'run':
      return name === ''
        ? { form: 'refused', problem: which }
        : words === ''
          ? {
              form: 'refused',
              problem: `/team run ${name} takes the job after the name`,
            }
          : { form: 'run', name, job: words };
    case 'stop':
      return rest === ''
        ? {
            form: 'refused',
            problem: 'Which run? The list under the prompt names them',
          }
        : { form: 'stop', name: rest.replaceAll(/\s+/g, ' ') };
    default:
      return {
        form: 'refused',
        problem: `/team has no ${form}; it takes list, new, show, run or stop`,
      };
  }
}

/** `a, b and c`. */
export function andList(names: readonly string[]): string {
  return new Intl.ListFormat('en', { type: 'conjunction' }).format(names);
}

/**
 * What main gets for `/team new <words>`: the words, after one line that
 * names the tool which makes a team, so the agent proposes one rather than
 * answers in prose.
 */
export function newTeamPrompt(words: string): string {
  return (
    'The person asks for a team of agents through /team new: work ' +
    "out the team for what they describe below, then call chord's " +
    "propose_team with it (list_agents gives each runtime's models and " +
    `modes).\n\n${words}`
  );
}

/**
 * What chord tells main, ahead of its next turn, of a run the person
 * started with `/team run`, which main took no part in.
 */
export function ranNote(team: string, lead: string, job: string): string {
  return (
    `The person handed team ${team} this job: "${job}". Its lead is ` +
    `@${lead} and reports to you; send_message reaches it.`
  );
}

/**
 * Why `/team run` or `/team show` found no team by `name`, or a file that
 * is not one.
 */
export function teamRefusal(
  name: string,
  found: ListedTeam | undefined,
): string | undefined {
  if (found === undefined) {
    return `No team named ${name} · /team lists them`;
  }

  return 'problem' in found
    ? `${found.shown} is not a team chord can run:\n${found.problem}`
    : undefined;
}

/**
 * What `/team stop` says of the run it closed: its lead, and the members
 * open with it.
 */
export function stoppedLine(run: string, members: readonly string[]): string {
  return members.length === 0
    ? `Stopped ${run}: its lead is closed · /resume lists it`
    : `Stopped ${run}: ${andList(['its lead', ...members])} are closed · ` +
        '/resume lists them';
}

/** A team's runs open in the window, as the picker and `/team show` read them. */
export interface TeamRun {
  /** The team's file name. */
  readonly team: string;
  /** The run's name, its lead's: `bugfix`, `bugfix 2`. */
  readonly name: string;
  /** When its lead opened, on chord's clock. */
  readonly since: number;
}

/** A team file as the picker lists it, its path as the window shows it. */
export type ListedTeam = FoundTeam & { readonly shown: string };

/** What `/team`'s picker and names read: the teams, the runs, the two places. */
export interface TeamListing {
  readonly teams: readonly ListedTeam[];
  readonly runs: readonly TeamRun[];
  readonly dirs: { readonly project: string; readonly user?: string };
}

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

/** The first unit of an elapsed time: `41s`, `6m`. */
function briefly(ms: number): string {
  return formatElapsed(ms).split(' ')[0]!;
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
  if (dirs.user === undefined) {
    return `Saved for this project in ${dirs.project}.`;
  }

  return columns < NARROW
    ? `For this project in ${dirs.project}, for every project in ${dirs.user}.`
    : `Saved for this project in ${dirs.project}, and for every project in ${dirs.user}.`;
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

/** What the picker says with no team saved. */
export const NO_TEAMS =
  'No teams yet. /team new and a few words about the work makes one.';

/**
 * What Enter on a team puts in the draft: a run's start. A broken file has
 * nothing to start, so Enter on it leaves the picker open.
 */
export function pickedDraft(found: FoundTeam): string | undefined {
  return 'problem' in found ? undefined : `/team run ${found.name} `;
}

/**
 * The line `/team show` opens a running team with: its name, its file and
 * how long it has worked on what, the job cut to fit.
 */
export function runningHeader(
  name: string,
  file: string,
  run: TeamRunShown,
  width: number,
): string {
  const start = `${name} · ${file} · working ${briefly(
    run.at - run.since,
  )} on "`;
  const job = run.job.replaceAll(/\s+/g, ' ').trim();
  const room = Math.max(1, width - stringWidth(start) - 1);

  // A cut at a space would leave it before the ellipsis.
  return `${start}${
    stringWidth(job) <= room
      ? job
      : cliTruncate(job, room).replace(/\s+…$/, '…')
  }"`;
}

/** One running agent's row laid out, and where its state is in it. */
export interface RunningLine {
  readonly text: string;
  /** The state's cells, `[start, end)` in `text`, to paint by its tone. */
  readonly state: readonly [number, number];
  /** Its mark's cells after the state, to paint by the mark's tone. */
  readonly mark?: readonly [number, number];
  readonly agent: TeamAgentShown;
}

/** What a member not open says in the state column. */
export const NOT_OPENED = 'not opened';

/** The least of the latest headline the running table keeps its effort for. */
const MIN_LATEST = 12;

/**
 * `/team show`'s running table: each agent's name, `runtime · model`,
 * effort and mode from the file, then its state and its latest headline,
 * cut to `width`, the headline first. The effort is a column where an agent
 * sets one, as the proposal's table has it, and gives way to the headline
 * where that would keep fewer than `MIN_LATEST` cells, as what each agent
 * is on now is what this form is for.
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
      : `${ownState(agent).padEnd(stateWidth)}${GAP}${mark}`;
  };

  const cellsOf = (effort: boolean) =>
    agents.map((agent) => {
      const file = defined(agent);

      return [
        agent.name,
        [file?.agent, file?.model]
          .filter((part) => part !== undefined)
          .join(' · '),
        ...(effort ? [file?.effort ?? '—'] : []),
        file?.mode ?? '—',
        stateOf(agent),
      ];
    });

  const laidOut = (cells: string[][]) => {
    const widths = cells[0]!.map((_, column) =>
      Math.max(0, ...cells.map((row) => stringWidth(row[column]!))),
    );
    const before = widths
      .slice(0, -1)
      .reduce((sum, each) => sum + each + GAP.length, 0);

    return {
      before,
      room: width - before - widths.at(-1)! - GAP.length,
    };
  };

  if (agents.length === 0) {
    return [];
  }

  const withEffort = cellsOf(true);
  const effort =
    agents.some((agent) => defined(agent)?.effort !== undefined) &&
    laidOut(withEffort).room >= MIN_LATEST;
  const cells = effort ? withEffort : cellsOf(false);
  const { before, room: left } = laidOut(cells);
  const room = Math.max(1, left);
  const laid = new Table()
    .body(
      cells.map((row, index) => {
        const latest = agents[index]!.latest ?? '';

        return [
          ...row,
          stringWidth(latest) <= room ? latest : cliTruncate(latest, room),
        ];
      }),
    )
    .padding(GAP.length)
    .toString()
    .split('\n');

  return agents.map((agent, index) => {
    const state = ownState(agent);
    const mark = markOf(agent);
    const markAt = before + stateWidth + GAP.length;

    return {
      text: (laid[index] ?? '').trimEnd(),
      state: [before, before + state.length],
      ...(mark === undefined ? {} : { mark: [markAt, markAt + mark.length] }),
      agent,
    };
  });
}
