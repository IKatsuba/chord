/**
 * What chord's commands say under `chord acp`: plain text for a client's own
 * interface, which may render it as markdown and in a proportional font, so one
 * thing a line, no columns and no angle brackets.
 */
import type { SessionNotification } from '@agentclientprotocol/sdk/unstable';
import type { Team } from '../teams.ts';
import {
  briefly,
  LEAD_ROLE,
  type ListedTeam,
  NO_TEAMS,
  type TeamListing,
  type TeamRun,
  teamsSaved,
  type TeamWords,
} from './team_command.ts';

/** `/team`'s words where no window shows a list under a prompt. */
export const ACP_TEAM_WORDS: TeamWords = {
  whichRun: 'Which run? /team lists them',
  closedLead: "chord with its agent's name and -r lists it",
  closedRun: "chord with each agent's name and -r lists them",
  noRun: '/team lists them',
};

/** What a command came to, and whether it was refused. */
export interface CommandSaid {
  readonly text: string;
  readonly failed: boolean;
}

/** A command's one chunk, marked as chord's. */
export function commandChunk(
  sessionId: string,
  name: string,
  text: string,
  failed: boolean,
): SessionNotification {
  return {
    sessionId,
    update: {
      sessionUpdate: 'agent_message_chunk',
      content: { type: 'text', text },
      _meta: { 'chord/command': { name, failed } },
    },
  };
}

/**
 * What a file says, on one line: a repo's file must not make rows or blocks of
 * its own in what chord says. A client treats it as untrusted, as an agent's.
 */
const oneLine = (text: string) =>
  text.replaceAll(/\s*[\n\v\f\r\u0085\u2028\u2029]+\s*/g, ' ').trim();

const joined = (parts: readonly (string | undefined)[]) =>
  parts
    .flatMap((part) => (part === undefined ? [] : [oneLine(part)]))
    .join(' · ');

function teamRow(found: ListedTeam, runs: readonly TeamRun[], now: number) {
  if ('problem' in found) {
    return `- ${joined([found.name, `not read: ${found.problem}`])}`;
  }

  const { team } = found;
  const own = runs.filter((run) => run.team === found.name);
  const runtimes = new Set([
    team.lead.agent,
    ...team.members.map(({ agent }) => agent),
  ]);

  return `- ${joined([
    found.name,
    `${team.members.length + 1} agents`,
    [...runtimes].join(', '),
    found.place === 'user'
      ? 'every project'
      : found.hides
        ? "this project · hides every project's"
        : 'this project',
    own.length === 0
      ? undefined
      : own.length === 1
        ? `working ${briefly(now - own[0]!.since)}`
        : `${own.length} runs`,
    team.description,
  ])}`;
}

/** `/team list`: the teams, the runs, where they are saved, what to type. */
export function teamsText(
  { teams, runs, dirs }: TeamListing,
  now: number,
): string {
  return [
    teams.length === 0
      ? NO_TEAMS
      : `Teams:\n\n${teams.map((found) => teamRow(found, runs, now)).join('\n')}`,
    runs.length === 0
      ? 'No run is open.'
      : `Runs open:\n\n${runs
          .map(
            ({ name, team, since }) =>
              `- ${name} · team ${team} · working ${briefly(now - since)}`,
          )
          .join('\n')}`,
    teamsSaved(dirs),
    ...(teams.length === 0
      ? []
      : [
          '/team show and a name shows a team; /team run, a name and a job starts one.',
        ]),
  ].join('\n\n');
}

type Defined = Team['lead'];

const agentParts = ({ agent, model, effort, mode }: Defined) => [
  agent,
  model,
  effort,
  mode,
];

/** `/team show` of a team not running. */
export function teamText(name: string, file: string, team: Team): string {
  return [
    joined([name, file]),
    oneLine(team.description),
    `Agents:\n\n${[
      `- ${joined(['lead', ...agentParts(team.lead), LEAD_ROLE])}`,
      ...team.members.map(
        (member) =>
          `- ${joined([member.name, ...agentParts(member), member.role])}`,
      ),
    ].join('\n')}`,
  ].join('\n\n');
}

/** `/team show` of a run: its header, whole, and which of its agents are open. */
export function runText({
  name,
  file,
  team,
  job,
  since,
  open,
  now,
}: {
  readonly name: string;
  readonly file: string;
  readonly team: Team;
  readonly job: string;
  readonly since: number;
  /** Its members open now, by name. */
  readonly open: readonly string[];
  readonly now: number;
}): string {
  return [
    `${name} · ${file} · working ${briefly(now - since)} on "${job.replaceAll(/\s+/g, ' ').trim()}"`,
    oneLine(team.description),
    `Agents:\n\n${[
      `- ${joined([`lead (${name})`, 'open', ...agentParts(team.lead), LEAD_ROLE])}`,
      ...team.members.map(
        (member) =>
          `- ${joined([
            member.name,
            open.includes(member.name) ? 'open' : 'not open',
            ...agentParts(member),
            member.role,
          ])}`,
      ),
    ].join('\n')}`,
  ].join('\n\n');
}

/** Why `/team show` shows no selected run: only a window draws its receipt. */
export function selectedRunRefusal(typed: string, runId: string): string {
  return (
    `${typed} is a selected run, and only chord's window shows its receipt: ` +
    `chord -r with this session's id, then /team show ${runId} there`
  );
}

const withNote = (words: string, note: string | undefined) =>
  note === undefined ? words : `${words}\n\n${note}`;

/** `/team run`, started. */
export function startedText(team: string, lead: string, note?: string): string {
  return withNote(
    `Team ${team} started. Its lead is ${lead}; /team stop ${lead} ends it.`,
    note,
  );
}

/** `/new`, opened. */
export function openedText(
  name: string,
  runtime: string,
  note?: string,
): string {
  return withNote(
    `Opened ${name} (${runtime}). It is idle, with no prompt yet; main's ` +
      'send_message starts it, so ask main to send it the work.',
    note,
  );
}

/** A command with other blocks beside it. */
export function notAloneRefusal(name: string): string {
  return (
    `/${name} takes text alone, and this prompt had other blocks beside it. ` +
    'Nothing ran; send the command by itself.'
  );
}
