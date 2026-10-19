/**
 * Task agents: a session chord opens on any runtime for one job a parent
 * asked for with `spawn_task`. It has no tab: its work is relayed into its
 * parent's stream as a subagent's, under the task's id, so it draws as
 * CHD-149's subagent block in the parent's turn, and its requests reach the
 * person in the parent's tab. It ends with its first turn, whose last message
 * is the report, delivered to the parent as a message; then chord closes it.
 */
import type { SessionUpdate } from '@agentclientprotocol/sdk';
import type { ConversationEvent } from './conversation.ts';
import type { ElicitationReply } from './elicitations.ts';
import { endWord } from './monitors.ts';
import { reduceTranscript } from './transcript/reducer.ts';
import { TASK_META, TASK_SPENT_META } from './transcript/subagents.ts';
import {
  emptyTranscript,
  type MessageFrom,
  type SubagentState,
  type TaskInfo,
  type TaskSpent,
  type TeamPart,
  type Transcript,
} from './transcript/types.ts';
import type { TokenUsage } from './usage.ts';

/**
 * `from` as a message's row and its wrapper name it: a monitor's as its
 * description, `monitor`, and how it ended on its last.
 */
export function fromLine(from: MessageFrom): string {
  const { monitor } = from;

  return (
    monitor === undefined
      ? [from.name, from.runtime, from.note]
      : [
          from.name,
          'monitor',
          monitor.end === undefined ? undefined : endWord(monitor.end),
        ]
  )
    .filter((part) => part !== undefined)
    .join(' · ');
}

/**
 * The sender as a row after `←` names it: `@parser` for a name
 * `send_message` reaches, bare for a task and chord. The wrapper the agent
 * reads keeps the bare name, which is what `send_message` takes.
 */
export function senderName(from: MessageFrom): string {
  return from.reachable ? `@${from.name}` : from.name;
}

/**
 * A message as its recipient gets it, so the agent knows who speaks: never
 * as the person's own words.
 */
export function wrapMessage(from: MessageFrom, text: string): string {
  const monitor =
    from.monitor === undefined ? '' : ` monitor="${from.monitor.id}"`;

  return `<message from="${fromLine(from).replaceAll(
    '"',
    '&quot;',
  )}"${monitor}>\n${text}\n</message>`;
}

/**
 * A team agent's first prompt: the team part in `<team>`, so the agent tells
 * the team's words from the job, then the message that opened it.
 */
export function wrapTeamMessage(
  part: TeamPart,
  from: MessageFrom,
  text: string,
): string {
  const member = part.member === undefined ? '' : ` member="${part.member}"`;

  return `<team name="${part.team}" role="${
    part.member === undefined ? 'lead' : 'member'
  }"${member}>\n${part.text}\n</team>\n${wrapMessage(from, text)}`;
}

const TEAM =
  /^<team name="([^"]*)" role="(?:lead|member)"(?: member="([^"]*)")?>\n([\s\S]*?)\n<\/team>\n(?=<message )/;

const WRAPPED =
  /^<message from="([^"]*)"(?: monitor="([^"]*)")?>\n([\s\S]*)\n<\/message>$/;

/**
 * A prompt that is a wrapped message, read back into who sent it and what
 * was said, with the team part that went ahead of it, as a record keeps it;
 * undefined for any other prompt.
 */
export function unwrapMessage(prompt: string):
  | {
      readonly from: MessageFrom;
      readonly text: string;
      readonly team?: TeamPart;
    }
  | undefined {
  const teamed = TEAM.exec(prompt);
  const match = WRAPPED.exec(
    teamed === null ? prompt : prompt.slice(teamed[0].length),
  );

  if (!match) {
    return undefined;
  }

  const [name = '', runtime, note] = match[1]!
    .replaceAll('&quot;', '"')
    .split(' · ');
  const monitor = match[2];

  return {
    // A monitor's end is read from its record's `from`, not parsed back.
    from:
      monitor !== undefined
        ? { name, monitor: { id: monitor } }
        : {
            name,
            ...(runtime === undefined ? {} : { runtime }),
            ...(note === 'report' || note === 'failed' ? { note } : {}),
          },
    text: match[3]!,
    ...(teamed === null
      ? {}
      : {
          team: {
            team: teamed[1]!,
            ...(teamed[2] === undefined ? {} : { member: teamed[2] }),
            text: teamed[3]!,
          },
        }),
  };
}

/** A task's name: the one asked for, or its prompt's first line. */
export function taskName(name: string | undefined, prompt: string): string {
  const named = name?.trim();

  if (named) {
    return named;
  }

  return prompt.trim().split('\n')[0]?.trim() || 'task';
}

/** The last message the agent sent in turn `turnId`, which is its report. */
export function reportOf(transcript: Transcript, turnId: string): string {
  const last = transcript.entries.findLast(
    (entry) => entry.kind === 'assistant' && entry.turnId === turnId,
  );

  return last?.kind === 'assistant' ? last.text.trim() : '';
}

/** A `subagent_update` for the task, as an adapter's would describe it. */
export function taskUpdate(
  id: string,
  state: SubagentState,
  task?: TaskInfo & { readonly prompt: string },
  spent?: TaskSpent,
): SessionUpdate {
  return {
    sessionUpdate: 'subagent_update',
    sessionId: id,
    state: { state },
    ...(task === undefined
      ? {}
      : { title: task.name, description: task.prompt }),
    ...(task === undefined && spent === undefined
      ? {}
      : {
          _meta: {
            ...(task === undefined
              ? {}
              : {
                  [TASK_META]: {
                    name: task.name,
                    runtime: task.runtime,
                    ...(task.model === undefined ? {} : { model: task.model }),
                    ...(task.effort === undefined
                      ? {}
                      : { effort: task.effort }),
                  },
                }),
            // What it spent, on its ending update (CHD-373).
            ...(spent === undefined ? {} : { [TASK_SPENT_META]: spent }),
          },
        }),
  };
}

/**
 * What a task spent, from its own transcript and its turn's answer: the
 * tokens the answer gave, and the cost its last `usage_update` did, marked
 * when chord worked it out; none when its agent reported neither.
 */
export function taskSpent(
  transcript: Transcript,
  tokens: TokenUsage | undefined,
): TaskSpent | undefined {
  const { usage } = transcript;
  const spent: TaskSpent = {
    ...(tokens === undefined ? {} : { tokens }),
    ...(usage?.cost === undefined ? {} : { cost: usage.cost }),
    ...(usage?.cost !== undefined && usage.estimated?.includes('cost')
      ? { estimated: true as const }
      : {}),
  };

  return Object.keys(spent).length === 0 ? undefined : spent;
}

/** What a task does to its parent, which `Conversation` gives it. */
export interface TaskParent {
  /**
   * An event of the task's, into the parent's stream: its work as a
   * subagent's, its requests as the parent's to answer.
   */
  relay(event: ConversationEvent): void;
  /**
   * The task's report, or its failure, to the parent: a turn, or queued
   * behind the one running.
   */
  deliver(from: MessageFrom, text: string): void;
  /**
   * A line to go ahead of the person's next prompt, as a task the person
   * stopped sends no report: a turn right after Esc would undo the Esc.
   */
  ahead(from: MessageFrom, text: string): void;
  /** The task ended and its agent is closing. */
  ended(): void;
}

/** What a task drives: its own `Conversation`, or a stand-in in a test. */
export interface TaskSession {
  start(): void;
  send(text: string): boolean;
  interrupt(): void;
  choose(id: string, optionId: string): void;
  reject(id: string): void;
  answer(id: string, response: ElicitationReply): void;
  close(): Promise<void>;
}

/** What starts a task: who it is, and what it was asked. */
export interface TaskStart extends TaskInfo {
  /** chord's id for it, which `spawn_task` answers. */
  readonly id: string;
  readonly prompt: string;
}

/**
 * One task agent, from its start to its report. `session` is made with the
 * task's own listener, so every event it reports is heard here first.
 */
export class TaskAgent {
  readonly start: TaskStart;
  readonly #parent: TaskParent;
  readonly #now: () => number;
  #session: TaskSession | undefined;
  /** The task's own transcript, folded here to read its report from. */
  #transcript: Transcript = emptyTranscript;
  #turnId: string | undefined;
  /** The job went to the agent: a cancel stops its turn from here on. */
  #sent = false;
  #ended = false;
  /** The parent cancelled it: it ends `cancelled` and sends no report. */
  #stopped = false;
  /** Its turn's tokens, as the answer to its prompt gave them. */
  #tokens: TokenUsage | undefined;

  constructor(start: TaskStart, parent: TaskParent, now: () => number) {
    this.start = start;
    this.#parent = parent;
    this.#now = now;
  }

  get id(): string {
    return this.start.id;
  }

  get running(): boolean {
    return !this.#ended;
  }

  /** How the task reads, as a message's sender. */
  get from(): MessageFrom {
    return { name: this.start.name, runtime: this.start.runtime };
  }

  /**
   * The effort the task is on once it is up, for its block to say after its
   * model; the window says it only for a task asked for one.
   */
  startedOn(effort: string): void {
    if (this.#ended) {
      return;
    }

    this.#parent.relay({
      type: 'update',
      turnId: '',
      update: taskUpdate(this.id, 'running', { ...this.start, effort }),
      at: this.#now(),
    });
  }

  /** Puts the task in the parent's transcript and starts its agent. */
  begin(session: TaskSession): void {
    this.#session = session;

    this.#parent.relay({
      type: 'update',
      turnId: '',
      update: taskUpdate(this.id, 'running', this.start),
      at: this.#now(),
    });
    session.start();
  }

  /** Every event the task's conversation reports. */
  heard(event: ConversationEvent): void {
    if (this.#ended) {
      return;
    }

    // Only what the report is read from: its own turn and messages.
    if (
      event.type === 'prompt' ||
      event.type === 'result' ||
      (event.type === 'update' && event.subagentId === undefined)
    ) {
      this.#transcript = reduceTranscript(this.#transcript, event);
    }

    switch (event.type) {
      case 'connected':
        this.#sent = true;

        this.#session?.send(this.start.prompt);

        return;
      // A model the runtime refused fails the start, as the task's session
      // requires the one asked for.
      case 'connect_failed':
        return this.#end('failed', event.message);
      // A starting effort or mode it was refused, before it is up: the task
      // runs on the agent's own, and the person is told which task it was.
      case 'failed':
        return this.#sent
          ? undefined
          : this.#parent.relay({
              ...event,
              message: `${this.start.name}: ${event.message}`,
            });
      case 'prompt':
        this.#turnId = event.turnId;

        return;
      case 'update':
        return this.#parent.relay({
          ...event,
          subagentId: event.subagentId ?? this.id,
        });
      case 'served':
        return this.#parent.relay({
          ...event,
          subagentId: event.subagentId ?? this.id,
        });
      case 'permission_requested':
        return this.#parent.relay({
          ...event,
          at: this.#now(),
          permission: {
            ...event.permission,
            subagentId: event.permission.subagentId ?? this.id,
          },
        });
      case 'elicitation_requested':
        return this.#parent.relay({
          ...event,
          elicitation: { ...event.elicitation, subagentId: this.id },
        });
      case 'permission_settled':
      case 'elicitation_settled':
        return this.#parent.relay(event);
      case 'disconnected':
        return this.#end('disconnected', `${this.start.runtime} exited`);
      case 'result': {
        if (event.turnId !== this.#turnId) {
          return;
        }

        const { result } = event;

        this.#tokens = result.status === 'failed' ? undefined : result.usage;

        return result.status === 'failed'
          ? this.#end('failed', result.error.message)
          : result.status === 'cancelled'
            ? this.#end('cancelled', '')
            : this.#end('completed', reportOf(this.#transcript, event.turnId));
      }
      default:
        return;
    }
  }

  /**
   * Stops the task's turn, as the parent's Esc does; it sends no report. One
   * still starting has no turn to stop: it ends here, so its job is never
   * sent.
   */
  cancel(): void {
    if (this.#ended) {
      return;
    }

    this.#stopped = true;

    if (!this.#sent) {
      return this.#end('cancelled', '');
    }

    this.#session?.interrupt();
  }

  choose(id: string, optionId: string): void {
    this.#session?.choose(id, optionId);
  }

  reject(id: string): void {
    this.#session?.reject(id);
  }

  answer(id: string, response: ElicitationReply): void {
    this.#session?.answer(id, response);
  }

  /**
   * Closes the task's agent; one still running ends `cancelled` first, as
   * the parent closing takes it with it.
   */
  close(): Promise<void> {
    if (!this.#ended) {
      this.#stopped = true;

      this.#end('cancelled', '');
    }

    return this.#session?.close() ?? Promise.resolve();
  }

  #end(state: SubagentState, text: string): void {
    if (this.#ended) {
      return;
    }

    this.#ended = true;

    this.#parent.relay({
      type: 'update',
      turnId: '',
      update: taskUpdate(
        this.id,
        state,
        undefined,
        taskSpent(this.#transcript, this.#tokens),
      ),
      at: this.#now(),
    });

    if (state === 'cancelled' || this.#stopped) {
      this.#parent.ahead(
        this.from,
        'The person stopped this task before it reported.',
      );
    } else {
      this.#parent.deliver(
        { ...this.from, note: state === 'completed' ? 'report' : 'failed' },
        text === '' ? '(no report)' : text,
      );
    }

    this.#parent.ended();
  }
}
