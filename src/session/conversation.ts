import type { AvailableCommand, SessionUpdate } from '@agentclientprotocol/sdk';
import { setTimeout as delay } from 'node:timers/promises';
import type { ResourceLink } from '../files.ts';
import { type AgentOption, sameOptions, valueName } from './config.ts';
import { type AgentModels, sameModels } from './models.ts';
import type { ElicitationReply, PendingElicitation } from './elicitations.ts';
import { type AgentModes, sameModes } from './modes.ts';
import {
  DEFAULT_TIMEOUT_MS,
  endSentence,
  endWord,
  type EventLines,
  eventText,
  type MonitorArgs,
  type MonitorInfo,
  MonitorRun,
  type MonitorsPast,
  monitorsPast,
  type EndedMonitor,
  type RunCommand,
  runMonitorCommand,
  type RunningMonitor,
  withLines,
} from './monitors.ts';
import { type PendingPermission, waitFor } from './permissions.ts';
import {
  askStarting,
  type StartingAsk,
  type StartingValue,
} from './starting.ts';
import type {
  Attachment,
  OpenSessionOptions,
  Session,
  SteerOutcome,
  Turn,
} from './session.ts';
import {
  type TaskAgent,
  type TaskParent,
  type TaskSession,
  wrapMessage,
  wrapTeamMessage,
} from './tasks.ts';
import type {
  ChordCall,
  ElicitationAnswer,
  ElicitationWait,
  MessageFrom,
  MonitorEnd,
  PermissionAnswer,
  PermissionWait,
  TeamPart,
  TranscriptAction,
  TurnResult,
} from './transcript/types.ts';
import type { TokenUsage } from './usage.ts';
import { type CutCall, cutNote } from './cut_off.ts';
import { chordCallOf, servedFor } from './transcript/chord.ts';
import { mergeToolCall } from './transcript/tools.ts';
import { emptyTranscript, type Transcript } from './transcript/types.ts';

/**
 * What a conversation reports: the transcript reducer's actions, plus the
 * session's own coming and going, which no turn carries.
 */
export type ConversationEvent =
  | TranscriptAction
  /**
   * The session is up; `sessionId` is the agent's id for it, and `at` when it
   * came up, epoch milliseconds.
   */
  | {
      readonly type: 'connected';
      readonly sessionId: string;
      readonly at?: number;
    }
  | { readonly type: 'connect_failed'; readonly message: string }
  /**
   * The session opened is an earlier one, last used at `lastUsedAt`, first
   * prompted with `prompt` and, for an agent another started, called `name`,
   * where chord's record says; reported first, before its past.
   */
  | {
      readonly type: 'resumed';
      readonly lastUsedAt?: number;
      readonly prompt?: string;
      readonly name?: string;
    }
  /**
   * What the agent takes in a prompt besides text, as its
   * `promptCapabilities` say; reported before `connected`.
   */
  | { readonly type: 'prompt_capabilities'; readonly image: boolean }
  /**
   * The models the agent offers and the one it says it uses; none when it
   * advertises none.
   */
  | { readonly type: 'model'; readonly models: AgentModels | undefined }
  /**
   * The agent's modes, when they differ from the last reported, and after
   * every mode change the agent answered.
   */
  | { readonly type: 'modes'; readonly modes: AgentModes | undefined }
  /** A turn's tokens, as the agent's answer to its prompt gave them. */
  | {
      readonly type: 'usage';
      readonly turnId: string;
      readonly usage: TokenUsage;
    }
  /**
   * The agent's config options other than its mode and model, when they
   * differ from the last reported.
   */
  | { readonly type: 'options'; readonly options: readonly AgentOption[] }
  /** A mode was asked for; the agent has not answered yet. */
  | { readonly type: 'mode_asked'; readonly id: string }
  /** The agent answered for that mode, and what it reports has been read. */
  | { readonly type: 'mode_answered'; readonly id: string }
  /**
   * A prompt sent while a turn runs, held until the turns ahead of it have
   * ended; its `prompt` comes then.
   */
  | {
      readonly type: 'queued';
      readonly turnId: string;
      readonly text: string;
      /** Set on a message from another agent, or chord. */
      readonly from?: MessageFrom;
      /**
       * A message held while the turn it goes into waits on the person: it
       * goes in once they answer.
       */
      readonly afterAnswer?: true;
      /**
       * A message held while the turn it goes into has tool calls open that
       * a steer would cut off: it goes in once they have ended (CHD-423).
       */
      readonly afterCalls?: true;
    }
  /**
   * An interrupt took every queued prompt of the person's back; none of them
   * will run. Messages stay queued, and go once the interrupted turn ends.
   */
  | { readonly type: 'queue_withdrawn' }
  /** The agent's slash commands, when they differ from the last reported. */
  | {
      readonly type: 'commands';
      readonly commands: readonly AvailableCommand[];
    }
  /**
   * The session was let go for a new one, which starts now: everything the
   * old one reported is gone, and `connected` comes again.
   */
  | { readonly type: 'cleared' }
  /**
   * A long-lived agent of the session's, by chord's id for it, was closed
   * while the session goes on, by `close_agent` or the person; the record
   * keeps it, so a resume knows the agents still open when the session was
   * left.
   */
  | { readonly type: 'agent_closed'; readonly id: string }
  /**
   * The person's `/team run` started a run of the session's: the record keeps
   * it as the `run_team` call it was, so a resume knows the run was open. It
   * draws nothing there, as no call of the agent's asked for it, and the
   * window drew it under the command already.
   */
  | {
      readonly type: 'run_typed';
      readonly turnId: string;
      readonly call: ChordCall;
    }
  /**
   * The session's monitors still running, whenever one starts, hands on an
   * event or ends, and those ended since it came up, in the order they
   * ended; the window's alone, as none is restarted on a resume.
   */
  | {
      readonly type: 'monitors';
      readonly monitors: readonly RunningMonitor[];
      readonly ended: readonly EndedMonitor[];
    }
  | { readonly type: 'closing' };

export type OpenSession = (options: OpenSessionOptions) => Promise<Session>;

/**
 * Where a conversation keeps its sessions: it hears what the reducer is
 * handed, from the moment a session is up, and the prompts as the agent got
 * them, which the reducer never sees.
 */
export interface Recording {
  /** A session is up, its past already played out; it is recorded from now. */
  opened(session: Session): void;
  /**
   * A prompt went to the agent: its text, then `images` images, then `links`,
   * who sent it when it is a message, and the running turn it went `into`
   * when it started none. One that never went is not heard of, nor is its
   * turn's end.
   */
  sent(
    turnId: string,
    prompt: string,
    images: number,
    links: readonly ResourceLink[],
    at: number,
    from?: MessageFrom,
    into?: string,
  ): void;
  /** Each event the conversation reports, in order. */
  heard(event: ConversationEvent): void;
  /** Settles once what was heard so far is kept. */
  flushed(): Promise<void>;
}

/** What each session the conversation opens is put on before it is shown. */
export interface Starting {
  /** A model, as `/model` sets it. */
  readonly model?: StartingValue | undefined;
  /** A mode, as shift+tab sets it. */
  readonly mode?: StartingValue | undefined;
  /**
   * An effort, as `/config` sets it, asked for after the model, whose own
   * efforts the agent offers. Never required: a refusal leaves the session
   * on the agent's own.
   */
  readonly effort?: StartingValue | undefined;
}

/** A prompt to send: what the transcript shows, and what the agent gets. */
interface Prompt {
  readonly turnId: string;
  readonly text: string;
  readonly prompt: string;
  readonly attachments: readonly Attachment[];
  readonly mentions: readonly string[];
  /** Set on a message from another agent, or chord. */
  readonly from?: MessageFrom;
  /** The team part that goes ahead of a team agent's first message. */
  readonly team?: TeamPart;
  /**
   * A message waiting for the person's answer to go into the running turn;
   * if the turn ends first, it goes as the next one.
   */
  readonly afterAnswer?: true;
}

/** How a message to the session went: straight into a turn, or queued. */
export type Delivery = 'sent' | 'queued';

/** A monitor started, as `monitor` answers it. */
export interface MonitorStarted {
  readonly id: string;
  readonly description: string;
  readonly timeout_ms: number;
}

/** A monitor the agent stopped, as `stop_monitor` answers it. */
export interface MonitorStopped {
  readonly id: string;
  readonly description: string;
  readonly events: number;
  readonly ran_ms: number;
}

/** A running monitor, and the message of its still queued, if one is. */
interface Monitoring {
  readonly run: MonitorRun;
  queued?: { readonly turnId: string; lines: EventLines } | undefined;
}

const NO_PAST: MonitorsPast = { last: 0, ended: new Map(), left: [] };

function messageOf(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

/** How long the agent must be silent after an answer to have finished. */
const QUIET_MS = 1000;
/** How long the next queued prompt waits for that silence at most. */
const SETTLE_LIMIT_MS = 5000;

/** The updates after which the agent's modes, options or commands may differ. */
const STATE_UPDATES: ReadonlySet<string> = new Set([
  'config_option_update',
  'current_mode_update',
  'available_commands_update',
]);

/**
 * The updates whose time the transcript keeps, on chord's clock: a subagent's
 * start and end, which no update carries a time for.
 */
const TIMED_UPDATES: ReadonlySet<string> = new Set(['subagent_update']);

/**
 * One session and the turn in flight in it, driven for an interface: it opens
 * the session, plays each prompt and the agent's updates out as
 * `ConversationEvent`s, holds the prompts sent during a turn, cancels, and
 * closes the agent. It holds no state the interface draws; that is the
 * reducers' job.
 */
export class Conversation {
  /**
   * Opens a session; the signal gives up on one still starting, so a quit or
   * a `/clear` never waits on an agent that does not answer.
   */
  readonly #open: (signal: AbortSignal) => Promise<Session>;
  readonly #emit: (event: ConversationEvent) => void;
  /** The window alone, for what the record must not keep. */
  readonly #show: (event: ConversationEvent) => void;
  readonly #now: () => number;
  readonly #starting: Starting;
  readonly #recording: Recording | undefined;
  /** What the refusal of the starting effort said, for the tool's answer. */
  #effortRefused: string | undefined;
  #opening: Promise<Session | undefined> | undefined;
  /** Gives up on the session `#opening` starts, and on those `clear` let go. */
  readonly #stops = new Set<AbortController>();
  #session: Session | undefined;
  /** The turn on screen, and its id. */
  #turn: { readonly id: string; readonly turn: Turn } | undefined;
  /**
   * The last turn's id, which an update after its answer or outside any turn
   * is folded under.
   */
  #lastTurnId = 'session';
  /**
   * The turn the agent started on its own with a steer that missed chord's,
   * which chord cancelled, until chord's next turn: what the agent sends
   * meanwhile is that turn's, not the turn of chord's before it.
   */
  #selfTurnId: string | undefined;
  /**
   * The turn whose prompt has gone to the agent. One with mentions waits on
   * their walk first, and a steer before it went would find no turn running.
   */
  #wentId: string | undefined;
  /** Prompts sent during the turn on screen, oldest first, not sent yet. */
  #queued: Prompt[] = [];
  /**
   * The turn that takes no message any more: it answered, an interrupt
   * cancelled it, or the agent answered a steer as if no turn of chord's were
   * running.
   */
  #sealed: string | undefined;
  /**
   * The steers the agent has not answered yet. They hold the queue: Codex's
   * adapter starts a turn of its own with a steer that missed the turn, and
   * a prompt of chord's sent meanwhile would run alongside it.
   */
  #steers = new Set<object>();
  /**
   * Settles once the last steer sent has its answer. Steers go one at a
   * time, so one after a steer that missed the turn is never put into the
   * turn the agent started with it, which chord cancels.
   */
  #steering = Promise.resolve();
  /**
   * The tool calls of the turn on screen not ended yet, by id, which hold a
   * steer back on an agent whose steer cuts them off.
   */
  #openCalls = new Set<string>();
  /** The turn's own calls as its updates have merged them, to tell a cut one. */
  #calls: Transcript = emptyTranscript;
  /** What chord served to the turn on screen, which a cut call never was. */
  #servedNow: ChordCall[] = [];
  /**
   * Calls of chord's tools cut off before they reached chord, which the
   * agent is told of ahead of its next turn (CHD-417), each once, with the
   * place it was made in among the calls.
   */
  #cut: {
    readonly id: string;
    readonly made: number;
    readonly call: CutCall;
  }[] = [];
  /** When each of the turn's calls was made, by id, from `#made`. */
  #madeAt = new Map<string, number>();
  /** Counts the calls made, never reset, so older ones always come first. */
  #made = 0;
  /**
   * Wakes the steers waiting on the person's answer or the turn's open
   * calls: something they wait on changed, a question answered, the last
   * call ended, the turn ended, or the session let go.
   */
  #wake = Promise.withResolvers<void>();
  /**
   * Stops the wait for a finished turn's trailing updates, while one is
   * holding the queue back.
   */
  #settling: AbortController | undefined;
  /** When the agent last sent an update, by `performance.now()`. */
  #heardAt = 0;
  /**
   * Requests on screen, by id, with the turn that asked, until they are
   * answered or withdrawn.
   */
  readonly #permissions = new Map<
    string,
    {
      readonly request: PendingPermission;
      readonly turnId: string;
      /** Asked with no turn running (CHD-158). */
      readonly between?: true;
    }
  >();
  /**
   * chord's own questions on screen, each withdrawn by calling it: they go
   * with their turn, an interrupt, `clear` and the close.
   */
  readonly #asks = new Set<() => void>();
  /** Forms and links on screen, by id, the same way. */
  readonly #elicitations = new Map<
    string,
    {
      readonly request: PendingElicitation;
      readonly turnId: string;
      /** Asked with no turn running (CHD-158). */
      readonly between?: true;
    }
  >();
  #closing: Promise<void> | undefined;
  /**
   * Sessions let go by `clear`, closing; `close` waits for them too. Each
   * settles with the error its close failed with, if it did.
   */
  readonly #retiring: Promise<unknown>[] = [];
  /** The last of each reported, so a reading that says nothing new stays quiet. */
  #models: AgentModels | undefined;
  #modes: AgentModes | undefined;
  #commands: readonly AvailableCommand[] = [];
  #options: readonly AgentOption[] = [];
  /** Mode changes asked for, one after another, so they land in order. */
  #modeChanges: Promise<void> = Promise.resolve();
  /** Model changes, for the same reason. */
  #modelChanges: Promise<void> = Promise.resolve();
  /** Config option changes, for the same reason. */
  #optionChanges: Promise<void> = Promise.resolve();
  #failures = 0;
  /** Lines to go ahead of the person's next prompt, as held output does. */
  #ahead: string[] = [];
  /** The task agents the session started, still running or closing, by id. */
  readonly #tasks = new Map<string, TaskAgent>();
  /** Requests of the task agents on screen, by id, with the task that asks. */
  readonly #foreign = new Map<string, TaskAgent>();
  /** Of those, the requests a task asked with no turn running (CHD-158). */
  readonly #foreignBetween = new Set<string>();
  /**
   * The quiet wait started once a request between turns was answered, which
   * a later answer starts again rather than ride out (CHD-158).
   */
  #betweenQuiet: AbortController | undefined;
  /** Ended task agents' closes, which the session's own close waits for. */
  readonly #endedTasks = new Set<Promise<void>>();
  /** The session's monitors still running, by id, in start order. */
  readonly #monitors = new Map<string, Monitoring>();
  /**
   * Monitors the person stopped, off the list at once, until their end
   * message goes.
   */
  readonly #ending = new Map<string, Monitoring>();
  /** What the session's past says of its monitors; an end adds to it. */
  #monitorsPast: MonitorsPast = NO_PAST;
  /** How each monitor ended since, by id, as its end's word says it. */
  readonly #monitorsEnded = new Map<string, string>();
  /** The monitors ended since the session came up, as the window shows them. */
  #endedMonitors: EndedMonitor[] = [];
  /** The last monitor id's number given out. */
  #monitorCount = 0;
  /** Monitors stopping, which a close waits for to be gone. */
  readonly #monitorsStopping = new Set<Promise<void>>();

  constructor(
    open: (signal: AbortSignal) => Promise<Session>,
    emit: (event: ConversationEvent) => void,
    now: () => number = Date.now,
    starting: Starting = {},
    recording?: Recording,
  ) {
    this.#open = open;
    // The record hears each event before the window does, as the window
    // may quit on one.
    this.#show = emit;
    this.#emit =
      recording === undefined
        ? emit
        : (event) => {
            recording.heard(event);
            emit(event);
          };

    this.#now = now;
    this.#starting = starting;
    this.#recording = recording;
  }

  /** The session the agent has opened; none while it still starts. */
  get session(): Session | undefined {
    return this.#session;
  }

  /**
   * Why the session is not on the starting effort, as the transcript says
   * it: `Could not start on max effort, …`; none when it took it or none was
   * asked for.
   */
  get effortRefused(): string | undefined {
    return this.#effortRefused;
  }

  /** Starts the agent; reports `connected` or `connect_failed`. */
  start(): void {
    if (this.#opening) {
      return;
    }

    const stop = new AbortController();

    this.#stops.add(stop);

    // Settles once the agent has a session, not once it is set up: a close
    // or a `clear` lets it go from there, whatever the agent leaves unanswered
    // in `#setUp`.
    const opening: Promise<Session | undefined> = this.#open(stop.signal).then(
      (session) => {
        // `clear` let this one go while it started; it closes it.
        if (this.#opening === opening) {
          this.#session = session;

          void this.#setUp(session).catch((error: unknown) => {
            if (this.#current(session)) {
              this.#emit({ type: 'connect_failed', message: messageOf(error) });
            }
          });
        }

        return session;
      },
      (error) => {
        if (this.#closing === undefined && this.#opening === opening) {
          this.#emit({ type: 'connect_failed', message: messageOf(error) });
        }

        return undefined;
      },
    );

    this.#opening = opening;

    void opening.finally(() => this.#stops.delete(stop));
  }

  /**
   * Lets the session go and starts a new one in its place, as `/clear` asks:
   * the agent forgets the conversation, and the transcript starts empty. The
   * old agent is closed alongside; a turn in it ends with it.
   */
  clear(): void {
    const opening = this.#opening;

    if (!opening || this.#closing) {
      return;
    }

    this.#opening = undefined;
    this.#session = undefined;
    this.#turn = undefined;
    this.#lastTurnId = 'session';
    this.#selfTurnId = undefined;
    this.#wentId = undefined;
    // They go with the session they were queued in.
    this.#queued = [];
    this.#steers = new Set();
    this.#steering = Promise.resolve();
    this.#openCalls = new Set();
    this.#calls = emptyTranscript;
    this.#madeAt = new Map();
    this.#servedNow = [];
    this.#cut = [];

    this.#rouse();

    // The old session's wait must not hold the new one's first prompt back.
    this.#settling?.abort();

    this.#settling = undefined;
    this.#models = undefined;
    this.#modes = undefined;
    this.#commands = [];
    this.#options = [];

    // The old session withdraws them as it closes; nothing is left to draw
    // them on.
    this.#withdrawAsks();
    this.#permissions.clear();
    this.#elicitations.clear();

    // Its task agents go with it, let go first so that nothing they say as
    // they close reaches the new session; so do the messages and lines they
    // left for it.
    const tasks = [...this.#tasks.values()];

    this.#tasks.clear();
    this.#foreign.clear();
    this.#foreignBetween.clear();

    this.#ahead = [];

    // A new session, whose agent started none of them and whose ids start
    // again at m1.
    const monitors = this.#stopMonitors();

    this.#monitorsPast = NO_PAST;

    this.#monitorsEnded.clear();

    this.#endedMonitors = [];
    this.#monitorCount = 0;

    this.#emit({ type: 'cleared' });
    this.#retiring.push(
      opening
        .then((session) => session?.close())
        .then(
          () => undefined,
          (error: unknown) => error,
        ),
      ...tasks.map((task) =>
        task.close().then(
          () => undefined,
          (error: unknown) => error,
        ),
      ),
      monitors,
    );
    this.start();
  }

  /**
   * Reports the agent's slash commands if they moved: the interface asks when
   * it is about to show them.
   */
  readCommands(): void {
    if (this.#session) {
      this.#report(this.#session);
    }
  }

  /**
   * Reports the agent's config options if they moved: the interface asks when
   * `/config` is about to list them.
   */
  readOptions(): void {
    if (this.#session) {
      this.#report(this.#session);
    }
  }

  /**
   * Sends a prompt and plays its turn out. While a turn runs, it waits behind
   * that one, and is reported `queued` until its turn comes. Refused (false)
   * before the session is up and once closing. `prompt` is what the agent
   * gets, when it is more than the `text` the transcript shows, such as held
   * shell output ahead of it; `attachments` go after it, and a link to each
   * of the `mentions` that is a file.
   */
  send(
    text: string,
    prompt: string = text,
    attachments: readonly Attachment[] = [],
    mentions: readonly string[] = [],
  ): boolean {
    const session = this.#session;

    if (!session || this.#closing) {
      return false;
    }

    const ahead = this.#ahead.splice(0);
    const next = {
      turnId: crypto.randomUUID(),
      text,
      prompt: [...ahead, prompt].join('\n\n'),
      attachments,
      mentions,
    };

    this.#enqueue(session, next);

    return true;
  }

  /**
   * A message from another agent, or chord: a turn of its own, wrapped so
   * the agent sees who speaks, queued behind a running turn as a prompt is,
   * with the team part ahead of it for a team agent's first.
   * Undefined before the session is up and once closing.
   */
  deliver(
    from: MessageFrom,
    text: string,
    team?: TeamPart,
  ): Delivery | undefined {
    return this.#message(from, text, team)?.delivery;
  }

  /**
   * A message another agent sent with `send_message`: while a turn of
   * chord's runs on an agent that takes steering, it goes into that turn at
   * once, or, while the turn waits on the person's answer to a permission, a
   * form or a link, once they answer; a steer the agent refuses, as when the
   * turn ended on the way, or starts a turn of its own with, which is
   * cancelled, goes as the next turn. Otherwise it goes as
   * `deliver` sends one. `sent` for a steer, as the message did not wait;
   * `queued` is called if it goes as the next turn after all.
   */
  tell(
    from: MessageFrom,
    text: string,
    queued?: () => void,
  ): Delivery | undefined {
    const session = this.#session;

    if (!session || this.#closing) {
      return undefined;
    }

    const into = this.#steerable(session);

    if (into === undefined) {
      return this.deliver(from, text);
    }

    const next: Prompt = {
      turnId: crypto.randomUUID(),
      text,
      prompt: wrapMessage(from, text),
      attachments: [],
      mentions: [],
      from,
    };

    if (this.#waitsOnPerson()) {
      this.#queued.push({ ...next, afterAnswer: true });
      this.#emit({
        type: 'queued',
        turnId: next.turnId,
        text,
        from,
        afterAnswer: true,
      });

      return 'queued';
    }

    void this.#steer(session, into, next, queued);

    return 'sent';
  }

  /**
   * The turn of chord's a message can go into now: its prompt gone to the
   * agent, not answered yet, not interrupted, on an agent that takes
   * steering.
   */
  #steerable(session: Session): string | undefined {
    const turn = this.#turn;

    return turn !== undefined &&
      this.#wentId === turn.id &&
      !this.#settling &&
      this.#sealed !== turn.id &&
      session.steers()
      ? turn.id
      : undefined;
  }

  /**
   * Whether the session's turn waits on the person: a permission of its
   * agent's or a question of chord's in the box, or a form or link. A task
   * agent's requests are the task's to wait on.
   */
  #waitsOnPerson(): boolean {
    return this.#permissions.size > 0 || this.#elicitations.size > 0;
  }

  /** Whether a request asked with no turn running waits on the person. */
  #waitsBetween(): boolean {
    return (
      this.#foreignBetween.size > 0 ||
      [...this.#permissions.values(), ...this.#elicitations.values()].some(
        (asked) => asked.between,
      )
    );
  }

  /**
   * A request between turns came: everything queued now waits for its
   * answer, and says so, whatever it waited for before (CHD-158).
   */
  #holdForAnswer(): void {
    this.#queued = this.#queued.map((queued) => {
      if (queued.afterAnswer) {
        return queued;
      }

      this.#emit({
        type: 'queued',
        turnId: queued.turnId,
        text: queued.text,
        ...(queued.from === undefined ? {} : { from: queued.from }),
        afterAnswer: true,
      });

      return { ...queued, afterAnswer: true };
    });
  }

  /**
   * The tool calls a steer told now waits out: those the turn has open at
   * this moment, on an agent whose steer cuts them off, and none on any
   * other. Calls opened later never extend the wait: held only until these
   * have ended, it goes into the same turn (the owner's answer on CHD-417).
   */
  #cutNow(session: Session): ReadonlySet<string> {
    return this.#openCalls.size > 0 && session.cutsCallsOnSteer()
      ? new Set(this.#openCalls)
      : new Set();
  }

  /**
   * Puts a message into turn `into`, drawn and recorded there once the agent
   * has taken it; refused, it goes as the next turn, as a message queued
   * behind the turn does, and `queued` is called.
   */
  async #steer(
    session: Session,
    into: string,
    next: Prompt,
    queued?: () => void,
  ): Promise<void> {
    const steer = {};
    const ahead = this.#steering;
    // Taken before any wait, as the message arrives.
    const awaited = this.#cutNow(session);
    const open = () => [...awaited].some((id) => this.#openCalls.has(id));
    const { promise: answered, resolve: answer } =
      Promise.withResolvers<void>();
    let outcome: SteerOutcome;

    // What its queue row says it waits on, once it has one.
    let shown: 'answer' | 'calls' | undefined;
    const show = (why: 'answer' | 'calls') => {
      if (shown === why) {
        return;
      }

      shown = why;

      this.#emit({
        type: 'queued',
        turnId: next.turnId,
        text: next.text,
        ...(next.from === undefined ? {} : { from: next.from }),
        ...(why === 'answer' ? { afterAnswer: true } : { afterCalls: true }),
      });
    };

    this.#steers.add(steer);

    this.#steering = answered;

    // Held for the calls open as it came, it waits in the queue at once, in
    // its order among the messages before it, as one held for an answer
    // does, until it goes in (CHD-423).
    if (this.#steerable(session) === into && open()) {
      show('calls');
    }

    try {
      await ahead;

      // The steer ahead may have found the turn over, or the person may have
      // been asked something while it was out.
      if (this.#steerable(session) === into) {
        if (this.#waitsOnPerson()) {
          show('answer');
        } else if (open()) {
          show('calls');
        }
      }

      while (
        this.#steerable(session) === into &&
        (this.#waitsOnPerson() || open())
      ) {
        await this.#wake.promise;
      }

      outcome =
        this.#steerable(session) === into
          ? await session.steer(next.prompt)
          : 'refused';
    } catch {
      outcome = 'refused';
    } finally {
      this.#steers.delete(steer);
      answer();
    }

    if (!this.#current(session)) {
      return;
    }

    // The agent has no turn of chord's running, whatever chord has seen of
    // its answer yet: the messages after this one go as turns of their own.
    if (outcome !== 'injected') {
      this.#sealed = into;

      queued?.();
    }

    if (outcome === 'refused') {
      this.#enqueue(session, next);
      void this.#advance(session);

      return;
    }

    // The steer missed the turn and Codex's adapter started one of its own
    // with it, which no prompt of chord's awaits. The owner's call on
    // CHD-365: cancel that turn at once and send the message as chord's next
    // turn, once the agent has gone quiet, as a message queued behind a turn
    // goes; what the agent did with it before the cancel landed stands.
    if (outcome === 'startedNewTurn') {
      const own = crypto.randomUUID();

      this.#selfTurnId = own;

      session.cancel().catch(() => {
        // The turn may have ended before the cancel landed.
      });

      // A line of its own closes it, so what it drew never reads as the
      // reply of chord's turn before it (CHD-365's design).
      if (next.from !== undefined) {
        this.#emit({ type: 'self_started', turnId: own, from: next.from });
      }

      const quiet = this.#quieten(session);

      this.#hold(next);
      await quiet;
      await this.#advance(session);

      return;
    }

    const at = this.#now();

    this.#emit({
      type: 'prompt',
      turnId: next.turnId,
      text: next.text,
      at,
      ...(next.from === undefined ? {} : { from: next.from }),
      into,
    });
    this.#recording?.sent(next.turnId, next.prompt, 0, [], at, next.from, into);
    // The turn may have answered while the steer was out, the queue held.
    void this.#advance(session);
  }

  /**
   * Once the person has answered the last question the turn waited on, the
   * messages held for it go into the turn, oldest first.
   */
  #release(): void {
    const session = this.#session;

    this.#rouse();

    if (!session || this.#closing || this.#waitsOnPerson()) {
      return;
    }

    // A request between turns answered: what waited for it goes in turn.
    if (!this.#turn) {
      void this.#answeredBetween(session);

      return;
    }

    const into = this.#steerable(session);
    const held = this.#queued.filter((queued) => queued.afterAnswer);

    if (into === undefined || held.length === 0) {
      return;
    }

    this.#queued = this.#queued.filter((queued) => !queued.afterAnswer);

    for (const { afterAnswer: _, ...message } of held) {
      void this.#steer(session, into, message);
    }
  }

  /**
   * Once a request between turns is answered, what waited for it goes, after
   * the agent has gone quiet, as after a turn's answer: the work that asked
   * says what it did with the answer outside any turn, and the next turn
   * must not take that for its own (CHD-158).
   */
  async #answeredBetween(session: Session): Promise<void> {
    this.#unhold();

    if (this.#queued.length === 0) {
      return;
    }

    // The quiet an earlier answer started counts again from this one, as
    // the work that asked this time may still be about to say so; any other
    // wait sends the queue on itself once it is over.
    if (this.#settling !== undefined) {
      if (this.#settling !== this.#betweenQuiet) {
        return;
      }

      this.#settling.abort();
    }

    const quiet = this.#quieten(session);

    this.#betweenQuiet = this.#settling;

    await quiet;
    await this.#advance(session);
  }

  /** Wakes the steers waiting on the person's answer to look again. */
  #rouse(): void {
    this.#wake.resolve();

    this.#wake = Promise.withResolvers<void>();
  }

  /**
   * The messages held for the person's answer wait, from now, for the turn's
   * end as any message does: the turn ended or was interrupted.
   */
  #unhold(): void {
    this.#rouse();

    this.#queued = this.#queued.map((queued) => {
      if (!queued.afterAnswer) {
        return queued;
      }

      const { afterAnswer: _, ...message } = queued;

      this.#emit({
        type: 'queued',
        turnId: message.turnId,
        text: message.text,
        ...(message.from === undefined ? {} : { from: message.from }),
      });

      return message;
    });
  }

  /**
   * A message that starts no turn: it goes ahead of the person's next
   * prompt, as held shell output does.
   */
  aside(from: MessageFrom, text: string): void {
    this.#ahead.push(wrapMessage(from, text));
  }

  #message(
    from: MessageFrom,
    text: string,
    team?: TeamPart,
  ): { readonly delivery: Delivery; readonly turnId: string } | undefined {
    const session = this.#session;

    if (!session || this.#closing) {
      return undefined;
    }

    const turnId = crypto.randomUUID();

    return {
      delivery: this.#enqueue(session, {
        turnId,
        text,
        prompt:
          team === undefined
            ? wrapMessage(from, text)
            : wrapTeamMessage(team, from, text),
        attachments: [],
        mentions: [],
        from,
        ...(team === undefined ? {} : { team }),
      }),
      turnId,
    };
  }

  /**
   * Rewrites message `turnId` while it is still queued, reported `queued`
   * again in its place; false once it has gone to the agent.
   */
  #requeue(turnId: string, from: MessageFrom, text: string): boolean {
    const index = this.#queued.findIndex((queued) => queued.turnId === turnId);

    if (index === -1) {
      return false;
    }

    this.#queued[index] = {
      ...this.#queued[index]!,
      text,
      prompt: wrapMessage(from, text),
      from,
    };

    this.#emit({ type: 'queued', turnId, text, from });

    return true;
  }

  /**
   * Starts a monitor for the session's agent: its command in `cwd`, each
   * batch of its lines a message to the agent later, as is its end. Refused
   * before the session is up, once closing, and when the shell does not
   * start; what it was asked is checked by `monitorRefusal` first.
   */
  startMonitor(
    args: MonitorArgs,
    cwd: string,
    run: RunCommand = runMonitorCommand,
  ): MonitorStarted | { readonly error: string } {
    if (!this.#session || this.#closing) {
      return { error: 'This session has closed' };
    }

    const info: MonitorInfo = {
      id: `m${this.#monitorsPast.last + this.#monitorCount + 1}`,
      description: args.description.trim(),
      command: args.command,
      startedAt: this.#now(),
      timeoutMs: args.timeoutMs ?? DEFAULT_TIMEOUT_MS,
    };
    // By the run, not its id: one stopped before a `/clear` ends after it,
    // when the new session's m1 is another.
    const started: MonitorRun | { readonly error: string } = MonitorRun.start(
      info,
      {
        event: (lines) => this.#monitorEvent(info, started, lines),
        ended: (end, rest) => this.#monitorEnded(info, started, end, rest),
      },
      cwd,
      run,
    );

    if ('error' in started) {
      return started;
    }

    this.#monitorCount += 1;

    this.#monitors.set(info.id, { run: started });
    this.#showMonitors();

    return {
      id: info.id,
      description: info.description,
      timeout_ms: info.timeoutMs,
    };
  }

  /**
   * Stops subagent `id` alone, as the person asked: it reads stopping until
   * its agent says how it ended, or goes back as it was when the stop could
   * not be sent, which the promise rejects with.
   */
  async stopSubagent(id: string): Promise<void> {
    const session = this.#session;

    if (session === undefined) {
      throw new Error('the agent is not connected');
    }

    this.#emit({
      type: 'subagent_stopping',
      turnId: 'stop',
      subagentId: id,
      stopping: true,
    });

    try {
      await session.stopSubagent(id);
    } catch (error) {
      this.#emit({
        type: 'subagent_stopping',
        turnId: 'stop',
        subagentId: id,
        stopping: false,
      });

      throw error;
    }
  }

  /**
   * Stops monitor `id`: the agent's own `stop_monitor`, which its answer
   * tells it of, or the person's, which a message does.
   */
  stopMonitor(
    id: string,
    by: 'agent' | 'person' = 'agent',
  ): MonitorStopped | { readonly error: string } {
    const monitoring = this.#monitors.get(id);

    if (monitoring === undefined) {
      const ended =
        this.#monitorsEnded.get(id) ?? this.#monitorsPast.ended.get(id);

      return {
        error:
          ended !== undefined
            ? `${id} already ended: ${ended}`
            : this.#monitorsPast.left.some((left) => left.id === id)
              ? `${id} was running when this session was left and was not ` +
                'restarted; monitor starts another'
              : `No running monitor ${id} of yours; list_monitors names them`,
      };
    }

    const { info, running } = monitoring.run;

    this.#monitors.delete(id);

    if (by === 'agent') {
      this.#monitorsEnded.set(id, 'stopped');
    } else {
      this.#ending.set(id, monitoring);
    }

    this.#endedMonitor(running, { kind: 'stopped' });

    this.#showMonitors();
    this.#stopping(monitoring.run, by);

    return {
      id,
      description: info.description,
      events: running.events,
      ran_ms: this.#now() - info.startedAt,
    };
  }

  /** The session's monitors still running, in start order. */
  get monitors(): readonly RunningMonitor[] {
    return [...this.#monitors.values()].map(({ run }) => run.running);
  }

  #stopping(run: MonitorRun, by: 'agent' | 'person' | 'close'): void {
    run.stop(by);

    const gone = run.ended;

    this.#monitorsStopping.add(gone);
    void gone.then(() => this.#monitorsStopping.delete(gone));
  }

  /** Stops every monitor without a word; settles once all are gone. */
  #stopMonitors(): Promise<void> {
    const runs = [...this.#monitors.values()].map(({ run }) => run);

    this.#monitors.clear();
    this.#ending.clear();

    for (const run of runs) {
      this.#stopping(run, 'close');
    }

    if (runs.length > 0) {
      this.#showMonitors();
    }

    return Promise.all([...this.#monitorsStopping]).then(() => undefined);
  }

  #showMonitors(): void {
    this.#show({
      type: 'monitors',
      monitors: this.monitors,
      ended: this.#endedMonitors,
    });
  }

  /** Keeps `monitor`'s end for the window, once: a stop's comes first. */
  #endedMonitor(monitor: RunningMonitor, end: MonitorEnd): void {
    if (this.#endedMonitors.some((ended) => ended.id === monitor.id)) {
      return;
    }

    this.#endedMonitors = [
      ...this.#endedMonitors,
      { ...monitor, end, endedAt: this.#now() },
    ];
  }

  /** `run`'s place in `among`, if it still has one there under its id. */
  #monitoring(
    info: MonitorInfo,
    run: unknown,
    among: ReadonlyMap<string, Monitoring>,
  ): Monitoring | undefined {
    const monitoring = among.get(info.id);

    return monitoring?.run === run ? monitoring : undefined;
  }

  /**
   * A batch of a monitor's lines: into its message still queued, if one is,
   * so a busy log never fills the queue, or else a message of its own.
   */
  #monitorEvent(info: MonitorInfo, run: unknown, lines: EventLines): void {
    const monitoring = this.#monitoring(info, run, this.#monitors);

    if (monitoring === undefined) {
      return;
    }

    const from: MessageFrom = {
      name: info.description,
      monitor: { id: info.id },
    };
    const queued = monitoring.queued;

    if (queued !== undefined) {
      const merged = withLines(queued.lines, lines.lines, lines.dropped);

      if (this.#requeue(queued.turnId, from, eventText(merged))) {
        queued.lines = merged;

        this.#showMonitors();

        return;
      }
    }

    const message = this.#message(from, eventText(lines));

    monitoring.queued =
      message?.delivery === 'queued'
        ? { turnId: message.turnId, lines }
        : undefined;

    this.#showMonitors();
  }

  /**
   * A monitor's end, told to its agent: the lines not handed on yet, its
   * message still queued included, then chord's sentence, as one message.
   */
  #monitorEnded(
    info: MonitorInfo,
    run: unknown,
    end: MonitorEnd,
    rest: EventLines,
  ): void {
    const monitoring =
      this.#monitoring(info, run, this.#monitors) ??
      this.#monitoring(info, run, this.#ending);

    if (monitoring === undefined) {
      return;
    }

    this.#monitors.delete(info.id);
    this.#ending.delete(info.id);
    this.#monitorsEnded.set(info.id, endWord(end));
    this.#endedMonitor(monitoring.run.running, end);
    this.#showMonitors();

    const from: MessageFrom = {
      name: info.description,
      monitor: { id: info.id, end },
    };
    const sentence = endSentence(end, this.#now() - info.startedAt);
    const queued = monitoring.queued;

    if (
      queued !== undefined &&
      this.#requeue(
        queued.turnId,
        from,
        eventText(withLines(queued.lines, rest.lines, rest.dropped), sentence),
      )
    ) {
      return;
    }

    this.#message(from, eventText(rest, sentence));
  }

  #enqueue(session: Session, next: Prompt): Delivery {
    if (this.#idle() && this.#queued.length === 0 && !this.#waitsBetween()) {
      void this.#play(session, next);

      return 'sent';
    }

    this.#hold(next);

    return 'queued';
  }

  /**
   * Puts a prompt at the end of the queue, which shows it: with no turn
   * running, behind a request between turns, it says it waits for the
   * answer, as no turn starts while one waits (CHD-158).
   */
  #hold(next: Prompt): void {
    const held =
      !this.#turn && this.#waitsBetween()
        ? { ...next, afterAnswer: true as const }
        : next;

    this.#queued.push(held);
    this.#emit({
      type: 'queued',
      turnId: next.turnId,
      text: next.text,
      ...(next.from === undefined ? {} : { from: next.from }),
      ...(held.afterAnswer ? { afterAnswer: true } : {}),
    });
  }

  /**
   * Whether nothing holds the queue back: no turn, no wait for one's
   * trailing updates, no steer the agent has not answered.
   */
  #idle(): boolean {
    return !this.#turn && !this.#settling && this.#steers.size === 0;
  }

  /**
   * Sends the next queued prompt, if nothing holds the queue back: no turn
   * starts while a request asked between turns waits on the person, which
   * the turn would take off the screen while the agent still waits on it
   * (CHD-158).
   */
  async #advance(session: Session): Promise<void> {
    const queued =
      this.#current(session) && this.#idle() && !this.#waitsBetween()
        ? this.#queued.shift()
        : undefined;

    if (queued) {
      await this.#play(session, queued);
    }
  }

  /**
   * One of chord's tools served to the session: the call that asked for it
   * is drawn by it.
   */
  served(call: ChordCall): void {
    if (this.#session && !this.#closing) {
      this.#servedNow.push(call);
      this.#emit({ type: 'served', turnId: this.#stamp(), call });
    }
  }

  /**
   * A call served to a task's session after the task ended: kept in its
   * record, which its parent resumed reads the task's work from; its
   * parent's `endedTaskServed` draws it.
   */
  servedEnded(call: ChordCall): void {
    this.#recording?.heard({ type: 'served', turnId: this.#stamp(), call });
  }

  /**
   * Where a call served to task `id` after it ended goes: its block, drawn
   * while the session the task ran in is still the one here.
   */
  endedTaskServed(id: string): (call: ChordCall) => void {
    const session = this.#session;

    return (call) => {
      if (this.#session === session && !this.#closing) {
        this.#show({
          type: 'served',
          turnId: this.#stamp(),
          call,
          subagentId: id,
        });
      }
    };
  }

  /** The person's `/team run` started a run of the session's, as `call`. */
  ranTyped(call: ChordCall): void {
    if (this.#session && !this.#closing) {
      this.#emit({ type: 'run_typed', turnId: this.#stamp(), call });
    }
  }

  /** A long-lived agent of the session's, `id`, was closed. */
  agentClosed(id: string): void {
    if (this.#session && !this.#closing) {
      this.#emit({ type: 'agent_closed', id });
    }
  }

  /** The turn an event that came outside any is folded under. */
  #stamp(): string {
    return this.#selfTurnId ?? this.#turn?.id ?? this.#lastTurnId;
  }

  /**
   * Starts a task agent for the session on `session`, which reports to the
   * task; it runs until its first turn ends, or the session's turn is
   * interrupted, or the session closes.
   */
  adopt(task: TaskAgent, session: TaskSession): void {
    this.#tasks.set(task.id, task);
    task.begin(session);
  }

  /** A task agent of the session's, by its id, until it has ended. */
  task(id: string): TaskAgent | undefined {
    return this.#tasks.get(id);
  }

  /** The task agents of the session still running. */
  get runningTasks(): number {
    return [...this.#tasks.values()].filter((task) => task.running).length;
  }

  /**
   * What task agent `id` of this session does to it. Each call is dropped
   * once the task is no longer the session's, as after a `/clear`, so an old
   * task reaches nothing in the session that replaced its parent.
   */
  taskParent(id: string): TaskParent {
    const own = () => this.#tasks.get(id);

    return {
      relay: (event) => {
        const task = own();

        if (task) {
          this.#relay(event, task);
        }
      },
      deliver: (from, text) => {
        if (own()) {
          void this.deliver(from, text);
        }
      },
      ahead: (from, text) => {
        if (own()) {
          this.#ahead.push(wrapMessage(from, text));
        }
      },
      ended: () => {
        const task = own();

        if (!task) {
          return;
        }

        this.#forget(task);

        const closing = task.close().catch(() => {});

        this.#endedTasks.add(closing);
        void closing.then(() => this.#endedTasks.delete(closing));
      },
    };
  }

  /** Lets a task go, and the requests of its still on screen. */
  #forget(task: TaskAgent): void {
    let released = false;

    for (const [request, asker] of this.#foreign) {
      if (asker === task) {
        this.#foreign.delete(request);

        released = this.#foreignBetween.delete(request) || released;
      }
    }

    this.#tasks.delete(task.id);

    if (released) {
      this.#release();
    }
  }

  /** A task agent's event, in the session's stream, under its turn. */
  #relay(event: ConversationEvent, task: TaskAgent): void {
    if (!this.#session || this.#closing) {
      return;
    }

    const turnId = this.#stamp();
    let released = false;

    switch (event.type) {
      // The task answers it, whichever of its own subagents asked; one
      // asked with no turn of the session's running holds the queue as the
      // session's own would (CHD-158).
      case 'permission_requested':
      case 'elicitation_requested': {
        const id =
          event.type === 'permission_requested'
            ? event.permission.id
            : event.elicitation.id;

        this.#foreign.set(id, task);

        if (!this.#turn) {
          this.#foreignBetween.add(id);
          this.#holdForAnswer();
        }

        break;
      }
      case 'permission_settled':
      case 'elicitation_settled':
        this.#foreign.delete(event.id);

        released = this.#foreignBetween.delete(event.id);

        break;
    }

    const stamped =
      'turnId' in event ? ({ ...event, turnId } as typeof event) : event;

    // The task's work is kept in its own record, which the parent resumed
    // reads it from; the parent's keeps the block's start and end.
    if (
      (stamped.type === 'update' || stamped.type === 'served') &&
      stamped.subagentId !== undefined
    ) {
      this.#show(stamped);
    } else {
      this.#emit(stamped);
    }

    // Once its answer is on screen, what waited for it goes.
    if (released) {
      this.#release();
    }
  }

  /**
   * Cancels the turn in flight, if there is one, and takes back every prompt
   * queued behind it, which never reaches the agent: an interrupt stops the
   * work asked for, and the queued prompts go back to the person, as in
   * Claude Code. Messages queued behind it are not the person's to take:
   * they go once the turn has ended, as after any turn.
   */
  interrupt(): void {
    if (this.#closing) {
      return;
    }

    // Before the running turn's cancel, so its end does not start the next.
    // Messages stay, and go once the turn has ended, as after any turn.
    const withdrawn = this.#queued.filter((queued) => !queued.from);

    this.#queued = this.#queued.filter((queued) => queued.from);

    if (withdrawn.length > 0) {
      this.#emit({ type: 'queue_withdrawn' });
    }

    // The turn's work is stopped, its task agents' with it.
    for (const task of this.#tasks.values()) {
      task.cancel();
    }

    const turn = this.#turn;

    // Before the asks are withdrawn, which would let held messages into the
    // turn being stopped; they go once it has ended, as any message left.
    if (turn) {
      this.#sealed = turn.id;
    }

    this.#unhold();
    this.#withdrawAsks();

    // The turn has answered and is only waiting out its trailing updates;
    // with the queue taken back, nothing is left to wait for or cancel. A
    // message left still waits them out, so they fold under their own turn.
    if (!turn || this.#settling) {
      if (this.#queued.length === 0) {
        this.#settling?.abort();
      }

      return;
    }

    this.#emit({ type: 'cancel', turnId: turn.id, at: this.#now() });
    turn.turn.cancel().catch(() => {
      // The turn may settle before the cancel lands; its result says so.
    });
  }

  /** Answers a permission request with one of its options. */
  choose(id: string, optionId: string): void {
    const task = this.#foreign.get(id);

    if (task) {
      return task.choose(id, optionId);
    }

    this.#settle(id, { type: 'chosen', optionId })?.resolve(optionId);
    this.#release();
  }

  /** Rejects a permission request, as Esc does; the turn goes on. */
  reject(id: string): void {
    const task = this.#foreign.get(id);

    if (task) {
      return task.reject(id);
    }

    this.#settle(id, { type: 'rejected' })?.reject();
    this.#release();
  }

  /**
   * Asks the person a question of chord's own in the permission box, as
   * `propose_team`'s save box is, during the turn: the option picked, by its
   * id, Esc picking the `reject_once` one; or undefined once it is
   * withdrawn, by `signal`, the turn's end, an interrupt or the close, and
   * at once with no turn to ask in.
   */
  ask(
    wait: Omit<PermissionWait, 'id'>,
    signal: AbortSignal,
  ): Promise<string | undefined> {
    const session = this.#session;
    const turn = this.#turn;

    if (!session || !turn || this.#closing || signal.aborted) {
      return Promise.resolve(undefined);
    }

    return new Promise((settle) => {
      const id = crypto.randomUUID();
      let answered = false;
      const finish = (optionId: string | undefined) => {
        if (answered) {
          return;
        }

        answered = true;

        this.#asks.delete(withdraw);
        signal.removeEventListener('abort', withdraw);
        settle(optionId);
      };

      const withdraw = () => {
        if (this.#permissions.delete(id)) {
          this.#emit({
            type: 'permission_settled',
            turnId: turn.id,
            id,
            answer: { type: 'withdrawn' },
          });
        }

        finish(undefined);
        this.#release();
      };

      const request: PendingPermission = {
        id,
        sessionId: session.id,
        toolCall: { toolCallId: wait.toolCallId ?? id },
        options: wait.options,
        signal,
        resolve: finish,
        reject: () =>
          finish(
            wait.options.find((option) => option.kind === 'reject_once')
              ?.optionId,
          ),
      };

      this.#permissions.set(id, { request, turnId: turn.id });
      this.#asks.add(withdraw);
      signal.addEventListener('abort', withdraw, { once: true });
      this.#emit({
        type: 'permission_requested',
        turnId: turn.id,
        permission: { ...wait, id },
      });
    });
  }

  #withdrawAsks(): void {
    for (const withdraw of [...this.#asks]) {
      withdraw();
    }
  }

  /**
   * Answers a form or link: `accept` with the values, `decline`, or `cancel`
   * (Esc). The turn goes on; the agent decides what each means.
   */
  answer(id: string, response: ElicitationReply): void {
    const task = this.#foreign.get(id);

    if (task) {
      return task.answer(id, response);
    }

    const asked = this.#elicitations.get(id);

    if (!asked) {
      return;
    }

    this.#elicitations.delete(id);
    this.#emit({
      type: 'elicitation_settled',
      turnId: asked.turnId,
      id,
      answer: answerOf(response),
    });
    asked.request.answer(response);
    this.#release();
  }

  /**
   * Asks the agent for a mode. Nothing on screen changes until the agent
   * reports the mode it is in; a refusal goes into the transcript.
   */
  setMode(id: string): void {
    const session = this.#session;

    if (!session || this.#closing) {
      return;
    }

    this.#emit({ type: 'mode_asked', id });

    this.#modeChanges = this.#modeChanges.then(async () => {
      let answered = true;

      try {
        await session.setMode(id);
      } catch (error) {
        answered = false;

        if (this.#current(session)) {
          this.#emit({
            type: 'failed',
            turnId: `mode-${++this.#failures}`,
            message: `Could not switch to ${id} mode: ${messageOf(error)}`,
          });
        }
      }

      // An answer is news even when it reads as before; a refusal moved
      // nothing.
      this.#report(session, answered);

      if (this.#current(session)) {
        this.#emit({ type: 'mode_answered', id });
      }
    });
  }

  /**
   * Asks the agent for a model. The status line moves once the agent reports
   * the model it uses; a refusal goes into the transcript.
   */
  setModel(id: string): void {
    const session = this.#session;

    if (!session || this.#closing) {
      return;
    }

    this.#modelChanges = this.#modelChanges.then(async () => {
      try {
        await session.setModel(id);
      } catch (error) {
        if (this.#current(session)) {
          this.#emit({
            type: 'failed',
            turnId: `model-${++this.#failures}`,
            message: `Could not switch to ${id}: ${messageOf(error)}`,
          });
        }
      }

      this.#report(session);
    });
  }

  /**
   * Asks the agent to set config option `id` to `value`, as `/config` does.
   * Once it answers, the value it reports goes into the transcript as a note
   * under `/config`; a refusal goes in the same way, as a failed one.
   */
  setOption(id: string, value: string): void {
    const session = this.#session;

    if (!session || this.#closing) {
      return;
    }

    this.#optionChanges = this.#optionChanges.then(async () => {
      const asked = this.#options.find((option) => option.id === id);

      try {
        await session.setOption(id, value);
      } catch (error) {
        if (this.#current(session)) {
          this.#emit({
            type: 'noted',
            turnId: `option-${crypto.randomUUID()}`,
            command: 'config',
            text: `Could not set ${asked?.name ?? id} to ${
              asked ? valueName(asked, value) : value
            }: ${messageOf(error)}`,
            failed: true,
          });
        }

        return;
      }

      this.#report(session);

      const option = this.#options.find((candidate) => candidate.id === id);

      if (this.#current(session) && option) {
        this.#emit({
          type: 'noted',
          turnId: `option-${crypto.randomUUID()}`,
          command: 'config',
          text: `${option.name} set to ${valueName(option, option.current)}`,
          failed: false,
        });
      }
    });
  }

  /**
   * Stops the agent, waiting for a session still starting; resolves once its
   * process has exited.
   */
  close(): Promise<void> {
    if (this.#closing) {
      return this.#closing;
    }

    this.#emit({ type: 'closing' });
    this.#settling?.abort();
    this.#rouse();

    for (const stop of this.#stops) {
      stop.abort(new Error('chord closed the session while it started'));
    }

    // Its task agents go with it, and its monitors, without a word.
    const tasks = [
      ...[...this.#tasks.values()].map((task) => task.close().catch(() => {})),
      ...this.#endedTasks,
      this.#stopMonitors(),
    ];

    this.#tasks.clear();
    this.#foreign.clear();

    this.#closing = (async () => {
      const [session, ...retired] = await Promise.all([
        this.#opening,
        ...this.#retiring,
        ...tasks,
      ]);

      await session?.close();
      await this.#recording?.flushed();

      const failure = retired.find((error) => error !== undefined);

      if (failure !== undefined) {
        throw failure;
      }
    })();

    // Once closing, so no message held for an answer goes in as they go.
    this.#withdrawAsks();

    return this.#closing;
  }

  /**
   * Reports what of the agent's models, modes, options and commands moved
   * since the last report; the modes even when they did not, if `fresh`.
   */
  #report(session: Session, fresh = false): void {
    if (!this.#current(session)) {
      return;
    }

    const models = session.models();
    const modes = session.modes();
    const options = session.options();
    const commands = session.commands();

    if (!sameModels(models, this.#models)) {
      this.#models = models;

      this.#emit({ type: 'model', models });
    }

    if (fresh || !sameModes(modes, this.#modes)) {
      this.#modes = modes;

      this.#emit({ type: 'modes', modes });
    }

    if (!sameOptions(options, this.#options)) {
      this.#options = options;

      this.#emit({ type: 'options', options });
    }

    if (!sameCommands(commands, this.#commands)) {
      this.#commands = commands;

      this.#emit({ type: 'commands', commands });
    }
  }

  /**
   * Readies a session that has started: asks for the starting model, effort
   * and mode,
   * reports what the agent offers, plays a resumed session's past, starts
   * hearing its updates, and reports `connected`.
   */
  async #setUp(session: Session): Promise<void> {
    session.permissions.subscribe((request) => this.#asked(session, request));
    session.elicitations.subscribe((request) =>
      this.#elicited(session, request),
    );

    // The window's alone: the record knows what it was opened from.
    if (session.resumed !== undefined) {
      const { lastUsedAt, prompt, name } = session.resumed;

      this.#show({
        type: 'resumed',
        ...(lastUsedAt === undefined ? {} : { lastUsedAt }),
        ...(prompt === undefined ? {} : { prompt }),
        ...(name === undefined ? {} : { name }),
      });
    }

    // Before the modes and models are reported, so the session is first
    // shown as it starts rather than as the agent's defaults.
    await this.#applyStarting(session);

    if (!this.#current(session)) {
      return;
    }

    // The model goes out even when there is none, so the interface knows
    // it has heard.
    this.#models = session.models();

    this.#emit({ type: 'model', models: this.#models });

    // Before `connected`, so a resumed session's past is on screen before a
    // prompt can follow it.
    const past = session.history();

    for (const action of past) {
      this.#emit(action);
    }

    // Ids go on from the past's, which `stop_monitor` refuses by how they
    // ended.
    this.#monitorsPast = monitorsPast(past);

    // After the past, whose mode and commands were the agent's then, so what
    // shows is what the session is on now; before `connected`, so shift+tab
    // has the modes to walk as soon as the session is up.
    this.#report(session, true);

    // After the past, which the record holds already or takes from the
    // session, and before any update it has not heard.
    this.#recording?.opened(session);
    session.subscribe((update, subagentId) =>
      this.#updated(session, update, subagentId),
    );
    // An agent that goes on its own takes its subagents with it; a close or
    // a `/clear` is not news.
    void session.exited.then(() => {
      if (this.#current(session)) {
        // Nobody is left to hear them.
        void this.#stopMonitors();
        this.#emit({
          type: 'disconnected',
          turnId: this.#stamp(),
          at: this.#now(),
        });
      }
    });

    this.#emit({ type: 'prompt_capabilities', image: session.takesImages() });
    this.#emit({ type: 'connected', sessionId: session.id, at: this.#now() });
  }

  /**
   * Asks for the starting model, effort and mode. A refusal goes into the
   * transcript with where the value was set, and the session goes on with
   * what the agent chose; a required value's refusal fails the session's
   * start, which an effort's never does.
   */
  async #applyStarting(session: Session): Promise<void> {
    const { model, mode, effort } = this.#starting;

    this.#effortRefused = undefined;

    const asks: StartingAsk[] = [
      ...(model === undefined
        ? []
        : [
            {
              value: model,
              what: `on ${model.id}`,
              kind: 'models',
              offered: () => Promise.resolve(session.models()?.available),
              ask: () => session.setModel(model.id),
            },
          ]),
      ...(effort === undefined
        ? []
        : [
            {
              value: { ...effort, required: false },
              what: `on ${effort.id} effort`,
              kind: 'efforts',
              listedOnly: true,
              offered: () => Promise.resolve(session.efforts()?.available),
              ask: () => session.setEffort(effort.id),
            },
          ]),
      ...(mode === undefined
        ? []
        : [
            {
              value: mode,
              what: `in ${mode.id} mode`,
              kind: 'modes',
              listedOnly: true,
              offered: () => Promise.resolve(session.modes()?.available),
              ask: () => session.setMode(mode.id),
            },
          ]),
    ];

    for (const ask of asks) {
      const refused = await askStarting(ask);

      if (refused !== undefined && ask.value.required) {
        throw new Error(`Could not ${refused}`);
      }

      if (refused !== undefined && ask.kind === 'efforts') {
        this.#effortRefused = `Could not ${refused}`;
      }

      if (refused !== undefined && this.#current(session)) {
        this.#emit({
          type: 'failed',
          turnId: `starting-${++this.#failures}`,
          message: `Could not ${refused}`,
        });
      }
    }
  }

  /**
   * One of the agent's updates, or one of its subagents', folded under the
   * turn on screen, or the last one when it came after its answer or outside
   * any turn.
   */
  #updated(
    session: Session,
    update: SessionUpdate,
    subagentId: string | undefined,
  ): void {
    if (!this.#current(session)) {
      return;
    }

    this.#heardAt = performance.now();

    if (subagentId === undefined) {
      this.#track(session, update);
    }

    this.#emit({
      type: 'update',
      turnId: this.#stamp(),
      update,
      ...(subagentId === undefined ? {} : { subagentId }),
      ...(TIMED_UPDATES.has(update.sessionUpdate) ? { at: this.#now() } : {}),
    });

    if (subagentId === undefined && STATE_UPDATES.has(update.sessionUpdate)) {
      this.#report(session);
    }
  }

  /**
   * Keeps the turn's open calls as its updates say; each one ending wakes
   * the steers held behind it.
   */
  #track(session: Session, update: SessionUpdate): void {
    if (
      update.sessionUpdate !== 'tool_call' &&
      update.sessionUpdate !== 'tool_call_update'
    ) {
      return;
    }

    if (this.#turn !== undefined) {
      this.#calls = mergeToolCall(this.#calls, this.#turn.id, update);

      if (!this.#madeAt.has(update.toolCallId)) {
        this.#madeAt.set(update.toolCallId, this.#made++);
      }
    }

    if (update.status === 'failed') {
      this.#cutOff(session, update.toolCallId);
    }

    if (update.status === 'completed' || update.status === 'failed') {
      if (this.#openCalls.delete(update.toolCallId)) {
        this.#rouse();
      }
    } else if (
      this.#turn !== undefined &&
      (update.sessionUpdate === 'tool_call' || update.status !== undefined)
    ) {
      // An adapter may name a call first in an update, as Codex's can.
      this.#openCalls.add(update.toolCallId);
    }
  }

  /**
   * Keeps call `id` for the note ahead of the next turn when it is one of
   * chord's that the agent cut off and chord served nothing for: it never
   * reached chord. Only in a turn running now, so a past one a load replays
   * is never told again.
   */
  #cutOff(session: Session, id: string): void {
    const entry = this.#calls.entries.findLast(
      (each) => each.kind === 'tool' && each.call.id === id,
    );

    if (
      this.#turn === undefined ||
      entry?.kind !== 'tool' ||
      !entry.call.cut ||
      this.#cut.some((cut) => cut.id === id)
    ) {
      return;
    }

    const { call } = entry;
    const chord = chordCallOf(call, session.chordServer?.name);

    // Served is that tool with those arguments: another tool chord served
    // the same arguments for is not this call.
    if (
      chord !== undefined &&
      !this.#servedNow.some(
        (served) => served.tool === chord.tool && servedFor(call, served),
      )
    ) {
      this.#cut.push({
        id,
        made: this.#madeAt.get(id) ?? this.#made++,
        call: chord,
      });
    }
  }

  /**
   * Whether `session` is the one on screen: not let go by `clear`, and not
   * closing. What an older one reports is not news.
   */
  #current(session: Session): boolean {
    return this.#session === session && this.#closing === undefined;
  }

  #asked(session: Session, request: PendingPermission): void {
    // One from a session `clear` let go has nothing on screen to hang off.
    if (!this.#current(session)) {
      return request.reject();
    }

    // One with no turn running, from work that outlived its turn, waits on
    // the person as one in a turn does, under the last turn (CHD-158).
    const between = this.#turn === undefined;
    const turnId = this.#stamp();
    const withdrawn = () => {
      if (this.#permissions.delete(request.id)) {
        this.#emit({
          type: 'permission_settled',
          turnId,
          id: request.id,
          answer: { type: 'withdrawn' },
        });
        this.#release();
      }
    };

    this.#permissions.set(request.id, {
      request,
      turnId,
      ...(between && { between }),
    });

    if (between) {
      this.#holdForAnswer();
    }

    this.#emit({
      type: 'permission_requested',
      turnId,
      permission: waitFor(request, session.id),
      ...(between && { at: this.#now(), between }),
    });
    request.signal.addEventListener('abort', withdrawn, { once: true });

    if (request.signal.aborted) {
      withdrawn();
    }
  }

  #elicited(session: Session, request: PendingElicitation): void {
    // As with a permission: nothing on screen to hang it off.
    if (!this.#current(session)) {
      return request.answer({ action: 'cancel' });
    }

    const { id } = request;
    const between = this.#turn === undefined;
    const asker =
      request.sessionId !== undefined && request.sessionId !== session.id
        ? request.sessionId
        : undefined;
    const turnId = this.#stamp();
    const askedAt = this.#now();
    const withdrawn = () => {
      if (this.#elicitations.delete(id)) {
        this.#emit({
          type: 'elicitation_settled',
          turnId,
          id,
          answer: ranOut(request.wait, this.#now() - askedAt)
            ? { type: 'timed_out' }
            : { type: 'withdrawn' },
        });
        this.#release();
      }
    };

    this.#elicitations.set(id, {
      request,
      turnId,
      ...(between && { between }),
    });

    if (between) {
      this.#holdForAnswer();
    }

    this.#emit({
      type: 'elicitation_requested',
      turnId,
      elicitation: {
        ...request.wait,
        at: askedAt,
        ...(between && { between }),
        ...(between && asker !== undefined && { asker }),
      },
    });
    request.signal.addEventListener('abort', withdrawn, { once: true });

    if (request.signal.aborted) {
      withdrawn();
    }
  }

  /**
   * Waits for the agent to go quiet after an answer before the turn ends on
   * screen and the next queued prompt is sent: some agents send their last chunks or usage after
   * answering, and the transport cannot tell those from the next turn's once
   * it is sent. As acpx did, quiet is a second without an update, given up on
   * after five.
   */
  async #quieten(session: Session): Promise<void> {
    const settling = new AbortController();
    const giveUp = performance.now() + SETTLE_LIMIT_MS;

    this.#settling = settling;
    this.#heardAt = Math.max(this.#heardAt, performance.now());

    try {
      while (this.#current(session)) {
        const now = performance.now();
        const wait = Math.min(this.#heardAt + QUIET_MS, giveUp) - now;

        if (wait <= 0) {
          break;
        }

        await delay(wait, undefined, { signal: settling.signal });
      }
    } catch {
      // Aborted: the session is closing or let go, or the queue taken back.
    } finally {
      if (this.#settling === settling) {
        this.#settling = undefined;
      }
    }
  }

  /** Takes a request off the screen and hands it back to be answered. */
  #settle(id: string, answer: PermissionAnswer): PendingPermission | undefined {
    const asked = this.#permissions.get(id);

    if (!asked) {
      return undefined;
    }

    this.#permissions.delete(id);
    this.#emit({
      type: 'permission_settled',
      turnId: asked.turnId,
      id,
      answer,
    });

    return asked.request;
  }

  /**
   * Puts a prompt on screen and sends it, then the next one queued, once the
   * agent has answered; a turn in a session `clear` let go ends unseen, as
   * the transcript it belonged to is gone.
   */
  async #play(session: Session, next: Prompt): Promise<void> {
    const { turnId } = next;
    const emit = (event: ConversationEvent) =>
      this.#session === session && this.#emit(event);

    const at = this.#now();

    emit({
      type: 'prompt',
      turnId,
      text: next.text,
      at,
      ...(next.from === undefined ? {} : { from: next.from }),
      ...(next.team === undefined ? {} : { team: next.team }),
    });

    let result: TurnResult;
    let went = false;

    // chord's note of the calls cut off since the last turn goes ahead of
    // whatever starts this one, a message or the person's prompt.
    const cut = this.#cut.splice(0).sort((a, b) => a.made - b.made);
    const prompt =
      cut.length === 0
        ? next.prompt
        : [
            wrapMessage(
              { name: 'chord' },
              cutNote(cut.map((each) => each.call)),
            ),
            next.prompt,
          ].join('\n\n');

    try {
      const turn = session.prompt(prompt, next.attachments, next.mentions);

      this.#turn = { id: turnId, turn };
      this.#openCalls = new Set();
      this.#calls = emptyTranscript;
      this.#madeAt = new Map();
      this.#servedNow = [];
      this.#lastTurnId = turnId;
      this.#selfTurnId = undefined;

      // Recorded once it went, with the links found for it, before the
      // agent can answer: a prompt a cancel kept back never reached it.
      const links = await turn.sent;

      went = links !== undefined;

      if (went && this.#turn?.id === turnId) {
        this.#wentId = turnId;
      }

      if (links !== undefined && this.#session === session) {
        this.#recording?.sent(
          turnId,
          prompt,
          next.attachments.length,
          links,
          at,
          next.from,
        );
      }

      result = await turn.result;
    } catch (error) {
      result = { status: 'failed', error: { message: messageOf(error) } };
    }

    // A prompt a cancel kept back never took the note: the next one does,
    // in this session, never one `clear` started since.
    if (!went && cut.length > 0 && this.#session === session) {
      this.#cut = [...cut, ...this.#cut];
    }

    // The turn has answered: nothing goes into it any more, and a steer
    // waiting on the person's answer in it goes as the next turn.
    if (this.#current(session)) {
      this.#sealed = turnId;

      this.#unhold();
    }

    // The end of a turn whose prompt never went is the window's alone; in
    // the record it would end a turn that is not there.
    const ended = went
      ? emit
      : (event: ConversationEvent) =>
          this.#session === session && this.#show(event);

    // The turn stays on screen, still working, through the wait, so the
    // queued prompt reads as waiting behind it and Esc can still take it back.
    if (this.#queued.length > 0 && this.#current(session)) {
      await this.#quieten(session);
    }

    if (this.#turn?.id === turnId) {
      this.#turn = undefined;
    }

    // A question of chord's the turn ended under has nobody to answer.
    this.#withdrawAsks();
    ended({ type: 'result', turnId, result });

    if (result.status !== 'failed' && result.usage) {
      ended({ type: 'usage', turnId, usage: result.usage });
    }

    // A form the turn ended under no longer matters; the transcript has it
    // as cancelled already.
    for (const [id, asked] of this.#elicitations) {
      if (asked.turnId === turnId) {
        this.#elicitations.delete(id);
        asked.request.answer({ action: 'cancel' });
      }
    }

    await this.#advance(session);
  }
}

/** What the transcript keeps of a response to a form or link. */
function answerOf(response: ElicitationReply): ElicitationAnswer {
  switch (response.action) {
    case 'accept':
      return {
        type: 'accepted',
        ...(response.content ? { content: response.content } : {}),
      };
    case 'decline':
      return { type: 'declined' };
    case 'cancel':
      return { type: 'cancelled' };
  }
}

/**
 * How long before the countdown's end a withdrawal still reads as the
 * agent's wait running out. chord counts from when the request reached it,
 * later than the agent sent it by however long the way took, so its
 * countdown ends after the agent's; codex withdraws at its own end, with
 * no margin (the owner, 2026-10-17, CHD-413 Q10).
 */
export const RAN_OUT_TOLERANCE_MS = 1_000;

/**
 * Whether a request withdrawn after `waited` ms was withdrawn because the
 * wait its agent gave for an answer ran out, as codex's does: chord sees
 * only the withdrawal, so it reads one that came within
 * `RAN_OUT_TOLERANCE_MS` of the countdown's end, on its own clock, or
 * after it as that, and any earlier one as a cancel.
 */
export function ranOut(wait: ElicitationWait, waited: number): boolean {
  const expires =
    wait.mode === 'form' ? wait.questions?.expiresInMs : undefined;

  return expires !== undefined && waited >= expires - RAN_OUT_TOLERANCE_MS;
}

/** Whether two readings name the same commands, described the same way. */
function sameCommands(
  a: readonly AvailableCommand[],
  b: readonly AvailableCommand[],
): boolean {
  return (
    a.length === b.length &&
    a.every(
      (command, index) =>
        command.name === b[index]?.name &&
        command.description === b[index]?.description &&
        Boolean(command.input) === Boolean(b[index]?.input),
    )
  );
}
