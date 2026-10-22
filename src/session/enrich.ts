/**
 * The enricher chain: what one agent leaves out of an ACP message, chord fills
 * in before anything reads it — the session's state, the record, the window
 * and `-p` alike. Each enricher is pure, from one message the agent sent and
 * what the chain knows of its sessions to the messages chord reads in its
 * place, ACP's shape on both sides, so a chain could later stand in an ACP
 * proxy for other clients. What the chain knows is folded from the traffic
 * both ways, after each message has been enriched.
 */
import type {
  AnyMessage,
  SessionNotification,
  SessionUpdate,
  ToolKind,
  Usage,
} from '@agentclientprotocol/sdk';
import type { Relay } from '../acp/traffic.ts';
import {
  type AgentState,
  foldUpdate,
  modesOf,
  type SessionAnswer,
  stateOf,
  withOptions,
} from './agent_state.ts';
import { isModelState } from './models.ts';
import { type TokenUsage, tokensOf } from './usage.ts';

/**
 * The `_meta` key on what chord filled in, naming the fields it filled, so a
 * cost or a window chord worked out reads as its estimate wherever it goes.
 */
export const FILLED = 'chord/filled';

/**
 * The `_meta` key on a tool call where chord files an MCP call's server,
 * tool and arguments, `{server, tool, arguments}`, when the agent wrapped
 * them in its `rawInput` rather than sending the arguments as `rawInput`
 * itself.
 */
export const MCP_CALL = 'chord/mcp';

/** What the chain knows of one session. */
export interface SessionWire {
  /** What the agent has said of the session: its options, models, modes. */
  readonly agent: AgentState;
  /** Each tool call's title and kind, as its `tool_call` or an update gave them. */
  readonly tools: Readonly<Record<string, ToolFacts>>;
  /** The context as the agent's own last `usage_update` gave it. */
  readonly usage?: { readonly used: number; readonly size: number };
  /** Whether the agent has given a cost of its own; then chord gives none. */
  readonly agentCost: boolean;
  /** chord's estimate of what the session has cost, once there is one. */
  readonly estimate?: number;
  /**
   * The running total of tokens the agent's last answer gave, on an agent
   * whose answers give one (CHD-472).
   */
  readonly total?: TokenUsage;
}

export interface ToolFacts {
  readonly title?: string;
  readonly kind?: ToolKind;
  /**
   * The agent sent content of its own for the call, not chord's filled in,
   * which an update that leaves content out keeps (CHD-440).
   */
  readonly ownContent?: boolean;
}

/** A request chord sent and the agent has not answered yet. */
export interface Asked {
  readonly method: string;
  readonly params: Readonly<Record<string, unknown>>;
  /**
   * Whether the agent reported the session's mode while this was open, so an
   * empty answer to it has already been said and is not to be read back.
   */
  readonly modeReported?: boolean;
}

/** What the chain knows: chord's open requests and each session's state. */
export interface Wire {
  readonly asked: Readonly<Record<string, Asked>>;
  readonly sessions: Readonly<Record<string, SessionWire>>;
  /**
   * The agent's answers give each session's running total as their usage,
   * not the turn's (CHD-472): a fact of the agent, not of what it sent.
   */
  readonly totals?: boolean;
}

/**
 * Turns one message the agent sent into the messages chord reads in its
 * place: itself, filled in, perhaps with others before or after it.
 */
export type Enricher = (
  message: AnyMessage,
  wire: Wire,
) => readonly AnyMessage[];

export const EMPTY_WIRE: Wire = { asked: {}, sessions: {} };

const NEW_SESSION: SessionWire = {
  agent: stateOf({}),
  tools: {},
  agentCost: false,
};

/** Each enricher in turn over what the one before it made. */
export function enrich(
  chain: readonly Enricher[],
  message: AnyMessage,
  wire: Wire,
): readonly AnyMessage[] {
  return chain.reduce<readonly AnyMessage[]>(
    (messages, enricher) => messages.flatMap((each) => enricher(each, wire)),
    [message],
  );
}

/** `wire` after a message chord sent. */
export function heardFromChord(wire: Wire, message: AnyMessage): Wire {
  if (!('method' in message) || !('id' in message) || message.id === null) {
    return wire;
  }

  return {
    ...wire,
    asked: {
      ...wire.asked,
      [String(message.id)]: {
        method: message.method,
        params: recordOf(message.params),
      },
    },
  };
}

/** `wire` after a message the agent sent, as the chain left it. */
export function heardFromAgent(wire: Wire, message: AnyMessage): Wire {
  const notification = notificationOf(message);

  if (notification !== undefined) {
    const { sessionId, update } = notification;
    const heard = withSession(wire, sessionId, (session) =>
      heardUpdate(session, update),
    );

    return reportsMode(
      update,
      wire.sessions[sessionId],
      heard.sessions[sessionId],
    )
      ? { ...heard, asked: modeReportedTo(heard.asked, sessionId) }
      : heard;
  }

  const answer = answerOf(message, wire);
  const id = 'method' in message || !('id' in message) ? undefined : message.id;

  if (id === undefined || id === null || !(String(id) in wire.asked)) {
    return wire;
  }

  const { [String(id)]: _, ...asked } = wire.asked;
  const answered = { ...wire, asked };

  // An error answers the request too, and moves nothing.
  if (answer === undefined) {
    return answered;
  }

  const result = recordOf(answer.result);
  const sessionId = answer.sessionId ?? stringOf(result.sessionId);

  if (sessionId === undefined) {
    return answered;
  }

  switch (answer.method) {
    case 'session/new':
    case 'session/load':
    case 'session/resume':
      return withSession(answered, sessionId, (session) => ({
        ...session,
        agent: {
          ...stateOf(result as SessionAnswer),
          commands: session.agent.commands,
        },
      }));
    case 'session/prompt': {
      const usage = result.usage as Usage | null | undefined;

      return wire.totals === true && usage
        ? withSession(answered, sessionId, (session) => ({
            ...session,
            total: tokensOf(usage),
          }))
        : answered;
    }
    case 'session/set_config_option':
      return withSession(answered, sessionId, (session) => ({
        ...session,
        agent: withOptions(
          session.agent,
          Array.isArray(result.configOptions)
            ? result.configOptions
            : undefined,
        ),
      }));
    case 'session/set_model': {
      const modelId = stringOf(answer.params.modelId);

      return withSession(answered, sessionId, (session) =>
        modelId === undefined || !isModelState(session.agent.models)
          ? session
          : {
              ...session,
              agent: {
                ...session.agent,
                models: { ...session.agent.models, currentModelId: modelId },
              },
            },
      );
    }
    default:
      return answered;
  }
}

/**
 * `wire` with what a session's past said, for a session reopened from chord's
 * record, whose past the agent does not replay: the cost it had come to,
 * whether the agent gave its own, and the running total of tokens it last
 * gave, on an agent that gives one.
 */
export function recalled(
  wire: Wire,
  sessionId: string,
  past: readonly SessionUpdate[],
  total?: TokenUsage,
): Wire {
  return withSession(wire, sessionId, (session) => ({
    ...past.reduce(heardUpdate, session),
    ...(total === undefined ? {} : { total }),
  }));
}

/**
 * A relay that runs `chain` over everything the agent sends, on an agent
 * whose answers give the session's running total as their usage when
 * `totals`.
 */
export function enricherRelay(
  chain: readonly Enricher[],
  totals = false,
): Relay & {
  /**
   * Folds in a session's recorded past before it is reopened, with the
   * running total its agent last gave, where it gives one.
   */
  recall(
    sessionId: string,
    past: readonly SessionUpdate[],
    total?: TokenUsage,
  ): void;
} {
  let wire: Wire = totals ? { ...EMPTY_WIRE, totals } : EMPTY_WIRE;

  return {
    fromChord: (message) => {
      wire = heardFromChord(wire, message);
    },
    fromAgent: (message) => {
      const out = enrich(chain, message, wire);

      for (const each of out) {
        wire = heardFromAgent(wire, each);
      }

      return out;
    },
    recall: (sessionId, past, total) => {
      wire = recalled(wire, sessionId, past, total);
    },
  };
}

/**
 * Whether `update` reports the session's mode: a mode update always, the
 * config options only when the mode in them moved, as ACP sends the whole set
 * for a change to any one of them.
 */
function reportsMode(
  update: SessionUpdate,
  before: SessionWire | undefined,
  after: SessionWire | undefined,
): boolean {
  return (
    update.sessionUpdate === 'current_mode_update' ||
    (update.sessionUpdate === 'config_option_update' &&
      modeIn(before) !== modeIn(after))
  );
}

function modeIn(session: SessionWire | undefined): string | undefined {
  return session === undefined ? undefined : modesOf(session.agent)?.current;
}

/** `asked` with each open request about `sessionId` marked as told its mode. */
function modeReportedTo(
  asked: Wire['asked'],
  sessionId: string,
): Wire['asked'] {
  return Object.fromEntries(
    Object.entries(asked).map(([id, each]) => [
      id,
      each.params.sessionId === sessionId
        ? { ...each, modeReported: true }
        : each,
    ]),
  );
}

function heardUpdate(session: SessionWire, update: SessionUpdate): SessionWire {
  const agent = foldUpdate(session.agent, update);

  switch (update.sessionUpdate) {
    case 'tool_call':
    case 'tool_call_update': {
      const known = session.tools[update.toolCallId] ?? {};
      const facts: ToolFacts = {
        ...known,
        ...(typeof update.title === 'string' ? { title: update.title } : {}),
        ...(typeof update.kind === 'string' ? { kind: update.kind } : {}),
        // Content chord filled in is none of the agent's: what it sent there
        // was none, or an empty list that cleared its own.
        ...(Array.isArray(update.content)
          ? {
              ownContent:
                update.content.length > 0 &&
                !filledIn(update).includes('content'),
            }
          : {}),
      };

      return {
        ...session,
        agent,
        tools: { ...session.tools, [update.toolCallId]: facts },
      };
    }
    case 'usage_update': {
      const filled = filledIn(update);
      const cost =
        typeof update.cost?.amount === 'number'
          ? update.cost.amount
          : undefined;

      return {
        ...session,
        agent,
        // A size chord filled in is still none the agent gave.
        ...(filled.includes('used')
          ? {}
          : {
              usage: {
                used: update.used,
                size: filled.includes('size') ? 0 : update.size,
              },
            }),
        ...(cost !== undefined && filled.includes('cost')
          ? { estimate: cost }
          : {}),
        agentCost:
          session.agentCost || (cost !== undefined && !filled.includes('cost')),
      };
    }
    default:
      return { ...session, agent };
  }
}

function withSession(
  wire: Wire,
  sessionId: string,
  change: (session: SessionWire) => SessionWire,
): Wire {
  return {
    ...wire,
    sessions: {
      ...wire.sessions,
      [sessionId]: change(wire.sessions[sessionId] ?? NEW_SESSION),
    },
  };
}

/** The fields chord filled in on a message's `_meta`, or on its own. */
export function filledIn(
  value:
    | { readonly _meta?: { [key: string]: unknown } | null | undefined }
    | undefined,
): readonly string[] {
  const filled = value?._meta?.[FILLED];

  return Array.isArray(filled)
    ? filled.filter((each): each is string => typeof each === 'string')
    : [];
}

/** `meta` with `fields` named as chord's, beside what it already said. */
export function markFilled(
  meta: { [key: string]: unknown } | null | undefined,
  fields: readonly string[],
): { [key: string]: unknown } {
  const already = filledIn({ _meta: meta });

  return {
    ...meta,
    [FILLED]: [...already, ...fields.filter((each) => !already.includes(each))],
  };
}

/**
 * A `session/update` the agent sent, when the message is one. Not checked
 * against ACP's schema, as the session layer takes it by its shape alone.
 */
export function notificationOf(
  message: AnyMessage,
): SessionNotification | undefined {
  if (
    'id' in message ||
    !('method' in message) ||
    message.method !== 'session/update'
  ) {
    return undefined;
  }

  const params = recordOf(message.params);
  const update = recordOf(params.update);

  return typeof params.sessionId === 'string' &&
    typeof update.sessionUpdate === 'string'
    ? (params as unknown as SessionNotification)
    : undefined;
}

/** `message` carrying `update` in place of its own. */
export function withUpdate(
  message: AnyMessage,
  update: SessionUpdate,
): AnyMessage {
  const params = recordOf('params' in message ? message.params : undefined);

  return { ...message, params: { ...params, update } } as AnyMessage;
}

/** A `session/update` of chord's own for a session, as an agent sends one. */
export function updateMessage(
  sessionId: string,
  update: SessionUpdate,
): AnyMessage {
  return {
    jsonrpc: '2.0',
    method: 'session/update',
    params: { sessionId, update },
  };
}

/** The agent's answer to one of chord's requests, with what was asked. */
export interface Answer {
  readonly id: string;
  readonly method: string;
  readonly params: Readonly<Record<string, unknown>>;
  /** The session the request named, when it named one. */
  readonly sessionId?: string;
  /** Whether the agent reported the mode while the request was open. */
  readonly modeReported: boolean;
  readonly result: unknown;
}

/** The agent's successful answer to a request of chord's, when it is one. */
export function answerOf(message: AnyMessage, wire: Wire): Answer | undefined {
  if (
    'method' in message ||
    !('id' in message) ||
    message.id === null ||
    !('result' in message)
  ) {
    return undefined;
  }

  const id = String(message.id);
  const asked = wire.asked[id];

  if (asked === undefined) {
    return undefined;
  }

  const sessionId = stringOf(asked.params.sessionId);

  return {
    id,
    method: asked.method,
    params: asked.params,
    ...(sessionId === undefined ? {} : { sessionId }),
    modeReported: asked.modeReported === true,
    result: message.result,
  };
}

/** `message`, an answer, with `result` in place of its own. */
export function withResult(message: AnyMessage, result: unknown): AnyMessage {
  return { ...message, result } as AnyMessage;
}

/** `message`, a request, with `params` in place of its own. */
export function withParams(message: AnyMessage, params: unknown): AnyMessage {
  return { ...message, params } as AnyMessage;
}

export function recordOf(value: unknown): Readonly<Record<string, unknown>> {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : {};
}

function stringOf(value: unknown): string | undefined {
  return typeof value === 'string' ? value : undefined;
}
