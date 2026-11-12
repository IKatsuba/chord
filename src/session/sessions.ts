/**
 * Finding an earlier session to resume among chord's own session records:
 * the latest one for an agent and a directory (`--continue`), one by the
 * agent's id for it (`--resume <id>`), or every one there or in any
 * directory (`/resume`).
 */
import pLimit from 'p-limit';
import { createReadStream } from 'node:fs';
import { readdir } from 'node:fs/promises';
import { join } from 'node:path';
import { createInterface } from 'node:readline';
import { notFound } from '../not_found.ts';
import {
  parseRecord,
  promptLine,
  type RecordEntry,
  recordsDir,
} from './record.ts';
import { recordedSelection } from './team_selection.ts';

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
  /** The agent's own title for it, where its record says (CHD-445). */
  readonly title?: string | undefined;
  /**
   * Whether it is a task's, which keeps its spawn_task name and shows its
   * agent's title nowhere, opened again as main too (CHD-445, Q200).
   */
  readonly task?: boolean | undefined;
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
  /** Last recorded prompt, or receipt-only actual opening, epoch milliseconds. */
  readonly lastUsedAt: number;
  /** First prompt, or an explicit receipt-only team-attempt preview. */
  readonly prompt: string;
  /** A task agent's: the session that started it, by the agent's id. */
  readonly parent?: string;
  /** An agent another started's: its name, or its task's description. */
  readonly name?: string;
  /**
   * The agent's own title for it, on one line: the last a
   * `session_info_update` gave it (CHD-445).
   */
  readonly title?: string;
  /** A task agent's, whose agent's title is shown nowhere (Q200). */
  readonly task?: boolean;
}

/**
 * Session records with a prompt or an admitted selected attempt. The list
 * reads their header, prompts, receipt and titles; the past opens on demand.
 * `lines` reads a record's file a line at a time.
 */
export async function readRecords(
  stateDir: string,
  lines: (path: string) => AsyncIterable<string> = recordLines,
): Promise<SessionRecord[]> {
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

  // A person's records run to thousands of files and gigabytes: read whole
  // and all at once, they held the window for half a minute and gigabytes
  // of memory (CHD-615). A few at a time, a line at a time, holds a line.
  const limit = pLimit(RECORDS_READ_AT_ONCE);
  const read = await Promise.all(
    paths.map((path) =>
      limit(async () => {
        try {
          const summary = summarise(path);

          for await (const line of lines(path)) {
            summary.line(line);
          }

          return summary.done();
        } catch {
          // Gone since the directory was read, or unreadable: not offered.
          return undefined;
        }
      }),
    ),
  );

  return read.filter((record) => record !== undefined);
}

/** How many records the list reads at once. */
const RECORDS_READ_AT_ONCE = 8;

/** A record's file, a line at a time. */
function recordLines(path: string): AsyncIterable<string> {
  return createInterface({
    input: createReadStream(path, { encoding: 'utf8' }),
    crlfDelay: Infinity,
  });
}

/**
 * The records a start reads, read once however many of its steps ask: the
 * agent an id names, the picker and the session found each need them, and
 * every read is of the whole directory (CHD-557).
 */
export function recordsOnce(
  read: () => Promise<SessionRecord[]>,
): () => Promise<SessionRecord[]> {
  let records: Promise<SessionRecord[]> | undefined;

  return () => (records ??= read());
}

/** A real recorded session with work; looked-only records stay hidden. */
export function summaryOf(
  path: string,
  text: string,
): SessionRecord | undefined {
  const summary = summarise(path);

  for (const line of text.split('\n')) {
    summary.line(line);
  }

  return summary.done();
}

/**
 * What a record says of its session, gathered as its lines are read: its
 * header, first and last prompt, last receipt, last opening and title.
 * Written by `JSON.stringify` with `type` first, so a line's kind is known
 * without parsing every update.
 */
type PromptEntry = Extract<RecordEntry, { type: 'prompt' }>;
type OpenedEntry = Extract<RecordEntry, { type: 'opened' }>;

function summarise(path: string): {
  line(line: string): void;
  done(): SessionRecord | undefined;
} {
  let header: RecordEntry | undefined;
  let read = false;
  let first: PromptEntry | undefined;
  let last: PromptEntry | undefined;
  let receipt: ReturnType<typeof recordedSelection>;
  let opened: OpenedEntry | undefined;
  const title = recordedTitle();

  return {
    line: (line) => {
      if (!read) {
        read = true;
        [header] = parseRecord(line);
      }

      if (line.startsWith('{"type":"prompt"')) {
        const [entry] = parseRecord(line);

        if (entry?.type === 'prompt') {
          first ??= entry;
          last = entry;
        }
      } else if (
        line.startsWith('{"type":"served"') &&
        line.includes('"run_team"')
      ) {
        const [entry] = parseRecord(line);

        if (entry?.type === 'served' && entry.call.tool === 'run_team') {
          receipt = recordedSelection(entry.call) ?? receipt;
        }
      } else if (line.startsWith('{"type":"opened"')) {
        const [entry] = parseRecord(line);

        if (entry?.type === 'opened') {
          opened = entry;
        }
      } else {
        title.line(line);
      }
    },
    done: () => {
      if (header?.type !== 'session') {
        return undefined;
      }

      if (first === undefined && receipt === undefined) {
        return undefined;
      }

      // A task is known by its spawn_task title alone, as its caller named
      // it, not by its agent's own (the owner, Q200).
      const named = header.task === undefined ? title.done() : undefined;

      return {
        path,
        sessionId: header.sessionId,
        agent: header.agent,
        cwd: header.cwd,
        lastUsedAt: last?.at ?? opened?.at ?? header.at,
        prompt:
          first === undefined
            ? `Team attempt: ${receipt!.saved.name}`
            : promptLine(first.prompt),
        ...(header.parent === undefined ? {} : { parent: header.parent }),
        ...(header.name === undefined ? {} : { name: header.name }),
        ...(named === undefined ? {} : { title: named }),
        ...(header.task === undefined ? {} : { task: true }),
      };
    },
  };
}

/**
 * The agent's title for a session as its record's lines leave it, as the
 * conversation keeps it (CHD-491): the last `session_info_update` that gave
 * one, `null` taking it back and a blank one left out; a subagent's is not
 * the session's. Only the lines that name the update are parsed.
 */
function recordedTitle(): {
  line(line: string): void;
  done(): string | undefined;
} {
  let title: string | undefined;

  return {
    line: (line) => {
      if (
        !line.startsWith('{"type":"update"') ||
        !line.includes('"session_info_update"')
      ) {
        return;
      }

      const [entry] = parseRecord(line);

      if (
        entry?.type !== 'update' ||
        entry.subagentId !== undefined ||
        entry.update.sessionUpdate !== 'session_info_update'
      ) {
        return;
      }

      if (entry.update.title === null) {
        title = undefined;
      } else if (
        typeof entry.update.title === 'string' &&
        entry.update.title.trim() !== ''
      ) {
        title = titleLine(entry.update.title);
      }
    },
    done: () => title,
  };
}

/**
 * A title as chord draws it: on one line, its whitespace folded as a
 * prompt's is, and its control characters left out, so an escape sequence
 * in it is text and not acted on (CHD-445).
 */
export function titleLine(title: string): string {
  return title
    .replaceAll(/\s+/g, ' ')
    .replaceAll(/\p{Cc}/gu, '')
    .trim();
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
 * What a session is called where chord names it: the agent's title for it,
 * or its first prompt, on one line, after the name of an agent another
 * started, as what it was asked says little of which one it is (CHD-445).
 */
export function sessionLabel({
  prompt,
  name,
  title,
}: {
  readonly prompt: string;
  readonly name?: string | undefined;
  readonly title?: string | undefined;
}): string {
  const said = title ?? prompt;

  return name === undefined ? said : `${name} · ${said}`;
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
    noMcpServers,
    shownCwd,
  }: {
    agent: string;
    agentCommand?: string | undefined;
    /** `--no-mcp-servers` was typed for `agent`. */
    noMcpServers?: boolean | undefined;
    /** The session's directory as the screen shows it. */
    shownCwd: string;
  },
): string {
  return `That session is in ${shownCwd}. Quit and open it there with:\n${resumeCommand(
    agent,
    chosen.sessionId,
    agentCommand,
    noMcpServers,
  )}`;
}

/**
 * The agent chord's latest record of session `id` ran on; none for an id
 * chord has no record of. `chord -r <id>` with no agent on the command line
 * opens on it (Q180).
 */
export function recordedAgent(
  records: readonly SessionRecord[],
  id: string,
): string | undefined {
  return latest(records.filter((record) => record.sessionId === id))?.agent;
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

function resumeOf(record: SessionRecord): Resume {
  return {
    sessionId: record.sessionId,
    cwd: record.cwd,
    record: record.path,
    lastUsedAt: record.lastUsedAt,
    prompt: record.prompt,
    ...(record.name === undefined ? {} : { name: record.name }),
    ...(record.title === undefined ? {} : { title: record.title }),
    ...(record.task === true ? { task: true } : {}),
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
  /** `--no-mcp-servers` was typed, and is said again as the command is. */
  noMcpServers = false,
): string {
  const words = ['chord', shellQuote(agent)];

  if (agentCommand !== undefined) {
    words.push('--agent-command', shellQuote(agentCommand));
  }

  if (noMcpServers) {
    words.push('--no-mcp-servers');
  }

  // An id that starts with a dash would be read as an option on its own;
  // Cliffy takes it as the flag's value when joined with `=`.
  return sessionId.startsWith('-')
    ? [...words, `--resume=${shellQuote(sessionId)}`].join(' ')
    : [...words, '--resume', shellQuote(sessionId)].join(' ');
}

/**
 * The session quitting leaves to resume: its agent and its id.
 */
export interface Resumable {
  readonly agent: string;
  readonly sessionId: string;
}

/**
 * What is printed once the window has gone: the command that resumes its
 * session, or nothing when no prompt went to it. A typed `agentCommand` and
 * `--no-mcp-servers` go with it when it is of the agent they were given for.
 */
export function resumeMessage(
  session: Resumable | undefined,
  override?: {
    readonly agent: string;
    /** The `--agent-command` the person gave, for `agent` alone. */
    readonly agentCommand?: string;
    /** `--no-mcp-servers` was typed, for `agent` alone. */
    readonly noMcpServers?: boolean;
  },
): string | undefined {
  return session === undefined
    ? undefined
    : `Resume this session with:\n${resumeCommand(
        session.agent,
        session.sessionId,
        session.agent === override?.agent ? override.agentCommand : undefined,
        session.agent === override?.agent && override.noMcpServers === true,
      )}`;
}

function shellQuote(text: string): string {
  return /^[\w@%+=:,./-]+$/.test(text)
    ? text
    : `'${text.replaceAll("'", `'\\''`)}'`;
}
