/**
 * The transcript's shapes, which every module of the reducer and everything
 * that draws a transcript share, and the transcript a session starts with.
 */
import type {
  AvailableCommand,
  Cost,
  ElicitationContentValue,
  ElicitationSchema,
  PermissionOption,
  PlanEntry,
  SessionUpdate,
  ToolCallContent,
  ToolCallLocation,
  ToolKind,
} from '@agentclientprotocol/sdk';
import type { Questions } from '../questions.ts';
import type { OpenEscape, TerminalCursor } from '../terminal_text.ts';
import type { TokenUsage } from '../usage.ts';
import type { Team } from '../../teams.ts';

/** One tool call, merged from its `tool_call` and every update to it. */
export interface ToolCall {
  readonly id: string;
  /** The agent's latest title for it; none until it gave one. */
  readonly title?: string;
  readonly kind?: ToolKind;
  /** ACP's `pending`, `in_progress`, `completed` or `failed`. */
  readonly status?: string;
  readonly locations?: readonly ToolCallLocation[];
  /** Text, diffs (`path`, `oldText`, `newText`) and terminals, as ACP sends. */
  readonly content?: readonly ToolCallContent[];
  readonly rawInput?: unknown;
  readonly rawOutput?: unknown;
  /**
   * The terminals the call ran its commands in, in the order the agent first
   * named them, with what each wrote; none until it named one.
   */
  readonly terminals?: readonly Terminal[];
  /**
   * The request chord's own MCP server served for it, once the call is known
   * to be that one; its headline and lines are read from this, not the title.
   */
  readonly chord?: ChordCall;
}

/** The tools chord's own MCP server offers. */
export type ChordTool =
  | 'list_agents'
  | 'list_sessions'
  | 'spawn_task'
  | 'open_agent'
  | 'send_message'
  | 'close_agent'
  | 'monitor'
  | 'stop_monitor'
  | 'list_monitors'
  | 'list_teams'
  | 'run_team'
  | 'propose_team';

/**
 * A request chord's MCP server served: the tool, the arguments it was called
 * with, and its answer, or the refusal it gave. A task's id when it started
 * one.
 */
export interface ChordCall {
  readonly tool: ChordTool;
  readonly input: unknown;
  readonly answer?: unknown;
  /** chord's refusal, which the call reads as its failure. */
  readonly error?: string;
  /** The task agent `spawn_task` started, by the id it answered. */
  readonly task?: string;
  /** A message that waited behind its recipient's turn. */
  readonly queued?: boolean;
  /**
   * Served while the call still waits on the person, as `propose_team`'s
   * proposal is drawn while its save box is open; the answer served after
   * takes its place.
   */
  readonly pending?: true;
  /**
   * What a call served again shares with the one it takes the place of: a
   * proposal served pending and its answer, as two proposals of the same
   * team can wait at once and each answer is its own call's; a message
   * served sent and again once it went queued after all.
   */
  readonly asked?: string;
}

/**
 * The team part ahead of a team agent's first message: the team's name, the
 * member it is for, none for the lead, and chord's words and the file's, as
 * the agent got them inside `<team>`.
 */
export interface TeamPart {
  readonly team: string;
  readonly member?: string;
  readonly text: string;
}

/**
 * Who a message to the session came from, as its `←` row and its wrapper name
 * them: `← Fix the tokenizer · codex · report` on screen, and
 * `<message from="Fix the tokenizer · codex · report">` for the agent.
 */
export interface MessageFrom {
  /** A child's name, `main` for the parent, or `chord`. */
  readonly name: string;
  readonly runtime?: string;
  /** A task's report, or the error a failed task ended with. */
  readonly note?: 'report' | 'failed';
  /**
   * `send_message` reaches it by its name: `main`, or a long-lived child;
   * never a task, whose name is its title, or chord. Its rows draw `@name`.
   * Told by who sent it, never by the name alone, which a task's could
   * match; a record kept before this was matches it against the children
   * its own `open_agent` answers name and none its `spawn_task` answers do.
   */
  readonly reachable?: true;
  /**
   * A monitor's event, `name` its description: its id, and on the last one
   * how it ended, that message's last line being chord's sentence for it.
   */
  readonly monitor?: {
    readonly id: string;
    readonly end?: MonitorEnd;
  };
}

/**
 * How a monitor ended, where it tells its agent: its command exited, a
 * signal chord did not send killed it, its `timeout_ms` passed, the person
 * stopped it, or it printed too much.
 */
export type MonitorEnd =
  | { readonly kind: 'exit'; readonly code: number }
  | { readonly kind: 'signal'; readonly signal: string }
  | {
      readonly kind: 'timed_out';
      readonly timeoutMs: number;
    }
  | { readonly kind: 'stopped' }
  | { readonly kind: 'flooded'; readonly by: 'lines' | 'bytes' };

/** A task agent chord started for the session, as `spawn_task` asked. */
export interface TaskInfo {
  /** Its `name`, or failing that its prompt's first line. */
  readonly name: string;
  readonly runtime: string;
  /** The model asked for; none when the runtime's own was left. */
  readonly model?: string;
  /**
   * The effort it started on, when one was asked for; said once it is up,
   * as a refused one leaves it on the runtime's own.
   */
  readonly effort?: string;
  /**
   * Its own record, which keeps its work, had gone when its parent was
   * resumed: how much it did is not known.
   */
  readonly workLost?: boolean;
}

/**
 * A terminal an agent ran a command in, as the `_meta` of its tool call's
 * updates tells it: `terminal_info`, `terminal_output_delta`,
 * `terminal_output` and `terminal_exit`, keyed by `terminal_id`. chord runs no
 * terminals; the agent runs them and sends what they wrote.
 */
export interface Terminal {
  readonly id: string;
  /**
   * What it wrote, as a screen would leave it (`terminal_text.ts`): plain
   * text, its cursor controls applied and every other escape dropped. Only
   * the last `OUTPUT_LIMIT` characters, from a line's start.
   */
  readonly output: string;
  /** Where its next output lands, when not at the end of what it wrote. */
  readonly cursor?: TerminalCursor;
  /** The escape its output so far ends inside, which a later delta ends. */
  readonly escape?: OpenEscape;
  /** The directory it ran in, when the agent says. */
  readonly cwd?: string;
  /** `terminal_exit` came: the command is over. */
  readonly exited: boolean;
  /** Its exit code, once it exited with one. */
  readonly exitCode?: number;
  /** The signal that ended it, once one did, as plain as the output. */
  readonly signal?: string;
  /** Output ran past `OUTPUT_LIMIT` and its start was dropped. */
  readonly truncated?: boolean;
}

/**
 * A compaction of the session's context the agent ran, folded from its
 * `compaction_update`s and `compaction_summary_chunk`s by its id.
 */
export interface Compaction {
  readonly id: string;
  /** ACP's `in_progress`, `completed`, `failed` or `cancelled`. */
  readonly status: string;
  /**
   * The summary the agent kept of what it dropped, as text; streamed chunks
   * build it, an update's `summary` replaces it. Empty when it sent none, as
   * Codex's adapter never does.
   */
  readonly summary: string;
  /** Why it failed, in the agent's words. */
  readonly error?: string;
}

/**
 * A command run from the prompt's bash mode, and what it wrote. chord's own:
 * the agent hears of it only as context sent with the next prompt.
 */
export interface ShellRun {
  readonly command: string;
  /** As written, escapes and all, up to `OUTPUT_LIMIT` (`context.ts`). */
  readonly stdout: string;
  readonly stderr: string;
  readonly running: boolean;
  /** The exit code, once it exited on its own. */
  readonly code?: number;
  /** Esc stopped it. */
  readonly stopped?: boolean;
  /** Why the shell could not run it at all. */
  readonly error?: string;
  /** A stream ran past `OUTPUT_LIMIT` and the rest was dropped. */
  readonly truncated?: boolean;
}

/**
 * A line of what one of chord's own commands reports: a label and its value,
 * or a sentence alone.
 */
export interface ReportRow {
  /** Padded to the widest label in its report, so the values line up. */
  readonly label?: string;
  readonly text: string;
}

/**
 * How a subagent stands: at work, or ended, and how. `completed`, `failed`,
 * `cancelled` and `disconnected` are the adapters' words for an ending; ACP's
 * `idle` reads as `completed`, the work asked of it done.
 */
export type SubagentState =
  'running' | 'completed' | 'failed' | 'cancelled' | 'disconnected';

/**
 * A subagent: a session of its own the agent started for part of a turn, as
 * its `subagent_update`s describe it, with the work it did held apart from
 * its parent's, in the order it came. Times are chord's clock, epoch
 * milliseconds, when the updates that carried them reached chord; a past that
 * kept none has none.
 */
export interface Subagent {
  /** Its session's id, which its own updates and requests carry. */
  readonly id: string;
  /** The parent's short name for it. */
  readonly title?: string;
  /** What it was asked to do, in full, as the parent described it. */
  readonly description?: string;
  readonly state: SubagentState;
  /** When its first update came. */
  readonly startedAt?: number;
  /** When it ended, once it has. */
  readonly endedAt?: number;
  /**
   * Its own messages, thoughts, tool calls and subagents, as a transcript's
   * entries are, in the order they first appeared.
   */
  readonly entries: readonly Entry[];
  /** Its latest plan, which never stands for its parent's. */
  readonly plan: readonly PlanEntry[];
  /** The id a `plan_update` gave that plan. */
  readonly planId?: string;
  /** Where its plan first came: how many of `entries` were there then. */
  readonly planAt?: number;
  /** Set on a task agent chord started, which the agent's runtime did not. */
  readonly task?: TaskInfo;
  /**
   * The `spawn_task` call it stands in place of, whose own updates it takes
   * from then on.
   */
  readonly callId?: string;
}

/** One block in the transcript, in the order it first appeared. */
export type Entry =
  | { readonly kind: 'user'; readonly turnId: string; readonly text: string }
  | {
      /**
       * A message another agent, or chord, sent the session, which began this
       * turn as a prompt would; `text` is what was said, without its wrapper.
       */
      readonly kind: 'message';
      readonly turnId: string;
      readonly from: MessageFrom;
      readonly text: string;
    }
  | {
      readonly kind: 'assistant' | 'thought';
      readonly turnId: string;
      readonly text: string;
      /** The agent's message id, when it sends one; a new id starts a block. */
      readonly messageId?: string;
      /**
       * The plan a `plan_update` wrote as this reply; each update to it rewrites
       * it, so no chunk runs on into it.
       */
      readonly planId?: string;
    }
  | { readonly kind: 'tool'; readonly turnId: string; readonly call: ToolCall }
  | {
      readonly kind: 'compaction';
      readonly turnId: string;
      readonly compaction: Compaction;
    }
  | {
      /**
       * A subagent, where its first update came among its parent's entries;
       * each later update changes it here.
       */
      readonly kind: 'subagent';
      readonly turnId: string;
      readonly subagent: Subagent;
    }
  | {
      readonly kind: 'error';
      readonly turnId: string;
      readonly message: string;
      readonly code?: string;
    }
  | {
      /**
       * Something chord carries on past, such as a settings key it left out;
       * `turnId` is the warning's own id.
       */
      readonly kind: 'warning';
      readonly turnId: string;
      readonly message: string;
    }
  | { readonly kind: 'cancelled'; readonly turnId: string }
  | {
      /** How a permission request was answered; a withdrawn one leaves none. */
      readonly kind: 'permission';
      readonly turnId: string;
      /** The tool call's title, as the request named it. */
      readonly title?: string;
      /** The agent's option the person chose; none when Esc rejected it. */
      readonly option?: PermissionOption;
    }
  | {
      /**
       * How a form or link the agent asked for was answered. A request that
       * stopped mattering, as when its turn was cancelled, reads `cancelled`.
       */
      readonly kind: 'elicitation';
      readonly turnId: string;
      readonly wait: ElicitationWait;
      readonly outcome: ElicitationOutcome;
      /** What an accepted form sent, by field. */
      readonly content?: Readonly<Record<string, ElicitationContentValue>>;
    }
  | {
      /**
       * The plan as it stood when a turn finished it, kept in the transcript
       * once the live list above the prompt lets it go.
       */
      readonly kind: 'plan';
      readonly turnId: string;
      readonly entries: readonly PlanEntry[];
    }
  | {
      /** `turnId` is the run's own id; no turn asked for it. */
      readonly kind: 'shell';
      readonly turnId: string;
      readonly run: ShellRun;
    }
  | {
      /**
       * What one of chord's commands, such as `/cost`, reported as it ran; the
       * agent never hears of it. `turnId` is the report's own id.
       */
      readonly kind: 'report';
      readonly turnId: string;
      /** The command's name, without its `/`. */
      readonly command: string;
      readonly rows: readonly ReportRow[];
    }
  | {
      /**
       * One of chord's commands changed something in the session outside any
       * turn, such as a config option, or the agent refused it: one line under
       * the command as typed. `turnId` is the note's own id.
       */
      readonly kind: 'note';
      readonly turnId: string;
      /** The command's name, without its `/`. */
      readonly command: string;
      readonly text: string;
      readonly failed: boolean;
    }
  | {
      /** The turn ended on its own for a reason other than `end_turn`. */
      readonly kind: 'stopped';
      readonly turnId: string;
      readonly reason: string;
    }
  | {
      /**
       * The long-lived agents a resumed session had open when it was left,
       * which are not reopened with it; `turnId` is the note's own id.
       */
      readonly kind: 'left_open';
      readonly turnId: string;
      readonly agents: readonly LeftOpen[];
    }
  | {
      /**
       * A team's instructions, which went to a lead or member ahead of its
       * first message; drawn as one line, its text under ctrl+o.
       */
      readonly kind: 'team_part';
      readonly turnId: string;
      readonly part: TeamPart;
    }
  | {
      /**
       * What `/team` did, under the command as typed: a team shown, a run
       * started, or a line; `turnId` is the entry's own id.
       */
      readonly kind: 'team';
      readonly turnId: string;
      /** The command as typed, without its `/`: `team show bugfix`. */
      readonly command: string;
      readonly shown: TeamShown;
    }
  | {
      /**
       * The monitors a resumed session had running when it was left, which
       * are not restarted; `turnId` is the note's own id.
       */
      readonly kind: 'monitors_left';
      readonly turnId: string;
      readonly monitors: readonly PastMonitor[];
    }
  | {
      /**
       * The close of a turn the agent started on its own with a message
       * steered after chord's turn had ended, which chord cancelled; the
       * message, from `from`, goes as chord's next turn. It stays under what
       * that turn drew, and stands alone while the turn drew nothing.
       */
      readonly kind: 'self_started';
      readonly turnId: string;
      readonly from: MessageFrom;
      readonly alone: boolean;
    };

/** What one `/team` command left in the transcript. */
export type TeamShown =
  /** `/team`: the command as typed, while its picker is open. */
  | { readonly kind: 'listed' }
  | {
      /** `/team show`: the team as its file has it, and its run, if open. */
      readonly kind: 'show';
      readonly name: string;
      /** Its file, as the window shows paths. */
      readonly file: string;
      readonly team: Team;
      readonly running?: TeamRunShown;
    }
  | {
      /** `/team run`: the run started, drawn as `run_team`'s call is. */
      readonly kind: 'ran';
      readonly call: ChordCall;
    }
  | {
      /** A line under the command: what it did, or why it did not. */
      readonly kind: 'said';
      readonly text: string;
      readonly failed: boolean;
    };

/** A run of a team as `/team show` caught it: a snapshot, as `/status` is. */
export interface TeamRunShown {
  /** The run's name: `bugfix`, `bugfix 2`. */
  readonly name: string;
  /** When its lead opened, on chord's clock. */
  readonly since: number;
  /** When `/team show` caught it, which its times are counted to. */
  readonly at: number;
  readonly job: string;
  /** The lead, then each of the file's members, in the file's order. */
  readonly agents: readonly TeamAgentShown[];
}

/** One agent of a running team, as `/team show` caught it. */
export interface TeamAgentShown {
  /** `lead`, or the member's name. */
  readonly name: string;
  /** The team's lead: a member may be named `lead` too. */
  readonly lead?: true;
  /** Not opened yet, or closed again: it has no state. */
  readonly open: boolean;
  /** Its state as the agent list words it; none while idle and seen. */
  readonly state?: {
    readonly glyph: string;
    readonly words: string;
    readonly tone: 'warning' | 'error' | 'success' | 'dim';
  };
  /**
   * Its latest call's or incoming message's headline, as its transcript
   * draws it: `Edit(src/a.ts)`, `→ to @coder`, `← from @tester · claude`.
   */
  readonly latest?: string;
}

/** A monitor a resumed session's past started, by its id. */
export interface PastMonitor {
  readonly id: string;
  readonly description: string;
}

/** A long-lived agent left open, as its parent's record names it. */
export interface LeftOpen {
  readonly name: string;
  readonly runtime: string;
  /** A team run's lead's: its team's name, by its file. */
  readonly team?: string;
  /** A team run's: its lead and the members it had open. */
  readonly agents?: number;
}

/**
 * A permission request the turn is waiting on, with what the interface draws
 * to ask it.
 */
export interface PermissionWait {
  readonly id: string;
  /** The subagent that asks, when the session's own agent does not. */
  readonly subagentId?: string;
  readonly toolCallId?: string;
  readonly title?: string;
  readonly kind?: ToolKind;
  readonly locations?: readonly ToolCallLocation[];
  /** The call's arguments, kept only when the request has no content. */
  readonly rawInput?: unknown;
  /** The agent's own options, in the agent's order. */
  readonly options: readonly PermissionOption[];
  /**
   * chord's own question rather than the agent's: `propose_team`'s save box,
   * whose answer is drawn on the call, so it leaves no record of its own.
   */
  readonly save?: SaveBox;
}

/** `propose_team`'s save box: its question, and the file each choice writes. */
export interface SaveBox {
  /** `Save team bugfix?`, or `Replace team bugfix?`. */
  readonly question: string;
  /** The file each option writes, by its id, as the window shows paths. */
  readonly files: Readonly<Record<string, string>>;
  /** What Esc does: `tell claude what to change`. */
  readonly escape: string;
}

/**
 * How a permission request stopped waiting: an option chosen, rejected with
 * Esc, or withdrawn because the turn was cancelled or the session closed.
 */
export type PermissionAnswer =
  | { readonly type: 'chosen'; readonly optionId: string }
  | { readonly type: 'rejected' }
  | { readonly type: 'withdrawn' };

/**
 * A form or link the agent asks the person for, through ACP's
 * `elicitation/create`, with what the interface draws to ask it.
 */
export type ElicitationWait = {
  readonly id: string;
  readonly message: string;
  /** The tool call the request came out of, when the agent names one. */
  readonly toolCallId?: string;
  /** The task agent that asks, when the session's own agent does not. */
  readonly subagentId?: string;
} & (
  | {
      readonly mode: 'form';
      readonly schema: ElicitationSchema;
      /** The form's questions, where an enricher read the adapter's form. */
      readonly questions?: Questions;
    }
  | { readonly mode: 'url'; readonly url: string }
);

/** How an elicitation ended, as its record says it. */
export type ElicitationOutcome =
  'accepted' | 'declined' | 'cancelled' | 'timed_out';

/**
 * How an elicitation stopped waiting: answered, or withdrawn because its turn
 * ended or the session closed, which its record calls cancelled, or once
 * the wait its agent gave for an answer ran out (`timed_out`).
 */
export type ElicitationAnswer =
  | {
      readonly type: 'accepted';
      readonly content?: Readonly<Record<string, ElicitationContentValue>>;
    }
  | { readonly type: 'declined' }
  | { readonly type: 'cancelled' }
  | { readonly type: 'withdrawn' }
  | { readonly type: 'timed_out' };

/** What the turn in flight is doing; times are epoch milliseconds. */
export type TurnState =
  | { readonly status: 'idle' }
  | {
      readonly status: 'working';
      readonly turnId: string;
      readonly since: number;
    }
  | {
      readonly status: 'awaiting_permission';
      readonly turnId: string;
      readonly since: number;
      readonly permissions: readonly PermissionWait[];
      /**
       * Asked between turns, by a task agent that outlived the turn that
       * started it: the session is idle again once every request is answered.
       */
      readonly between?: true;
    }
  | {
      /** Cancel was asked for; the turn has not settled yet. */
      readonly status: 'cancelling';
      readonly turnId: string;
      readonly since: number;
      readonly cancelledAt: number;
    };

export interface Usage {
  /** Tokens in the context window now. */
  readonly used: number;
  /** The context window's size in tokens; 0 when nobody knows it. */
  readonly size: number;
  readonly cost?: Cost;
  /** Which of the three chord worked out itself, its estimates, not the agent's. */
  readonly estimated?: readonly UsageField[];
}

export type UsageField = 'used' | 'size' | 'cost';

/**
 * How a turn ended: the agent's answer to its prompt, with the turn's tokens
 * when it reported them, or why there was none.
 */
export type TurnResult =
  | {
      readonly status: 'completed' | 'cancelled';
      readonly stopReason: string;
      readonly usage?: TokenUsage;
    }
  | {
      readonly status: 'failed';
      readonly error: { readonly message: string; readonly code?: string };
    };

export interface Transcript {
  readonly entries: readonly Entry[];
  /** The latest plan; each plan update replaces it, `[]` clears it. */
  readonly plan: readonly PlanEntry[];
  /**
   * The id a `plan_update` gave the latest plan, so a `plan_removed` for
   * another plan leaves it; none when it came as an older `plan` update.
   */
  readonly planId?: string;
  readonly usage?: Usage;
  /**
   * The current mode's id, as the agent last reported it: in its mode config
   * option or by `current_mode_update`.
   */
  readonly mode?: string;
  readonly commands: readonly AvailableCommand[];
  readonly turn: TurnState;
  /**
   * Forms and links the turn in flight asks for, oldest first; the first is
   * on screen. Apart from the turn's status, as a permission may be asked
   * while one is open.
   */
  readonly asking: readonly ElicitationWait[];
  /**
   * Requests chord served whose tool call has not come yet, so the call is
   * tied to its request when it does.
   */
  readonly served?: readonly ChordCall[];
}

/**
 * What the reducer folds. `turnId` is the turn's own id; it keeps a late
 * update from an earlier turn out of the turn now in flight.
 */
export type TranscriptAction =
  | {
      readonly type: 'prompt';
      readonly turnId: string;
      readonly text: string;
      readonly at: number;
      /** Set when the prompt is a message from another agent, or chord. */
      readonly from?: MessageFrom;
      /** The team part that went ahead of the message. */
      readonly team?: TeamPart;
      /**
       * A message put into turn `into` as it ran, which starts no turn of
       * its own; `turnId` is still the message's own.
       */
      readonly into?: string;
    }
  /**
   * chord's MCP server served one of its tools to the session, or to the
   * subagent named, a task agent of its: the call that asked is drawn by it.
   */
  | {
      readonly type: 'served';
      readonly turnId: string;
      readonly call: ChordCall;
      readonly subagentId?: string;
    }
  /**
   * One of the agent's `session/update`s, as it sent it. `turnId` is the turn
   * on screen when it came, or the last one: an update may come after its
   * turn's answer, or outside any turn.
   */
  | {
      readonly type: 'update';
      readonly turnId: string;
      readonly update: SessionUpdate;
      /** The subagent whose session it came for; none for the session's own. */
      readonly subagentId?: string;
      /** When it reached chord, for the updates whose time is kept. */
      readonly at?: number;
    }
  | {
      readonly type: 'permission_requested';
      readonly turnId: string;
      readonly permission: PermissionWait;
      /** When it was asked, for a task agent's asked between turns. */
      readonly at?: number;
    }
  | {
      readonly type: 'permission_settled';
      readonly turnId: string;
      readonly id: string;
      readonly answer: PermissionAnswer;
    }
  | {
      readonly type: 'elicitation_requested';
      readonly turnId: string;
      readonly elicitation: ElicitationWait;
    }
  | {
      readonly type: 'elicitation_settled';
      readonly turnId: string;
      readonly id: string;
      readonly answer: ElicitationAnswer;
    }
  | { readonly type: 'cancel'; readonly turnId: string; readonly at: number }
  /**
   * The agent that ran the subagents is gone: its process exited, or the
   * session is a past reopened in another. `at` is when, if known.
   */
  | {
      readonly type: 'disconnected';
      readonly turnId: string;
      readonly at?: number;
    }
  | {
      /** The agent answered the turn's prompt, or the prompt failed. */
      readonly type: 'result';
      readonly turnId: string;
      readonly result: TurnResult;
    }
  /**
   * A bash-mode command started; `turnId` is the run's own, as no turn asked,
   * and stands for it from here on.
   */
  | {
      readonly type: 'shell_started';
      readonly turnId: string;
      readonly command: string;
    }
  | {
      readonly type: 'shell_output';
      readonly turnId: string;
      readonly stream: 'stdout' | 'stderr';
      readonly text: string;
    }
  | {
      readonly type: 'shell_ended';
      readonly turnId: string;
      readonly code?: number;
      readonly stopped?: boolean;
      readonly error?: string;
    }
  /** A run a resumed session's prompt carried, whole, as it was sent. */
  | {
      readonly type: 'shell_replayed';
      readonly turnId: string;
      readonly run: ShellRun;
    }
  /** One of chord's commands reported; `turnId` is the report's own id. */
  | {
      readonly type: 'reported';
      readonly turnId: string;
      readonly command: string;
      readonly rows: readonly ReportRow[];
    }
  /**
   * A change one of chord's commands made, or asked for and was refused,
   * outside any turn; `turnId` is the note's own id.
   */
  | {
      readonly type: 'noted';
      readonly turnId: string;
      readonly command: string;
      readonly text: string;
      readonly failed: boolean;
    }
  /** `/team` showed a team, started a run or said a line; see `TeamShown`. */
  | {
      readonly type: 'team_shown';
      readonly turnId: string;
      readonly command: string;
      readonly shown: TeamShown;
    }
  | {
      /**
       * Something asked of the agent outside any turn failed, such as a mode
       * change; `turnId` is one of its own, as no turn asked.
       */
      readonly type: 'failed';
      readonly turnId: string;
      readonly message: string;
    }
  /** Something went wrong that chord carries on past; `turnId` is its own. */
  | {
      readonly type: 'warned';
      readonly turnId: string;
      readonly message: string;
    }
  /**
   * A resumed session's long-lived agents that were open when it was left;
   * `turnId` is the note's own id.
   */
  | {
      readonly type: 'left_open';
      readonly turnId: string;
      readonly agents: readonly LeftOpen[];
    }
  /**
   * A resumed session's monitors that were running when it was left;
   * `turnId` is the note's own id.
   */
  | {
      readonly type: 'monitors_left';
      readonly turnId: string;
      readonly monitors: readonly PastMonitor[];
    }
  /**
   * chord cancelled turn `turnId`, which the agent started on its own with
   * a message from `from` that a steer brought after chord's turn had ended.
   */
  | {
      readonly type: 'self_started';
      readonly turnId: string;
      readonly from: MessageFrom;
    };

export const emptyTranscript: Transcript = {
  entries: [],
  plan: [],
  commands: [],
  turn: { status: 'idle' },
  asking: [],
};
