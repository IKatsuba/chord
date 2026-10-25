/**
 * Team files: a team's agents in YAML frontmatter, how the team works in the
 * markdown body after it. They live in `.chord/teams/` for the project and in
 * `teams/` beside the user's settings file for every project, and are read
 * whenever they are needed, never at start, so a file saved elsewhere counts
 * at once.
 */
import { z } from '@zod/zod';
import { agentName, agentNameProblem } from './agent_name.ts';
import { VFile } from 'vfile';
import { matter } from 'vfile-matter';
import { stringify } from 'yaml';
import { isDeepStrictEqual } from 'node:util';
import { basename, dirname, extname, join } from 'node:path';
import {
  mkdir,
  readdir,
  readFile,
  rename,
  rm,
  writeFile,
} from 'node:fs/promises';
import { notFound } from './not_found.ts';
import { userSettingsFile } from './settings.ts';
import type { TeamPart } from './session/transcript/types.ts';

/** A team's name, which is also its lead's name in the list and messages. */
const TEAM_NAME = /^[a-z][a-z0-9-]{0,23}$/;
/** A member's name, short enough for the list's name column. */
const MEMBER_NAME = /^[a-z][a-z0-9-]{0,15}$/;
/** Names that already mean an agent of the session. */
const TAKEN = ['main', 'chord'];
/** The most members one lead holds, as it is one of main's 8 children. */
export const MAX_MEMBERS = 8;

const oneLine = (max: number) =>
  z
    .string()
    .min(1)
    .max(max)
    .refine((text) => !/[\r\n]/.test(text), {
      message: 'must be one line',
    });

/**
 * The frontmatter's schema. Model, effort and mode ids are not checked here:
 * only an agent's runtime knows them, and starting every runtime to read a file
 * would cost more than a refused open does.
 */
function frontmatterSchema(name: string, runtimes: readonly string[]) {
  const agent = z
    .string()
    .min(1)
    .refine((id) => runtimes.includes(id), {
      error: (issue) => `chord knows no runtime named ${String(issue.input)}`,
    });
  const lead = z.strictObject({
    agent,
    model: z.string().min(1).optional(),
    effort: z.string().min(1).optional(),
    mode: z.string().min(1).optional(),
    instructions: z.string().min(1).optional(),
  });
  const member = z.strictObject({
    name: agentName
      .regex(MEMBER_NAME, {
        message: 'must be a lowercase letter, then up to 15 of a-z, 0-9 and -',
      })
      .refine((id) => !TAKEN.includes(id) && id !== name, {
        error: (issue) => `${String(issue.input)} is taken`,
      }),
    role: oneLine(80),
    agent,
    model: z.string().min(1).optional(),
    effort: z.string().min(1).optional(),
    mode: z.string().min(1).optional(),
    instructions: z.string().min(1),
  });

  return z.strictObject({
    description: oneLine(200),
    lead,
    members: z
      .array(member)
      .min(1)
      .max(MAX_MEMBERS)
      .superRefine((members, context) => {
        members.forEach((one, index) => {
          if (members.findIndex((other) => other.name === one.name) < index) {
            context.addIssue({
              code: 'custom',
              path: [index, 'name'],
              message: `${one.name} is named twice`,
            });
          }
        });
      }),
  });
}

export type Frontmatter = z.infer<ReturnType<typeof frontmatterSchema>>;
export type TeamLead = Frontmatter['lead'];
export type TeamMember = Frontmatter['members'][number];

/** A team as its file says it, checked. */
export interface Team extends Frontmatter {
  /** How the team works, in markdown, without the blank lines around it. */
  readonly body: string;
}

/** Where a team is saved. */
export type TeamPlace = 'project' | 'user';

/** A team file found, read and checked, or the first problem with it. */
export type FoundTeam = {
  readonly name: string;
  readonly file: string;
  readonly place: TeamPlace;
  /** A project's team that hides the user's file of the same name. */
  readonly hides: boolean;
} & ({ readonly team: Team } | { readonly problem: string });

/** The two directories teams are saved in; none for the user without a home. */
export function teamDirs({
  configHome,
  cwd,
}: {
  configHome: string | undefined;
  cwd: string;
}): { project: string; user: string | undefined } {
  const settings = userSettingsFile(configHome);

  return {
    project: join(cwd, '.chord', 'teams'),
    user: settings === undefined ? undefined : join(dirname(settings), 'teams'),
  };
}

/** The file a team of `name` is saved to in `dir`. */
export function teamFile(dir: string, name: string): string {
  return join(dir, `${name}.md`);
}

/** Why `name` cannot name a team, or undefined when it can. */
export function teamNameProblem(name: string): string | undefined {
  return (
    agentNameProblem(name) ??
    (!TEAM_NAME.test(name)
      ? `the name ${name} must be a lowercase letter, then up to 23 of a-z, 0-9 and -`
      : TAKEN.includes(name)
        ? `the name ${name} is taken`
        : undefined)
  );
}

/** zod's message for a key left out, which `problemOf` words on its own. */
const MISSING = 'missing';

/**
 * zod's issue in its path's words, as the settings files' problems are:
 * `members.1.agent is missing`.
 */
function problemOf(issue: z.core.$ZodIssue): string {
  const path = issue.path.map(String).join('.');

  if (path === '') {
    return issue.code === 'invalid_type'
      ? 'the frontmatter is not a YAML mapping'
      : issue.message.toLowerCase();
  }

  return issue.message === MISSING
    ? `${path} is missing`
    : issue.code === 'unrecognized_keys'
      ? `${path}.${issue.keys[0]} is not a key a team has`
      : `${path}: ${issue.message.charAt(0).toLowerCase()}${issue.message.slice(
          1,
        )}`;
}

/**
 * Checks a team's parts: its name, the frontmatter's structure and runtimes
 * against `runtimes`, and a body that is not empty. The answer is the team or
 * its first problem.
 */
export function checkTeam(
  name: string,
  frontmatter: unknown,
  body: string,
  runtimes: readonly string[],
): { team: Team } | { problem: string } {
  const named = teamNameProblem(name);

  if (named !== undefined) {
    return { problem: named };
  }

  const result = frontmatterSchema(name, runtimes).safeParse(frontmatter, {
    error: (issue) =>
      issue.code === 'invalid_type' && issue.input === undefined
        ? MISSING
        : undefined,
  });

  if (!result.success) {
    const [issue] = result.error.issues;

    return { problem: issue === undefined ? 'not a team' : problemOf(issue) };
  }

  const trimmed = body.trim();

  return trimmed === ''
    ? { problem: 'the body is empty' }
    : { team: { ...result.data, body: trimmed } };
}

/**
 * The shape `propose_team` takes, for the agent to read as JSON Schema: the
 * team file's parts by their JSON types, with what each is for. The MCP SDK
 * refuses a call whose types are wrong in zod's words; `checkProposal` checks
 * the rest, as a file is checked.
 */
export function proposalShape() {
  const agent = z.string().describe('The runtime, as list_agents names it');
  const model = z
    .string()
    .optional()
    .describe(
      "A model id list_agents gives for the runtime; the runtime's own if " +
        'left out',
    );
  const effort = z
    .string()
    .optional()
    .describe(
      'An effort the runtime offers for that model, by its id, as ' +
        "list_agents lists them (`efforts`); the runtime's own if left out. " +
        'One it does not take starts the agent on its own',
    );
  const mode = z
    .string()
    .optional()
    .describe(
      'A mode id list_agents gives for the runtime: the permissions it works ' +
        "under, which the person approves; the runtime's own if left out",
    );

  return {
    name: z
      .string()
      .describe(
        "The team's name and its file's: a lowercase letter, then up to 23 of " +
          'a-z, 0-9 and -; not main or chord',
      ),
    description: z
      .string()
      .describe('What the team is for, one line of at most 200 characters'),
    lead: z
      .object({
        agent,
        model,
        effort,
        mode,
        instructions: z
          .string()
          .optional()
          .describe(
            'How the lead works: when it opens which member, what it does itself',
          ),
      })
      .describe(
        'The lead, which opens the members, names who edits which files and ' +
          'reports to main',
      ),
    members: z
      .array(
        z.object({
          name: z
            .string()
            .describe(
              'A lowercase letter, then up to 15 of a-z, 0-9 and -; unique, not ' +
                "main, chord or the team's name",
            ),
          role: z.string().describe('What it does, one line of at most 80'),
          agent,
          model,
          effort,
          mode,
          instructions: z.string().describe('How it does its part, in full'),
        }),
      )
      .describe(`1 to ${MAX_MEMBERS} members`),
    body: z
      .string()
      .describe(
        'How the team works, in markdown, which every agent of it reads: the ' +
          'steps, a "Who edits what" section (one writer per file, how members ' +
          'agree on files, that other runs of a team may work here too) and a ' +
          '"Reporting" section (when the lead writes to main)',
      ),
  };
}

/**
 * A proposed team checked as its file would be, from `propose_team`'s
 * arguments: its name and the team, or the first problem.
 */
export function checkProposal(
  input: unknown,
  runtimes: readonly string[],
): { name: string; team: Team } | { problem: string } {
  const { name, body, ...frontmatter } =
    typeof input === 'object' && input !== null
      ? (input as Record<string, unknown>)
      : {};

  if (typeof name !== 'string') {
    return { problem: 'name is missing' };
  }

  const checked = checkTeam(
    name,
    frontmatter,
    typeof body === 'string' ? body : '',
    runtimes,
  );

  return 'team' in checked ? { name, team: checked.team } : checked;
}

/** How one of a team's agents changed against the team saved before. */
export type RowChange = 'added' | 'changed' | 'removed';

/**
 * Each agent's change from `before` to `after`: the lead's apart, since a
 * member may be named `lead` too, and each member's by its name, new, gone
 * or set otherwise; none where it is the same.
 */
export function teamChanges(
  before: Team,
  after: Team,
): { lead?: RowChange; members: ReadonlyMap<string, RowChange> } {
  const members = new Map<string, RowChange>();

  for (const member of after.members) {
    const old = before.members.find((each) => each.name === member.name);

    if (old === undefined) {
      members.set(member.name, 'added');
    } else if (!isDeepStrictEqual(old, member)) {
      members.set(member.name, 'changed');
    }
  }

  for (const member of before.members) {
    if (!after.members.some((each) => each.name === member.name)) {
      members.set(member.name, 'removed');
    }
  }

  return isDeepStrictEqual(before.lead, after.lead)
    ? { members }
    : { lead: 'changed', members };
}

/** Reads a team file's text, as `checkTeam` checks it. */
export function parseTeam(
  name: string,
  text: string,
  runtimes: readonly string[],
): { team: Team } | { problem: string } {
  // As bytes, the file is read by vfile's own UTF-8 decoder, which drops a
  // leading BOM as Deno's reader of front matter did; a string keeps it.
  const file = new VFile(new TextEncoder().encode(text));
  const read = file.value;

  try {
    matter(file, { strip: true });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);

    return {
      problem: `the frontmatter is not valid YAML (${message.split('\n')[0]})`,
    };
  }

  // vfile-matter reads a file with none as an empty mapping; only whether it
  // stripped anything tells the two apart.
  if (file.value === read) {
    return { problem: 'no frontmatter between --- lines' };
  }

  return checkTeam(name, file.data.matter, String(file), runtimes);
}

/** A team as its file holds it: the frontmatter between `---` lines, then the body. */
export function teamText({ body, ...frontmatter }: Team): string {
  return `---\n${stringify(frontmatter)}---\n\n${body}\n`;
}

/** The teams saved in `dir`, by name; none for a directory that is not there. */
async function teamsIn(
  dir: string | undefined,
): Promise<{ name: string; file: string }[]> {
  if (dir === undefined) {
    return [];
  }

  const found: { name: string; file: string }[] = [];

  try {
    for (const entry of await readdir(dir, { withFileTypes: true })) {
      if (!entry.isDirectory() && extname(entry.name) === '.md') {
        found.push({
          name: basename(entry.name, '.md'),
          file: join(dir, entry.name),
        });
      }
    }
  } catch (error) {
    if (!notFound(error)) {
      throw error;
    }
  }

  return found;
}

/**
 * Every team file, by name: the project's and the user's, the project's
 * winning a name both have, as the project's settings sit on top of the
 * user's. A file that fails the check is listed with its first problem, so
 * the person sees it and can fix it.
 */
export async function findTeams(
  where: { configHome: string | undefined; cwd: string },
  runtimes: readonly string[],
): Promise<FoundTeam[]> {
  const dirs = teamDirs(where);
  const project = await teamsIn(dirs.project);
  const user = await teamsIn(dirs.user);
  const shadowed = new Set(project.map(({ name }) => name));
  const files = [
    ...project.map((found) => ({
      ...found,
      place: 'project' as const,
      hides: user.some(({ name }) => name === found.name),
    })),
    ...user
      .filter(({ name }) => !shadowed.has(name))
      .map((found) => ({
        ...found,
        place: 'user' as const,
        hides: false,
      })),
  ].sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0));

  return await Promise.all(
    files.map(async (found) => {
      try {
        const text = await readFile(found.file, 'utf8');

        return { ...found, ...parseTeam(found.name, text, runtimes) };
      } catch (error) {
        return {
          ...found,
          problem: `cannot be read (${
            error instanceof Error ? error.message : String(error)
          })`,
        };
      }
    }),
  );
}

/**
 * Writes a team to `file` as `saveSetting` writes a settings file: to a file
 * beside it that is renamed over the old, so a failed write leaves nothing
 * half-written. A missing directory is made.
 */
export async function saveTeam(file: string, team: Team): Promise<void> {
  await mkdir(dirname(file), { recursive: true });

  const temporary = `${file}.${crypto.randomUUID()}.tmp`;

  try {
    await writeFile(temporary, teamText(team));
    await rename(temporary, file);
  } catch (error) {
    await rm(temporary).catch(() => {});

    throw error;
  }
}

/** `a, b and c`. */
function listed(names: readonly string[]): string {
  return new Intl.ListFormat('en', { type: 'conjunction' }).format(names);
}

/**
 * A member as the team part lists it: name, role, runtime · model · effort ·
 * mode.
 */
function memberLine(member: TeamMember): string {
  return `- ${member.name}: ${member.role} (${[
    member.agent,
    member.model,
    member.effort,
    member.mode,
  ]
    .filter((part) => part !== undefined)
    .join(' · ')})`;
}

/** Who a team part is for: a run's lead, or one of its members. */
export type TeamRole =
  | {
      /** The run's lead, by the name chord gave it: `bugfix`, `bugfix 2`. */
      readonly lead: string;
      /** The leads of the other runs open in the session, by their names. */
      readonly others: readonly string[];
    }
  | { readonly member: TeamMember; readonly lead: string };

/**
 * The team part a lead or member gets ahead of its first message: chord's
 * standing words, which say only the mechanics (its tools, the names it
 * reaches, the directory), then the file's words: its instructions, the
 * members and how the team works. How files are shared and when to report
 * are the file's, where the person reads and changes them.
 */
export function teamPart(
  name: string,
  team: Team,
  role: TeamRole,
  cwd: string,
): TeamPart {
  const members = team.members.map(memberLine).join('\n');
  const how = `How the team works:\n${team.body}`;

  if ('member' in role) {
    const { member, lead } = role;
    const others = team.members
      .filter((each) => each !== member)
      .map((each) => each.name);

    return {
      team: name,
      member: member.name,
      text: [
        `You are ${member.name}, a member of team ${name}, opened by its ` +
          `lead, ${lead}. You work in ${cwd}, beside the team's other ` +
          'members: there are no worktrees.',
        "Your tools on chord's server: send_message {to, text} reaches " +
          `your lead, ${lead}, and ${
            others.length === 0 ? '' : `${listed(others)}, `
          }the team's other members while they are open, by name and ` +
          'directly: the lead does not see those. spawn_task and ' +
          'list_agents start task agents for one-off jobs. You open no ' +
          'long-lived agents.',
        `Your role: ${member.role}`,
        `Your instructions:\n${member.instructions.trim()}`,
        `The members:\n${members}`,
        how,
      ].join('\n\n'),
    };
  }

  const runs =
    role.others.length === 0
      ? 'No other run of a team is open in this session.'
      : `Other runs open in this session, whose leads send_message reaches by ` +
        `these names: ${listed(role.others)}.`;

  return {
    team: name,
    text: [
      `You are the lead of team ${name}${
        role.lead === name ? '' : `, running as ${role.lead}`
      }: a long-lived agent chord opened for main, the session the person ` +
        `talks to. You work in ${cwd}, and so does every member you open: ` +
        'there are no worktrees.',
      "Your tools on chord's server: open_agent {member, prompt} opens one " +
        'of the members below on the runtime, model, effort and mode the ' +
        'team gives it, with your prompt as its first message. ' +
        'send_message {to, text} reaches main, your open members by name, and the leads of the ' +
        'other runs. close_agent {to} closes a member; close each when its ' +
        'part is done. spawn_task and list_agents start task agents for ' +
        'one-off jobs. Each message of yours to main goes into the turn main ' +
        "is in, where its runtime takes that, or else starts a turn of main's.",
      runs,
      ...(team.lead.instructions === undefined
        ? []
        : [`Your instructions:\n${team.lead.instructions.trim()}`]),
      `The members:\n${members}`,
      how,
    ].join('\n\n'),
  };
}
