/**
 * Finding an earlier session to resume among chord's own session records:
 * the latest one for an agent and a directory (`--continue`), one by the
 * agent's id for it (`--resume <id>`), or every one there or in any
 * directory (`/resume`).
 */
import { join } from 'node:path';
import { readdir, readFile } from 'node:fs/promises';
import { notFound } from '../not_found.ts';
import { parseRecord, promptLine, recordsDir } from './record.ts';

/** An earlier session to open again, and what chord knows of it. */
export interface Resume {
  /**
   * The agent's own id for the session: the ACP session id, which the agent
   * loads it by, and which chord prints on quit.
   */
  readonly sessionId: string;
  /** The directory the session works in. */
  readonly cwd: string;
  /**
   * The file of chord's record of it, which holds its past and goes on
   * gathering the conversation; none when chord never saw the session.
   */
  readonly record?: string | undefined;
  /** When it was last used, epoch milliseconds, where its record says. */
  readonly lastUsedAt?: number | undefined;
  /** Its first prompt, on one line, where its record says. */
  readonly prompt?: string | undefined;
  /** An agent another started's name or task, where its record says. */
  readonly name?: string | undefined;
}

/** Why there is nothing to resume: a sentence to show the person. */
export class ResumeError extends Error {
  override name = 'ResumeError';
}

/** What a record says of its session, as finding and listing need it. */
export interface SessionRecord {
  /** The record's file. */
  readonly path: string;
  readonly sessionId: string;
  readonly agent: string;
  readonly cwd: string;
  /** When its last prompt was sent, epoch milliseconds. */
  readonly lastUsedAt: number;
  /** Its first prompt, on one line. */
  readonly prompt: string;
  /** A task agent's: the session that started it, by the agent's id. */
  readonly parent?: string;
  /** An agent another started's: its name, or its task's description. */
  readonly name?: string;
}

/**
 * Every session record in `stateDir` a prompt was sent in. Only the first
 * line and the prompts are parsed, as a list needs no more; the past is read
 * when a session is opened.
 */
export async function readRecords(stateDir: string): Promise<SessionRecord[]> {
  const dir = recordsDir(stateDir);
  const paths: string[] = [];

  try {
    for (const entry of await readdir(dir, { withFileTypes: true })) {
      if (entry.isFile() && entry.name.endsWith('.jsonl')) {
        paths.push(join(dir, entry.name));
      }
    }
  } catch (error) {
    if (notFound(error)) {
      return [];
    }

    throw error;
  }

  const read = await Promise.all(
    paths.map(async (path) => {
      try {
        return summaryOf(path, await readFile(path, 'utf8'));
      } catch {
        // Gone since the directory was read, or unreadable: not offered.
        return undefined;
      }
    }),
  );

  return read.filter((record) => record !== undefined);
}

/** What `path`'s record says of its session; none for one never prompted. */
export function summaryOf(
  path: string,
  text: string,
): SessionRecord | undefined {
  const lines = text.split('\n');
  const [header] = parseRecord(lines[0] ?? '');
  // Written by `JSON.stringify` with `type` first, so a prompt's line is
  // known without parsing every update.
  const prompts = parseRecord(
    lines.filter((line) => line.startsWith('{"type":"prompt"')).join('\n'),
  ).filter((entry) => entry.type === 'prompt');
  const first = prompts.at(0);
  const last = prompts.at(-1);

  if (header?.type !== 'session' || !first || !last) {
    return undefined;
  }

  return {
    path,
    sessionId: header.sessionId,
    agent: header.agent,
    cwd: header.cwd,
    lastUsedAt: last.at,
    prompt: promptLine(first.prompt),
    ...(header.parent === undefined ? {} : { parent: header.parent }),
    ...(header.name === undefined ? {} : { name: header.name }),
  };
}

function latest(records: readonly SessionRecord[]) {
  return records.toSorted((a, b) => b.lastUsedAt - a.lastUsedAt).at(0);
}

export interface FindOptions {
  readonly agent: string;
  readonly cwd: string;
}

/**
 * The session `--continue` reopens: the one used last for this agent in this
 * directory, of those the person opened; a task agent's is its parent's
 * work, not the person's last session.
 */
export function latestSession(
  records: readonly SessionRecord[],
  { agent, cwd }: FindOptions,
): Resume {
  const found = latest(
    records.filter(
      (record) =>
        record.cwd === cwd &&
        record.agent === agent &&
        record.parent === undefined,
    ),
  );

  if (!found) {
    throw new ResumeError(`No earlier ${agent} session in ${cwd} to continue.`);
  }

  return resumeOf(found);
}

/** An earlier session `/resume` offers, and what its row says of it. */
export interface EarlierSession {
  readonly resume: Resume;
  /** When it was last used: an ISO timestamp. */
  readonly lastUsedAt: string;
  /**
   * The first prompt sent in it, on one line, after the name of an agent
   * another started, as what it was asked says little of which one it is.
   */
  readonly prompt: string;
}

/**
 * Which directories a session list is drawn from: `/resume`'s scope without
 * a working directory is every one.
 */
export type ListOptions = Omit<FindOptions, 'cwd'> & {
  readonly cwd?: string | undefined;
};

/**
 * The sessions `/resume` offers: those `--continue` chooses among, newest
 * first, but `except`, the one on screen, which is already open. Without a
 * `cwd` they come from every directory chord's records name, as the records
 * are one store for all of them. A session with more than one record, as two
 * windows may leave, is offered once, by its latest.
 */
export function earlierSessions(
  records: readonly SessionRecord[],
  { agent, cwd }: ListOptions,
  except?: string,
): EarlierSession[] {
  const newest = records
    .filter(
      (record) =>
        (cwd === undefined || record.cwd === cwd) &&
        record.agent === agent &&
        record.sessionId !== except,
    )
    .toSorted((a, b) => b.lastUsedAt - a.lastUsedAt);
  const seen = new Set<string>();

  return newest
    .filter((record) => {
      const fresh = !seen.has(record.sessionId);

      seen.add(record.sessionId);

      return fresh;
    })
    .map((record) => ({
      resume: resumeOf(record),
      lastUsedAt: new Date(record.lastUsedAt).toISOString(),
      prompt: sessionLabel(record),
    }));
}

/**
 * What a session is called where chord names it: its first prompt, on one
 * line, after the name of an agent another started, as what it was asked
 * says little of which one it is.
 */
export function sessionLabel({
  prompt,
  name,
}: {
  readonly prompt: string;
  readonly name?: string | undefined;
}): string {
  return name === undefined ? prompt : `${name} · ${prompt}`;
}

/**
 * What `/resume` will call an open session whose first prompt, as its record
 * keeps it, is `firstPrompt`; none before one (CHD-491).
 */
export function openSessionLabel(
  firstPrompt: string | undefined,
): string | undefined {
  const prompt = firstPrompt === undefined ? '' : promptLine(firstPrompt);

  return prompt === '' ? undefined : sessionLabel({ prompt });
}

/** Those of `sessions` that work in `cwd`, in the order they came. */
export function sessionsIn(
  sessions: readonly EarlierSession[],
  cwd: string,
): EarlierSession[] {
  return sessions.filter(({ resume }) => resume.cwd === cwd);
}

/**
 * What `/resume` says of a session picked from another directory, which it
 * does not open in this window: the directory it works in, and the command
 * that opens it there, as `--resume` starts in a session's own directory.
 * The command has a line of its own, so that it is selected whole and wraps
 * as itself, not in the middle of a sentence.
 */
export function elsewhereRefusal(
  chosen: Resume,
  {
    agent,
    agentCommand,
    shownCwd,
  }: {
    agent: string;
    agentCommand?: string | undefined;
    /** The session's directory as the screen shows it. */
    shownCwd: string;
  },
): string {
  return `That session is in ${shownCwd}. Quit and open it there with:\n${resumeCommand(
    agent,
    chosen.sessionId,
    agentCommand,
  )}`;
}

/**
 * The session `--resume <id>` opens. chord need not have seen it: an id it has
 * no record of goes to the agent as it is, and the agent says whether it
 * knows it.
 */
export function sessionById(
  records: readonly SessionRecord[],
  id: string,
  { agent, cwd }: FindOptions,
): Resume {
  const named = records.filter((record) => record.sessionId === id);
  const found = latest(named.filter((record) => record.agent === agent));

  if (found) {
    return resumeOf(found);
  }

  const other = latest(named);

  if (other) {
    throw new ResumeError(
      `Session ${id} belongs to another agent (${other.agent}).`,
    );
  }

  return { sessionId: id, cwd };
}

/**
 * The refusal of `-r <id> -r <id> …`: chord opens one session, so each id
 * is said back as a command of its own, in the order given (CHD-493). An id
 * chord has a record of runs on that record's agent in its directory; one
 * it has none of, on this command's, and its line says so. The
 * `--agent-command` the person typed goes only with the agent it starts.
 */
export function severalRefusal(
  records: readonly SessionRecord[],
  ids: readonly string[],
  {
    agent,
    cwd,
    agentCommand,
  }: FindOptions & { readonly agentCommand?: string | undefined },
): ResumeError {
  const lines = ids.map((id) => {
    const found = latest(records.filter((record) => record.sessionId === id));
    const runs = found?.agent ?? agent;
    const command = resumeCommand(
      runs,
      id,
      runs === agent ? agentCommand : undefined,
      found?.cwd ?? cwd,
    );

    return found === undefined
      ? `${command}  # no record; the agent and directory are this command's`
      : command;
  });

  return new ResumeError(
    [
      `--resume opens one session; it was given ${ids.length}. Open each in a chord of its own:`,
      ...lines,
    ].join('\n'),
  );
}

function resumeOf(record: SessionRecord): Resume {
  return {
    sessionId: record.sessionId,
    cwd: record.cwd,
    record: record.path,
    lastUsedAt: record.lastUsedAt,
    prompt: record.prompt,
    ...(record.name === undefined ? {} : { name: record.name }),
  };
}

/**
 * The command that opens this session again, printed on quit as Claude Code
 * prints its own; an `--agent-command` goes with it, or the name would mean
 * nothing.
 */
export function resumeCommand(
  agent: string,
  sessionId: string,
  /**
   * The `--agent-command` the person gave, said again; a command from the
   * settings is not, as the settings give it again (the owner's Q56).
   */
  agentCommand?: string,
  /**
   * The directory it opens in, for a session that chord may have no record
   * of, which would otherwise open wherever the command is typed.
   */
  cwd?: string,
): string {
  const words = ['chord', shellQuote(agent)];

  if (cwd !== undefined) {
    words.push('--cwd', shellQuote(cwd));
  }

  if (agentCommand !== undefined) {
    words.push('--agent-command', shellQuote(agentCommand));
  }

  // An id that starts with a dash would be read as an option on its own;
  // Cliffy takes it as the flag's value when joined with `=`.
  return sessionId.startsWith('-')
    ? [...words, `--resume=${shellQuote(sessionId)}`].join(' ')
    : [...words, '--resume', shellQuote(sessionId)].join(' ');
}

/**
 * An open session quitting leaves to resume: its tab's agent, its id and the
 * directory it works in.
 */
export interface ResumableTab {
  readonly agent: string;
  readonly sessionId: string;
  readonly cwd: string;
}

/**
 * What is printed once the window has gone: a command that resumes each
 * session, in tab order, or nothing when none had a prompt. `agentCommand`
 * goes with the sessions of the agent it overrides.
 */
export function resumeMessage(
  tabs: readonly ResumableTab[],
  override?: {
    readonly agent: string;
    /** The `--agent-command` the person gave, for `agent` alone. */
    readonly agentCommand?: string;
  },
): string | undefined {
  const commands = tabs.map(({ agent, sessionId }) =>
    resumeCommand(
      agent,
      sessionId,
      agent === override?.agent ? override.agentCommand : undefined,
    ),
  );

  if (commands.length === 0) {
    return undefined;
  }

  return `${
    commands.length === 1
      ? 'Resume this session with:'
      : 'Resume these sessions with:'
  }\n${commands.join('\n')}`;
}

function shellQuote(text: string): string {
  return /^[\w@%+=:,./-]+$/.test(text)
    ? text
    : `'${text.replaceAll("'", `'\\''`)}'`;
}
