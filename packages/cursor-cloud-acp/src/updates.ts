/**
 * What the adapter draws, as ACP session updates: the SDK's tool calls as
 * tool rows and a plan, its usage, and the adapter's own lines in the
 * design's and the lead's words (CHD-622). Pure: the SDK only for its types.
 */
import { randomUUID } from 'node:crypto';
import type {
  PlanEntry,
  SessionUpdate,
  ToolKind,
  Usage,
} from '@agentclientprotocol/sdk/unstable';
import type {
  ConversationStep,
  ConversationTurn,
  InteractionUpdate,
  RunResult,
  RunStatus,
  SDKArtifact,
  SDKMessage,
  TokenUsage,
  ToolCall,
} from '@cursor/sdk';

/** A tool's ACP kind, from its name in the SDK's `ToolCall` union only. */
export function toolKind(name: string): ToolKind {
  switch (name) {
    case 'shell':
      return 'execute';
    case 'read':
      return 'read';
    case 'edit':
    case 'write':
      return 'edit';
    case 'delete':
      return 'delete';
    case 'grep':
    case 'glob':
    case 'ls':
    case 'semSearch':
      return 'search';
    case 'webFetch':
      return 'fetch';
    default:
      return 'other';
  }
}

/** The one field the SDK's own type names for each tool, shown in its title. */
const TITLED: Readonly<Record<string, string>> = {
  shell: 'command',
  read: 'path',
  write: 'path',
  edit: 'path',
  delete: 'path',
  ls: 'path',
  grep: 'pattern',
  glob: 'globPattern',
  task: 'description',
  generateImage: 'description',
};

/** A tool call as it may come: a shape the SDK's union does not know too. */
export type AnyToolCall =
  | ToolCall
  | {
      readonly type: string;
      readonly args?: unknown;
      readonly result?: unknown;
    };

/**
 * The value of the one field the SDK's type names for the tool when it is a
 * non-empty string, else the tool's name: chord draws the kind beside it,
 * so the name before a value would say it twice (5af654a3).
 */
export function toolTitle(call: AnyToolCall): string {
  const field = TITLED[call.type];
  const value =
    field === undefined || typeof call.args !== 'object' || call.args === null
      ? undefined
      : (call.args as Record<string, unknown>)[field];

  return typeof value === 'string' && value !== '' ? value : call.type;
}

/** A row's end: failed when the SDK's result says error. */
export function toolStatus(call: AnyToolCall): 'completed' | 'failed' {
  return typeof call.result === 'object' &&
    call.result !== null &&
    (call.result as { status?: unknown }).status === 'error'
    ? 'failed'
    : 'completed';
}

const TODO_STATUS = {
  pending: 'pending',
  inProgress: 'in_progress',
  completed: 'completed',
} as const;

/** An `updateTodos` call's plan, cancelled todos left out: ACP has no such status. */
export function plan(call: AnyToolCall): SessionUpdate | undefined {
  if (call.type !== 'updateTodos') {
    return undefined;
  }

  const todos = (call.args as { todos?: unknown } | undefined)?.todos;

  if (!Array.isArray(todos)) {
    return undefined;
  }

  const entries: PlanEntry[] = [];

  for (const todo of todos as unknown[]) {
    if (typeof todo !== 'object' || todo === null) {
      continue;
    }

    const { content, status: given } = todo as Record<string, unknown>;
    // Own keys only: a status such as `toString` is none of the SDK's.
    const status =
      typeof given === 'string' && Object.hasOwn(TODO_STATUS, given)
        ? TODO_STATUS[given as keyof typeof TODO_STATUS]
        : undefined;

    if (status !== undefined && typeof content === 'string') {
      // ACP requires a priority; the SDK gives none.
      entries.push({ content, priority: 'medium', status });
    }
  }

  return { sessionUpdate: 'plan', entries };
}

/** The SDK's token usage as ACP's, a field left out when the SDK has none. */
export function usage(tokens: TokenUsage): Usage {
  return {
    totalTokens: tokens.totalTokens,
    inputTokens: tokens.inputTokens,
    outputTokens: tokens.outputTokens,
    cachedReadTokens: tokens.cacheReadTokens,
    cachedWriteTokens: tokens.cacheWriteTokens,
    ...(tokens.reasoningTokens === undefined
      ? {}
      : { thoughtTokens: tokens.reasoningTokens }),
  };
}

/** One adapter line: an agent message of its own, never joined to the agent's text. */
export function line(text: string): SessionUpdate {
  return {
    sessionUpdate: 'agent_message_chunk',
    messageId: randomUUID(),
    content: { type: 'text', text },
  };
}

/**
 * Markdown's hard break: chord draws an agent's text as markdown, where a
 * bare newline joins the next line to the paragraph, and a link after one
 * wraps mid-address. With it the link stands on a line of its own.
 */
export const BREAK = '  \n';

/** The agent's page on cursor.com. */
export function link(agentId: string): string {
  return `https://cursor.com/agents/${agentId}`;
}

/** A Cursor URL as the screen shows it: `github.com/acme/web`. */
export function shown(url: string): string {
  return url.replace(/^https:\/\//, '');
}

/** An SDK string ending a sentence: no period after one it already has. */
function sentence(text: string): string {
  return /[.!?]$/.test(text) ? text : `${text}.`;
}

/** The sentence naming MCP servers a session was given, if any (Q5). */
function unreachable(servers: readonly string[]): string {
  return servers.length === 0
    ? ''
    : ` The MCP servers ${servers.join(', ')} given to this session are not reachable from Cursor's cloud.`;
}

/** The first message of a new session. */
export function firstMessage(options: {
  readonly url: string;
  readonly branch: string;
  readonly remote: string;
  readonly agentId: string;
  readonly mcpServers: readonly string[];
}): string {
  return `Cursor cloud agent on ${shown(options.url)}, starting from branch ${options.branch} on ${options.remote}. It runs in Cursor's cloud, not on this machine, pushes its work to a branch of its own, and keeps running if chord closes.${unreachable(options.mcpServers)}${BREAK}${link(options.agentId)}`;
}

/** How a resumed agent's latest run stands, from what the SDK gives. */
export interface LastRun {
  readonly status: RunStatus;
  readonly branch?: string | undefined;
  readonly error?: string | undefined;
}

/** The first message of a resumed or loaded session. */
export function resumedMessage(options: {
  readonly url: string | undefined;
  readonly agentId: string;
  readonly last: LastRun | undefined;
  readonly mcpServers: readonly string[];
}): string {
  const on =
    options.url === undefined
      ? 'Cursor cloud agent.'
      : `Cursor cloud agent on ${shown(options.url)}.`;
  const last = options.last;
  let state: string;

  if (last === undefined) {
    state = 'It has no runs yet.';
  } else if (last.status === 'finished') {
    state =
      last.branch === undefined
        ? 'Its last run finished.'
        : `Its last run finished: pushed to ${last.branch}.`;
  } else if (last.status === 'running') {
    state = 'Its last run is still going; a prompt is refused until it ends.';
  } else if (last.status === 'error') {
    state =
      last.error === undefined
        ? 'Its last run failed.'
        : `Its last run failed: ${sentence(last.error)}`;
  } else {
    state = 'Its last run was cancelled.';
  }

  return `${on} ${state}${unreachable(options.mcpServers)}${BREAK}${link(options.agentId)}`;
}

/** While Cursor provisions the VM. */
export const STARTING = "Cursor is starting the agent's machine…";

/** A `request` event: shown, never answered. */
export function requestLine(requestId: string, agentId: string): string {
  return `Cursor's agent is waiting for input or approval (request ${requestId}). This adapter cannot answer it; Esc stops the run.${BREAK}${link(agentId)}`;
}

/** A cancel Cursor did not confirm within the bound. */
export function unconfirmedStop(agentId: string): string {
  return `Cursor did not confirm the stop; the run may still be going: ${link(agentId)}`;
}

/** A run that cannot give its conversation, at load. */
export function noConversation(reason: string | undefined): string {
  return reason === undefined || reason === ''
    ? "Cursor cannot give this run's conversation."
    : `Cursor cannot give this run's conversation: ${sentence(reason)}`;
}

/** The run's end: each branch it pushed, its pull request, its artifacts. */
export function runEnd(
  result: Pick<RunResult, 'git'>,
  artifacts: readonly Pick<SDKArtifact, 'path'>[],
): string[] {
  const lines = (result.git?.branches ?? []).flatMap((each) =>
    each.branch === undefined
      ? []
      : [
          `Pushed to ${each.branch} on ${shown(each.repoUrl)}.${each.prUrl === undefined ? '' : ` Pull request: ${each.prUrl}`}`,
        ],
  );

  if (artifacts.length > 0) {
    lines.push(
      `Artifacts in the cloud: ${artifacts.map((each) => each.path).join(', ')}.`,
    );
  }

  return lines;
}

/**
 * One prompt's stream as ACP updates: `onDelta`'s content and
 * `run.stream()`'s `status`, `task` and `request`. The agent's text and
 * thinking keep one message id until something else is drawn, so an
 * adapter line between two pieces of text splits them. A kind neither
 * knows, from a later SDK, is passed over.
 */
export class Drawing {
  #text: string | undefined;
  #thought: string | undefined;

  constructor(private readonly agentId: string) {}

  /** `onDelta`'s update. */
  delta(update: InteractionUpdate): SessionUpdate[] {
    switch (update.type) {
      case 'text-delta':
        this.#thought = undefined;
        this.#text ??= randomUUID();

        return [
          {
            sessionUpdate: 'agent_message_chunk',
            messageId: this.#text,
            content: { type: 'text', text: update.text },
          },
        ];
      case 'thinking-delta':
        this.#text = undefined;
        this.#thought ??= randomUUID();

        return [
          {
            sessionUpdate: 'agent_thought_chunk',
            messageId: this.#thought,
            content: { type: 'text', text: update.text },
          },
        ];
      case 'tool-call-started':
        return this.#other([
          {
            sessionUpdate: 'tool_call',
            toolCallId: update.callId,
            title: toolTitle(update.toolCall),
            kind: toolKind(update.toolCall.type),
            status: 'in_progress',
            rawInput: update.toolCall.args,
          },
          ...optional(plan(update.toolCall)),
        ]);
      case 'partial-tool-call':
        return this.#other([
          {
            sessionUpdate: 'tool_call_update',
            toolCallId: update.callId,
            title: toolTitle(update.toolCall),
            kind: toolKind(update.toolCall.type),
            rawInput: update.toolCall.args,
          },
        ]);
      case 'tool-call-delta':
        return this.#other([
          { sessionUpdate: 'tool_call_update', toolCallId: update.callId },
        ]);
      case 'tool-call-completed':
        return this.#other([
          {
            sessionUpdate: 'tool_call_update',
            toolCallId: update.callId,
            status: toolStatus(update.toolCall),
            rawInput: update.toolCall.args,
            rawOutput: update.toolCall.result,
          },
          ...optional(plan(update.toolCall)),
        ]);
      default:
        return [];
    }
  }

  /** `run.stream()`'s message, for what only it carries. */
  message(message: SDKMessage): SessionUpdate[] {
    switch (message.type) {
      case 'status':
        if (message.status === 'CREATING') {
          return this.#other([line(STARTING)]);
        }

        return TERMINAL.has(message.status) && message.message
          ? this.#other([line(message.message)])
          : [];
      case 'task':
        return message.text ? this.#other([line(message.text)]) : [];
      case 'request':
        return this.#other([
          line(requestLine(message.request_id, this.agentId)),
        ]);
      default:
        return [];
    }
  }

  /** Something other than the agent's text: the next text is a new message. */
  #other(updates: SessionUpdate[]): SessionUpdate[] {
    this.#text = undefined;
    this.#thought = undefined;

    return updates;
  }
}

const TERMINAL = new Set(['FINISHED', 'ERROR', 'CANCELLED', 'EXPIRED']);

function optional<T>(value: T | undefined): T[] {
  return value === undefined ? [] : [value];
}

/**
 * A finished run's conversation, as `session/load` replays it: each turn's
 * user message, then its steps drawn as the live updates are.
 */
export function replay(turns: readonly ConversationTurn[]): SessionUpdate[] {
  return turns.flatMap((turn): SessionUpdate[] => {
    if (turn.type !== 'agentConversationTurn') {
      return [];
    }

    const asked: SessionUpdate[] =
      turn.turn.userMessage === undefined
        ? []
        : [
            {
              sessionUpdate: 'user_message_chunk',
              messageId: randomUUID(),
              content: { type: 'text', text: turn.turn.userMessage.text },
            },
          ];

    return [...asked, ...turn.turn.steps.flatMap(stepUpdates)];
  });
}

function stepUpdates(step: ConversationStep): SessionUpdate[] {
  switch (step.type) {
    case 'assistantMessage':
      return [
        {
          sessionUpdate: 'agent_message_chunk',
          messageId: randomUUID(),
          content: { type: 'text', text: step.message.text },
        },
      ];
    case 'thinkingMessage':
      return [
        {
          sessionUpdate: 'agent_thought_chunk',
          messageId: randomUUID(),
          content: { type: 'text', text: step.message.text },
        },
      ];
    case 'toolCall': {
      const call = step.message;
      const toolCallId = randomUUID();

      return [
        {
          sessionUpdate: 'tool_call',
          toolCallId,
          title: toolTitle(call),
          kind: toolKind(call.type),
          status: toolStatus(call),
          rawInput: call.args,
          rawOutput: call.result,
        },
        ...optional(plan(call)),
      ];
    }
    default:
      return [];
  }
}
