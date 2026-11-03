/**
 * `/team`'s words read, and what chord says of a run, whoever hosts it. Nothing
 * here reads a file or a session; the host gathers what each needs.
 */
import type { FoundTeam } from '../teams.ts';
import { formatElapsed } from './elapsed.ts';

/** What only the host can say, as it names where the host shows things. */
export interface TeamWords {
  /** Answers `/team stop` with no run, which has to say where runs are named. */
  readonly whichRun: string;
  /** Ends what `/team stop` says of a lead closed alone: where to find it. */
  readonly closedLead: string;
  /** Ends what `/team stop` says of a lead and members: where to find them. */
  readonly closedRun: string;
  /** Ends what `/team stop` says of no such run: where runs are named. */
  readonly noRun: string;
}

/** A team file as the picker lists it, its path as the window shows it. */
export type ListedTeam = FoundTeam & { readonly shown: string };

/** A team's runs open in the window, as the picker and `/team show` read them. */
export interface TeamRun {
  readonly id?: string;
  /** The team's file name. */
  readonly team: string;
  /** The run's name, its lead's: `bugfix`, `bugfix 2`. */
  readonly name: string;
  /** When its lead opened, on chord's clock. */
  readonly since: number;
}

/** What `/team`'s picker and names read: the teams, the runs, the two places. */
export interface TeamListing {
  readonly teams: readonly ListedTeam[];
  readonly runs: readonly TeamRun[];
  readonly dirs: { readonly project: string; readonly user?: string };
}

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
export function teamCommand(
  args: string,
  { whichRun }: TeamWords,
): TeamCommand {
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
        ? { form: 'refused', problem: whichRun }
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
export function stoppedLine(
  run: string,
  members: readonly string[],
  words: TeamWords,
): string {
  return members.length === 0
    ? `Stopped ${run}: its lead is closed · ${words.closedLead}`
    : `Stopped ${run}: ${andList(['its lead', ...members])} are closed · ` +
        words.closedRun;
}

/** What chord says with no team saved. */
export const NO_TEAMS =
  'No teams yet. /team new and a few words about the work makes one.';

/** The lead's role, which the file has no line for. */
export const LEAD_ROLE =
  'Splits the job, says who edits which files, reports to main';

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

/** Where teams are saved, whole. */
export function teamsSaved(dirs: {
  readonly project: string;
  readonly user?: string | undefined;
}): string {
  return dirs.user === undefined
    ? `Saved for this project in ${dirs.project}.`
    : `Saved for this project in ${dirs.project}, and for every project in ${dirs.user}.`;
}

/** The first unit of an elapsed time: `41s`, `6m`. */
export function briefly(ms: number): string {
  return formatElapsed(ms).split(' ')[0]!;
}
