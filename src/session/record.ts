/**
 * chord's record of a session: what the transcript reducer was handed, kept so
 * the session can be drawn again once it is resumed. One JSON Lines file per
 * session under `records/` in chord's state directory, appended to as the
 * session goes, so a long session costs one line per update, not a rewrite.
 */
import type { SessionUpdate } from '@agentclientprotocol/sdk';
import { join } from 'node:path';
import { appendFile, mkdir, readdir, readFile } from 'node:fs/promises';
import { notFound } from '../not_found.ts';
import type { ResourceLink } from '../files.ts';
import { shellContext, splitContext, withContext } from './context.ts';
import type { ConversationEvent, Recording } from './conversation.ts';
import type { PastAction, Session } from './session.ts';
import { monitorsPast } from './monitors.ts';
import { withoutSecrets } from './questions.ts';
import { unwrapMessage } from './tasks.ts';
import { TASK_META } from './transcript/subagents.ts';
import type {
  ChordCall,
  ElicitationAnswer,
  ElicitationWait,
  PlanAnswer,
  PlanWait,
  LeftOpen,
  MessageFrom,
  ShellRun,
  TranscriptAction,
  TurnResult,
} from './transcript/types.ts';
import { lastReading, type TurnFigures } from './turn_costs.ts';
import type { TokenUsage } from './usage.ts';

/** One line of a record. */
export type RecordEntry =
  /** The first line: whose session this is, and where it works. */
  | {
      readonly type: 'session';
      readonly version: 1;
      /** The agent's own id for the session, which it is reopened by. */
      readonly sessionId: string;
      readonly agent: string;
      readonly cwd: string;
      /** When the record was started, epoch milliseconds. */
      readonly at: number;
      /**
       * An agent another started's: the session that started it, by the
       * agent's id; a team member's is its lead's.
       */
      readonly parent?: string;
      /**
       * An agent another started's: its name, as a long-lived one is called
       * by, or a task's description, which `/resume` says the session by.
       */
      readonly name?: string;
      /**
       * A task agent's: chord's id for it, which its parent's record keeps its
       * block under, so the parent resumed draws the task's work from here.
       */
      readonly task?: string;
      /**
       * A long-lived agent's: chord's id for it, as `open_agent` or
       * `run_team` answered it, which its parent's record names it by.
       */
      readonly id?: string;
      /**
       * A team's lead's: the team it runs, by its file's name, so its parent
       * resumed counts its members from here.
       */
      readonly team?: string;
    }
  /**
   * A prompt as the agent got it: the shell output held for it ahead of the
   * typed text, how many images went after it, and the `resource_link` for
   * each file its `@` mentions named, which draw nothing as the text names
   * them already; a message's sender, which the wrapper the agent read
   * says less of than its row draws; and, for a message put into a running
   * turn, that turn, as it started none.
   */
  | {
      readonly type: 'prompt';
      readonly turnId: string;
      readonly at: number;
      readonly prompt: string;
      readonly images: number;
      readonly links?: readonly ResourceLink[];
      readonly from?: MessageFrom;
      readonly into?: string;
    }
  /**
   * One of the agent's updates, whole, under the turn it was folded into, with
   * the subagent it was for and when it came, where the reducer keeps those.
   */
  | {
      readonly type: 'update';
      readonly turnId: string;
      readonly update: SessionUpdate;
      readonly subagentId?: string;
      readonly at?: number;
    }
  /** A request chord's MCP server served, as the reducer was handed it. */
  | {
      readonly type: 'served';
      readonly turnId: string;
      readonly call: ChordCall;
      readonly subagentId?: string;
    }
  /**
   * A team run the person's `/team run` started, as the `run_team` call it
   * was. Its own line, not a `served` one: no call of the agent's asked for
   * it, so a resume must not hand its answer to a `run_team` call that does.
   */
  | { readonly type: 'ran'; readonly turnId: string; readonly call: ChordCall }
  /**
   * A long-lived agent `open_agent` opened, by chord's id for it, closed
   * while the session went on: by `close_agent` or the person's `x`. One
   * that closed with its parent, as the tab, `/clear` or `/resume` let the
   * parent go, was open when the session was left, and has no such line.
   */
  | { readonly type: 'closed'; readonly agent: string }
  /** A form or link the agent asked the person, with the questions chord read in it. */
  | {
      readonly type: 'asked';
      readonly turnId: string;
      readonly wait: ElicitationWait;
    }
  /**
   * How a form or link was answered, by its id, where it was: what was given
   * for a secret question left out.
   */
  | {
      readonly type: 'answered';
      readonly turnId: string;
      readonly id: string;
      readonly answer: ElicitationAnswer;
    }
  /** A plan cursor or grok put to the person (CHD-437, CHD-457). */
  | {
      readonly type: 'plan_asked';
      readonly turnId: string;
      readonly wait: PlanWait;
    }
  /** How a plan was answered, by its id; a record before these has none. */
  | {
      readonly type: 'plan_answered';
      readonly turnId: string;
      readonly id: string;
      readonly answer: PlanAnswer;
    }
  /** The person interrupted a turn, which ends its subagents then. */
  | { readonly type: 'cancel'; readonly turnId: string; readonly at: number }
  /**
   * The person stopped subagent `subagentId` alone with `x`, or, `stopping`
   * false, that stop could not be sent, so a resumed transcript says who
   * ended it as the live one did (CHD-479, the owner's Q118). A record
   * written before these has none, and says only how it ended.
   */
  | {
      readonly type: 'stopping';
      readonly subagentId: string;
      readonly stopping: boolean;
    }
  /**
   * chord cancelled a turn the agent started on its own with a message
   * steered after chord's turn had ended; the message went as the next turn.
   */
  | {
      readonly type: 'self_started';
      readonly turnId: string;
      readonly from: MessageFrom;
    }
  /** The agent's process went, and the subagents still running with it. */
  | { readonly type: 'disconnected'; readonly at: number }
  | {
      readonly type: 'result';
      readonly turnId: string;
      readonly result: TurnResult;
    }
  /**
   * A turn's tokens as its answer gave them, empty for an agent's own cycle,
   * and what the turn cost on its own, with the model it ended on
   * (CHD-373). Written again, whole, when its cost comes after its end; the
   * last line for a turn is its.
   */
  | ({ readonly type: 'usage' } & TurnFigures)
  /**
   * The session was opened, first or again: a turn's cost is found within
   * one opening. A record written before these has none.
   */
  | { readonly type: 'opened'; readonly at: number }
  /** The model, mode and other config values in use from here on. */
  | {
      readonly type: 'state';
      readonly model?: string;
      readonly mode?: string;
      readonly options: Readonly<Record<string, string>>;
    };

type StateEntry = Extract<RecordEntry, { type: 'state' }>;

/** A state line's values, any of them unknown. */
interface StateValues {
  readonly model?: string | undefined;
  readonly mode?: string | undefined;
  readonly options?: Readonly<Record<string, string>> | undefined;
}

/** The directory records are kept in, under chord's state directory. */
export function recordsDir(stateDir: string): string {
  return join(stateDir, 'records');
}

/** The lines of a record file; a line cut short by a crash is passed over. */
export function parseRecord(text: string): RecordEntry[] {
  return text.split('\n').flatMap((line) => {
    if (line === '') {
      return [];
    }

    try {
      return [JSON.parse(line) as RecordEntry];
    } catch {
      return [];
    }
  });
}

/** A record's past as written, or none when the file has gone. */
export async function readPast(path: string): Promise<RecordEntry[]> {
  try {
    return parseRecord(await readFile(path, 'utf8'));
  } catch (error) {
    if (notFound(error)) {
      return [];
    }

    throw error;
  }
}

/**
 * The pasts of the task agents session `parentId` started, from their own
 * records in `dir`, by chord's id for each task. A record that has gone is
 * not among them.
 */
export async function taskPasts(
  dir: string,
  parentId: string,
): Promise<Map<string, RecordEntry[]>> {
  const pasts = new Map<string, RecordEntry[]>();

  for (const entries of await childPasts(dir, parentId)) {
    const [header] = entries;

    if (header?.type === 'session' && header.task !== undefined) {
      pasts.set(header.task, entries);
    }
  }

  return pasts;
}

/**
 * The pasts of the team runs session `parentId` started, from their leads'
 * own records in `dir`, by chord's id for each lead. A record that has gone
 * is not among them.
 */
export async function runPasts(
  dir: string,
  parentId: string,
): Promise<Map<string, RecordEntry[]>> {
  const pasts = new Map<string, RecordEntry[]>();

  for (const entries of await childPasts(dir, parentId)) {
    const [header] = entries;

    if (
      header?.type === 'session' &&
      header.team !== undefined &&
      header.id !== undefined
    ) {
      pasts.set(header.id, entries);
    }
  }

  return pasts;
}

/** The records in `dir` of the agents session `parentId` started. */
async function childPasts(
  dir: string,
  parentId: string,
): Promise<RecordEntry[][]> {
  const pasts: RecordEntry[][] = [];

  try {
    for (const file of await readdir(dir, { withFileTypes: true })) {
      if (!file.isFile() || !file.name.endsWith('.jsonl')) {
        continue;
      }

      const entries = await readPast(join(dir, file.name));
      const [header] = entries;

      if (header?.type === 'session' && header.parent === parentId) {
        pasts.push(entries);
      }
    }
  } catch (error) {
    if (!notFound(error)) {
      throw error;
    }
  }

  return pasts;
}

/**
 * A parent's record with each task's work put back from the task's own,
 * after the line that started its block, as the parent's record keeps only
 * the block's start and end: the task's updates and the calls chord served
 * it go under the task's id, its own subagents' under theirs, as they were
 * relayed live. A task whose record has gone keeps the bare block, marked
 * so its ending does not count work it no longer has.
 */
export function withTaskWork(
  entries: readonly RecordEntry[],
  tasks: ReadonlyMap<string, readonly RecordEntry[]>,
): RecordEntry[] {
  const placed = new Set<string>();

  return entries.flatMap((entry) => {
    if (
      entry.type !== 'update' ||
      entry.subagentId !== undefined ||
      entry.update.sessionUpdate !== 'subagent_update' ||
      entry.update._meta?.[TASK_META] === undefined
    ) {
      return [entry];
    }

    const id = entry.update.sessionId;
    const own = tasks.get(id);

    if (placed.has(id)) {
      return [entry];
    }

    placed.add(id);

    if (own === undefined) {
      return [
        {
          ...entry,
          update: {
            ...entry.update,
            _meta: {
              ...entry.update._meta,
              [TASK_META]: {
                ...(entry.update._meta?.[TASK_META] as object),
                workLost: true,
              },
            },
          },
        },
      ];
    }

    return [
      entry,
      ...own.flatMap((each): RecordEntry[] =>
        each.type === 'update' || each.type === 'served'
          ? [
              {
                ...each,
                turnId: entry.turnId,
                subagentId: each.subagentId ?? id,
              },
            ]
          : [],
      ),
    ];
  });
}

/**
 * The updates a record kept, by the session that sent each: `rootId` for the
 * session's own, a subagent's ID for its. The enrichers keep each session
 * apart live, and so must hear a resumed past apart.
 */
/** The tokens of the last turn `entries` kept that had any. */
export function lastTotal(
  entries: readonly RecordEntry[],
): TokenUsage | undefined {
  return entries.findLast(
    (entry): entry is Extract<RecordEntry, { type: 'usage' }> =>
      entry.type === 'usage' && Object.keys(entry.usage).length > 0,
  )?.usage;
}

export function pastBySession(
  rootId: string,
  entries: readonly RecordEntry[],
): Map<string, SessionUpdate[]> {
  const bySession = new Map<string, SessionUpdate[]>();

  for (const entry of entries) {
    if (entry.type !== 'update') {
      continue;
    }

    const id = entry.subagentId ?? rootId;

    bySession.set(id, [...(bySession.get(id) ?? []), entry.update]);
  }

  return bySession;
}

/**
 * The names `send_message` reaches by, as the record's own answers tell it:
 * `main`, which no other agent may take, and each child `open_agent` opened,
 * but none a `spawn_task` in it named, as a message from that name could be
 * the task's.
 */
function answeredReachable(entries: readonly RecordEntry[]): Set<string> {
  const opened = new Set(['main']);
  const tasks = new Set<string>();

  for (const entry of entries) {
    if (entry.type !== 'served') {
      continue;
    }

    const name = (entry.call.answer as { name?: unknown } | undefined)?.name;

    if (typeof name !== 'string') {
      continue;
    }

    if (entry.call.tool === 'open_agent') {
      opened.add(name);
    } else if (entry.call.tool === 'spawn_task') {
      tasks.add(name);
    }
  }

  return new Set([...opened].filter((name) => !tasks.has(name)));
}

/**
 * The sender of a message whose prompt line has no `from`, as a record
 * written before it was kept has it: the wrapper does not say whether
 * `send_message` reaches it, so the record's answers do. A report or a
 * failure is always a task's.
 */
function legacyFrom(
  from: MessageFrom,
  reachable: ReadonlySet<string>,
): MessageFrom {
  return from.note === undefined && reachable.has(from.name)
    ? { ...from, reachable: true }
    : from;
}

/**
 * The long-lived agents the record's session had open when it was left: each
 * `open_agent` answered, and each team run `run_team` or the person's
 * `/team run` started, but not one closed while it went on. A run counts its lead and the members its lead's
 * record in `runs` had open, or its lead alone once that record has gone.
 */
function leftOpen(
  entries: readonly RecordEntry[],
  runs: ReadonlyMap<string, readonly RecordEntry[]> = new Map(),
): LeftOpen[] {
  const open = new Map<string, LeftOpen>();

  for (const entry of entries) {
    if (entry.type === 'closed') {
      open.delete(entry.agent);
    }

    if (
      (entry.type !== 'served' && entry.type !== 'ran') ||
      (entry.call.tool !== 'open_agent' && entry.call.tool !== 'run_team')
    ) {
      continue;
    }

    const answer = entry.call.answer as
      | { id?: unknown; name?: unknown; agent?: unknown; team?: unknown }
      | undefined;

    if (
      typeof answer?.id !== 'string' ||
      typeof answer.name !== 'string' ||
      typeof answer.agent !== 'string'
    ) {
      continue;
    }

    open.set(
      answer.id,
      entry.call.tool === 'run_team' && typeof answer.team === 'string'
        ? {
            name: answer.name,
            runtime: answer.agent,
            team: answer.team,
            agents: 1 + leftOpen(runs.get(answer.id) ?? []).length,
          }
        : { name: answer.name, runtime: answer.agent },
    );
  }

  return [...open.values()];
}

/**
 * A record's past as the reducers' actions, so it draws as its turns did
 * live: each prompt with the shell runs whose output went ahead of it, the
 * agent's updates whole (an edit with its diff), its subagents' among them,
 * each interrupt and turn's end, and its tokens, so what the session spent
 * counts them.
 * A turn the record has no end for, as when chord was stopped mid-turn, is
 * ended with nothing drawn for its end, as how it ended is not known; it is
 * only not left working. A subagent the record never saw end is
 * disconnected, with no time, as the agent that ran it is gone: where that
 * agent's part of the record ends, at the session's next opening, else at
 * the record's end, so a session resumed and worked on again reads in order
 * (the owner's Q144). A record written before openings were has its ends
 * at its end. The
 * long-lived agents open when the session was left are named last, as they
 * are not reopened with it, a team's runs counted from their leads' records
 * in `runs`, by chord's id for each lead.
 */
export function recordActions(
  entries: readonly RecordEntry[],
  runs: ReadonlyMap<string, readonly RecordEntry[]> = new Map(),
): PastAction[] {
  const actions: PastAction[] = [];
  /** The turn whose prompt came last, until its result does. */
  let open: string | undefined;
  const id = (turnId: string) => `history-${turnId}`;
  const reachable = answeredReachable(entries);
  const answered = new Set(
    entries.flatMap((entry) =>
      entry.type === 'answered' || entry.type === 'plan_answered'
        ? [entry.id]
        : [],
    ),
  );

  const end = () => {
    if (open !== undefined) {
      actions.push({
        type: 'result',
        turnId: open,
        result: { status: 'completed', stopReason: 'end_turn' },
      });
    }

    open = undefined;
  };

  for (const entry of entries) {
    switch (entry.type) {
      case 'prompt': {
        const turnId = id(entry.turnId);
        const message = unwrapMessage(entry.prompt);

        // It went into the turn running then, which goes on past it.
        if (entry.into !== undefined && message !== undefined) {
          actions.push({
            type: 'prompt',
            turnId,
            text: message.text,
            at: entry.at,
            from: entry.from ?? legacyFrom(message.from, reachable),
            into: id(entry.into),
          });

          break;
        }

        end();

        if (message !== undefined) {
          actions.push({
            type: 'prompt',
            turnId,
            text: message.text,
            at: entry.at,
            from: entry.from ?? legacyFrom(message.from, reachable),
            ...(message.team === undefined ? {} : { team: message.team }),
          });

          open = turnId;

          break;
        }

        const { runs, text } = splitContext(entry.prompt);

        actions.push(
          ...runs.map((run, index): TranscriptAction => ({
            type: 'shell_replayed',
            turnId: `${turnId}-shell-${index + 1}`,
            run,
          })),
          {
            type: 'prompt',
            turnId,
            text: withImages(text, entry.images),
            at: entry.at,
          },
        );

        open = turnId;

        break;
      }
      case 'update':
        actions.push({
          type: 'update',
          turnId: id(entry.turnId),
          update: entry.update,
          ...(entry.subagentId === undefined
            ? {}
            : { subagentId: entry.subagentId }),
          ...(entry.at === undefined ? {} : { at: entry.at }),
        });

        break;
      case 'asked':
        actions.push({
          type: 'elicitation_requested',
          turnId: id(entry.turnId),
          elicitation: entry.wait,
        });

        // One the record never saw answered, as chord was stopped while it
        // waited, is not drawn again as waiting.
        if (!answered.has(entry.wait.id)) {
          actions.push({
            type: 'elicitation_settled',
            turnId: id(entry.turnId),
            id: entry.wait.id,
            answer: { type: 'withdrawn' },
          });
        }

        break;
      case 'answered':
        actions.push({
          type: 'elicitation_settled',
          turnId: id(entry.turnId),
          id: entry.id,
          answer: entry.answer,
        });

        break;
      case 'plan_asked':
        actions.push({
          type: 'plan_requested',
          turnId: id(entry.turnId),
          plan: entry.wait,
        });

        // One the record never saw answered, as chord was stopped while it
        // waited, comes back withdrawn: never waiting, never taken.
        if (!answered.has(entry.wait.id)) {
          actions.push({
            type: 'plan_settled',
            turnId: id(entry.turnId),
            id: entry.wait.id,
            answer: { type: 'withdrawn' },
          });
        }

        break;
      case 'plan_answered':
        actions.push({
          type: 'plan_settled',
          turnId: id(entry.turnId),
          id: entry.id,
          answer: entry.answer,
        });

        break;
      case 'cancel':
        actions.push({
          type: 'cancel',
          turnId: id(entry.turnId),
          at: entry.at,
        });

        break;
      case 'stopping':
        actions.push({
          type: 'subagent_stopping',
          turnId: 'stop',
          subagentId: entry.subagentId,
          stopping: entry.stopping,
        });

        break;
      case 'self_started':
        actions.push({
          type: 'self_started',
          turnId: id(entry.turnId),
          from: entry.from,
        });

        break;
      case 'served':
        actions.push({
          type: 'served',
          turnId: id(entry.turnId),
          call: entry.call,
          ...(entry.subagentId === undefined
            ? {}
            : { subagentId: entry.subagentId }),
        });

        break;
      case 'disconnected':
        actions.push({
          type: 'disconnected',
          turnId: open ?? 'history',
          at: entry.at,
        });

        break;
      // Another agent opened the session: the one before it, and the
      // subagents still running with it, are gone.
      case 'opened':
        actions.push({ type: 'disconnected', turnId: open ?? 'history' });

        break;
      case 'result':
        actions.push({
          type: 'result',
          turnId: id(entry.turnId),
          result: entry.result,
        });

        if (open === id(entry.turnId)) {
          open = undefined;
        }

        break;
      case 'usage':
        actions.push({ ...entry, turnId: id(entry.turnId) });

        break;
    }
  }

  end();

  const before = spentBefore(entries);

  if (before !== undefined) {
    actions.push(before);
  }

  if (
    entries.some(
      (entry) =>
        entry.type === 'update' &&
        entry.update.sessionUpdate === 'subagent_update',
    )
  ) {
    actions.push({ type: 'disconnected', turnId: 'history' });
  }

  const left = leftOpen(entries, runs);

  if (left.length > 0) {
    actions.push({ type: 'left_open', turnId: 'history-left', agents: left });
  }

  const running = monitorsPast(actions).left;

  if (running.length > 0) {
    actions.push({
      type: 'monitors_left',
      turnId: 'history-monitors',
      monitors: running,
    });
  }

  return actions;
}

/**
 * What a record spent before it kept each turn's cost, as one figure: the
 * last cost its session's own updates gave before its first `opened` line,
 * or in all of one written before those lines were (the owner's Q62).
 */
function spentBefore(
  entries: readonly RecordEntry[],
): Extract<PastAction, { type: 'usage' }> | undefined {
  const opened = entries.findIndex((entry) => entry.type === 'opened');
  const first = entries[opened];
  const last = lastReading(
    (opened < 0 ? entries : entries.slice(0, opened)).flatMap((entry) =>
      entry.type === 'update' && entry.subagentId === undefined
        ? [entry.update]
        : [],
    ),
  );

  if (last === undefined) {
    return undefined;
  }

  return {
    type: 'usage',
    turnId: 'history-before',
    usage: {},
    cost: { amount: last.amount, currency: last.currency },
    ...(last.estimated ? { estimated: true as const } : {}),
    before: first?.type === 'opened' ? { until: first.at } : {},
  };
}

/**
 * The past an agent replayed as it loaded a session chord had no record of,
 * as a record's lines, so the record that starts then holds it too: an agent
 * that later reopens the session by `session/resume` replays nothing, and the
 * record is all there is to draw.
 */
export function historyEntries(actions: readonly PastAction[]): RecordEntry[] {
  const entries: RecordEntry[] = [];
  let runs: ShellRun[] = [];

  for (const action of actions) {
    switch (action.type) {
      case 'shell_replayed':
        runs.push(action.run);

        break;
      case 'prompt':
        entries.push({
          type: 'prompt',
          turnId: action.turnId,
          at: action.at,
          prompt:
            runs.length === 0
              ? action.text
              : withContext(shellContext(runs), action.text),
          // Already in the text as placeholders.
          images: 0,
        });

        runs = [];

        break;
      case 'update':
        entries.push(updateEntry(action));

        break;
      case 'result':
        entries.push({
          type: 'result',
          turnId: action.turnId,
          result: action.result,
        });

        break;
      case 'usage':
        entries.push(action);

        break;
    }
  }

  return entries;
}

/**
 * A prompt's text as it was typed, on one line: the shell output sent ahead of
 * it left out, a message's wrapper too, every run of whitespace one space. A prompt that was only shell
 * output reads as its first command, as bash mode shows it.
 */
export function promptLine(prompt: string): string {
  const message = unwrapMessage(prompt);

  if (message !== undefined) {
    return message.text.replaceAll(/\s+/g, ' ').trim();
  }

  const { runs, text } = splitContext(prompt);
  const typed = text.trim() === '' && runs[0] ? `!${runs[0].command}` : text;

  return typed.replaceAll(/\s+/g, ' ').trim();
}

/**
 * `text` with an `[Image #N]` at the end for each image it does not name:
 * chord's own prompts name theirs, another client's may not.
 */
export function withImages(text: string, images: number): string {
  const shown = [...text.matchAll(/\[Image #\d+\]/g)].length;
  const missing = Array.from(
    { length: Math.max(0, images - shown) },
    (_, index) => `[Image #${shown + index + 1}]`,
  );

  return [text, ...missing].filter((part) => part !== '').join(' ');
}

/** An update's line, with its subagent and its time where it has them. */
function updateEntry(
  action: Extract<TranscriptAction, { type: 'update' }>,
): RecordEntry {
  return {
    type: 'update',
    turnId: action.turnId,
    update: action.update,
    ...(action.subagentId === undefined
      ? {}
      : { subagentId: action.subagentId }),
    ...(action.at === undefined ? {} : { at: action.at }),
  };
}

/**
 * The record's line for an event the conversation reported, if it keeps one:
 * updates, interrupts, the person's stop of a subagent, a turn the agent
 * started on its own and chord cancelled, the agent's going, results and
 * usage as they came, and the model, mode and config values once they move.
 * `state` is the line last written of those.
 */
export function entryOf(
  event: ConversationEvent,
  state: StateEntry,
): RecordEntry | undefined {
  switch (event.type) {
    case 'update':
      return updateEntry(event);
    case 'elicitation_requested': {
      // When it came counts down a live box's wait, which a reopened
      // session never shows: the agent's request is gone by then.
      const { at: _, ...wait } = event.elicitation;

      return { type: 'asked', turnId: event.turnId, wait };
    }
    case 'plan_requested':
      return { type: 'plan_asked', turnId: event.turnId, wait: event.plan };
    case 'plan_settled':
      return {
        type: 'plan_answered',
        turnId: event.turnId,
        id: event.id,
        answer: event.answer,
      };
    case 'cancel':
      return { type: 'cancel', turnId: event.turnId, at: event.at };
    case 'subagent_stopping':
      return {
        type: 'stopping',
        subagentId: event.subagentId,
        stopping: event.stopping,
      };
    case 'self_started':
      return { type: 'self_started', turnId: event.turnId, from: event.from };
    case 'served':
      return {
        type: 'served',
        turnId: event.turnId,
        call: event.call,
        ...(event.subagentId === undefined
          ? {}
          : { subagentId: event.subagentId }),
      };
    case 'run_typed':
      return { type: 'ran', turnId: event.turnId, call: event.call };
    case 'agent_closed':
      return { type: 'closed', agent: event.id };
    case 'disconnected':
      return event.at === undefined
        ? undefined
        : { type: 'disconnected', at: event.at };
    case 'result':
      return { type: 'result', turnId: event.turnId, result: event.result };
    case 'usage':
      return event;
    case 'model':
      return stateWith(state, { model: event.models?.current });
    case 'modes':
      return stateWith(state, { mode: event.modes?.current });
    case 'options':
      return stateWith(state, {
        options: Object.fromEntries(
          event.options.map((option) => [option.id, option.current]),
        ),
      });
    default:
      return undefined;
  }
}

/** The state line with `moved` over it; none when nothing moved. */
function stateWith(
  state: StateEntry,
  moved: StateValues,
): StateEntry | undefined {
  const next = stateEntry({ ...state, ...moved });

  return JSON.stringify(next) === JSON.stringify(state) ? undefined : next;
}

function stateEntry({ model, mode, options }: StateValues): StateEntry {
  return {
    type: 'state',
    ...(model === undefined ? {} : { model }),
    ...(mode === undefined ? {} : { mode }),
    options: options ?? {},
  };
}

/** What a session is on as it opens, read from the session itself. */
function stateOfSession(session: Session): StateEntry {
  return stateEntry({
    model: session.models()?.current,
    mode: session.modes()?.current,
    options: Object.fromEntries(
      session.options().map((option) => [option.id, option.current]),
    ),
  });
}

/** An agent another started, as its record names it. */
interface Child {
  /** The agent's id for the session that started it, once it is open. */
  readonly parent: () => string | undefined;
  readonly name: string;
  /** A task agent's: chord's id for it. */
  readonly task?: string;
  /** A long-lived agent's: chord's id for it. */
  readonly id?: string;
  /** A team's lead's: its team's name. */
  readonly team?: string;
}

/**
 * Writes a conversation's sessions into their records as they go. A session
 * opened from a record goes on in that file; any other starts one of its own.
 * Nothing is written until a prompt is, or the agent works on its own, so a
 * session only looked at leaves no record, or no trace in the one it was
 * opened from.
 */
export class FileRecording implements Recording {
  readonly #dir: string;
  readonly #failed: (message: string) => void;
  readonly #now: () => number;
  /** The file the session on screen is written to; none before it opens. */
  #path: string | undefined;
  /** The session on screen's lines, held until a prompt is sent in it. */
  #held: RecordEntry[] = [];
  /** Lines to write, each with its file, oldest first. */
  #queue: { path: string; line: string }[] = [];
  /** Whether a prompt was sent in the session on screen. */
  #prompted = false;
  #state: StateEntry = stateEntry({});
  /** The forms and links waiting on the person, kept for their answer's line. */
  readonly #asking = new Map<string, ElicitationWait>();
  #writing: Promise<void> = Promise.resolve();
  #flushing = false;
  #reported = false;
  readonly #child: Child | undefined;
  /** The turn or cycle the session on screen began last. */
  #lastTurn: string | undefined;
  /**
   * The records of sessions `/clear` let go, by the turn each was in, which
   * may still say what it cost (CHD-373 S3c).
   */
  readonly #retired = new Map<string, string>();

  /**
   * `failed` hears, once, why a record could not be written; the session goes
   * on without it. An agent another started's record names it, and its
   * parent, the session `child.parent` gives the id of.
   */
  constructor(
    stateDir: string,
    failed: (message: string) => void,
    now: () => number = Date.now,
    child?: Child,
  ) {
    this.#dir = recordsDir(stateDir);
    this.#failed = failed;
    this.#now = now;
    this.#child = child;
  }

  /** The file the session is written to, once it is open. */
  get path(): string | undefined {
    return this.#path;
  }

  opened(session: Session): void {
    const path =
      session.record ?? join(this.#dir, `${crypto.randomUUID()}.jsonl`);

    this.#path = path;
    this.#held = [];
    this.#prompted = false;
    this.#state = stateOfSession(session);

    const opened: RecordEntry = { type: 'opened', at: this.#now() };
    const parent = this.#child?.parent();
    const lines: RecordEntry[] =
      session.record === undefined
        ? [
            {
              type: 'session',
              version: 1,
              sessionId: session.id,
              agent: session.agent,
              cwd: session.cwd,
              at: this.#now(),
              ...(parent === undefined ? {} : { parent }),
              ...(this.#child === undefined ? {} : { name: this.#child.name }),
              ...(this.#child?.task === undefined
                ? {}
                : { task: this.#child.task }),
              ...(this.#child?.id === undefined ? {} : { id: this.#child.id }),
              ...(this.#child?.team === undefined
                ? {}
                : { team: this.#child.team }),
            },
            // A past the agent replayed is in no record yet.
            ...historyEntries(session.history()),
            opened,
            this.#state,
          ]
        : [opened, this.#state];

    for (const line of lines) {
      this.#add(line);
    }
  }

  sent(
    turnId: string,
    prompt: string,
    images: number,
    links: readonly ResourceLink[],
    at: number,
    from?: MessageFrom,
    into?: string,
  ): void {
    if (this.#path === undefined) {
      return;
    }

    this.#begun();

    if (into === undefined) {
      this.#lastTurn = turnId;
    }

    this.#add({
      type: 'prompt',
      turnId,
      at,
      prompt,
      images,
      ...(links.length === 0 ? {} : { links }),
      ...(from === undefined ? {} : { from }),
      ...(into === undefined ? {} : { into }),
    });
    this.#flush();
  }

  heard(event: ConversationEvent): void {
    if (event.type === 'retired_usage' || event.type === 'retired_update') {
      this.#retiredLine(event);

      return;
    }

    if (event.type === 'cleared') {
      // Its last turn may still say what it cost, into this record.
      if (this.#path !== undefined && this.#lastTurn !== undefined) {
        this.#retired.set(this.#lastTurn, this.#path);
      }

      // The session it was let go for is opened next, and says so.
      this.#path = undefined;
      this.#lastTurn = undefined;
      this.#held = [];

      this.#asking.clear();

      return;
    }

    if (this.#path === undefined) {
      return;
    }

    if (event.type === 'elicitation_requested') {
      this.#asking.set(event.elicitation.id, event.elicitation);
    }

    // The agent's own cycle is work the session spent on, as a prompt's
    // turn is, though nobody sent one.
    if (event.type === 'cycle_started') {
      this.#begun();

      this.#lastTurn = event.turnId;
    }

    const entry =
      event.type === 'elicitation_settled'
        ? this.#answered(event)
        : entryOf(event, this.#state);

    if (entry?.type === 'state') {
      this.#state = entry;
    }

    if (entry !== undefined) {
      this.#add(entry);
    }

    this.#flush();
  }

  /**
   * An answer's line, once its form's line was written: the questions that
   * form carries say which values are secret and stay out of the file.
   */
  #answered(
    event: Extract<ConversationEvent, { type: 'elicitation_settled' }>,
  ): RecordEntry | undefined {
    const wait = this.#asking.get(event.id);
    const { answer } = event;

    this.#asking.delete(event.id);

    if (wait === undefined) {
      return undefined;
    }

    return {
      type: 'answered',
      turnId: event.turnId,
      id: event.id,
      answer:
        answer.type === 'accepted' &&
        answer.content !== undefined &&
        wait.mode === 'form'
          ? // A form no adapter's marks read can ask for anything, a token
            // among it, with nothing to say which value is one: none of its
            // values reaches the file.
            wait.questions === undefined
            ? { type: 'accepted' }
            : {
                type: 'accepted',
                content: withoutSecrets(wait.questions, answer.content),
              }
          : answer,
    };
  }

  /**
   * What a let-go session said after: its turn's figures, and a cost it
   * said, which a resume counts on from, into that session's record.
   */
  #retiredLine(
    event: Extract<
      ConversationEvent,
      { type: 'retired_usage' | 'retired_update' }
    >,
  ): void {
    const path = this.#retired.get(event.turnId);

    if (path === undefined) {
      return;
    }

    const { type, ...rest } = event;
    const entry: RecordEntry =
      type === 'retired_update'
        ? { type: 'update', turnId: event.turnId, update: event.update }
        : { type: 'usage', ...(rest as TurnFigures) };

    this.#queue.push({ path, line: `${JSON.stringify(entry)}\n` });
    this.#flush();
  }

  /** Work began in the session: what was held for it is kept from now. */
  #begun(): void {
    this.#prompted = true;

    for (const entry of this.#held.splice(0)) {
      this.#add(entry);
    }
  }

  flushed(): Promise<void> {
    return this.#writing;
  }

  #add(entry: RecordEntry): void {
    if (!this.#prompted || this.#path === undefined) {
      this.#held.push(entry);

      return;
    }

    this.#queue.push({ path: this.#path, line: `${JSON.stringify(entry)}\n` });
  }

  /**
   * Appends what is pending, one write at a time so lines land in order;
   * what comes while one is under way goes in the next.
   */
  #flush(): void {
    if (this.#flushing || this.#queue.length === 0) {
      return;
    }

    this.#flushing = true;
    this.#writing = this.#writing.then(async () => {
      try {
        while (this.#queue.length > 0) {
          const batch = this.#queue.splice(0);

          await mkdir(this.#dir, { recursive: true });

          for (const path of new Set(batch.map((each) => each.path))) {
            await appendFile(
              path,
              batch
                .filter((each) => each.path === path)
                .map((each) => each.line)
                .join(''),
            );
          }
        }
      } catch (error) {
        this.#queue = [];

        if (!this.#reported) {
          this.#reported = true;

          this.#failed(
            `Could not keep this session's record: ${
              error instanceof Error ? error.message : String(error)
            }`,
          );
        }
      } finally {
        this.#flushing = false;
      }
    });
  }
}
