/**
 * The enrichers chord runs on every session, in order: a subagent in the
 * adapters' draft shape put in ACP's, a cost from the turn's tokens, the
 * context window from the model, a tool call's title and kind carried onto
 * its updates, and a mode read back from an answer that says nothing. Each
 * fills in only what the agent left out.
 */
import type {
  SessionConfigOption,
  SessionUpdate,
  ToolCallUpdate,
  Usage,
} from '@agentclientprotocol/sdk';
import { modelsOf, modesOf } from './agent_state.ts';
import {
  answerOf,
  type Enricher,
  markFilled,
  notificationOf,
  recordOf,
  type SessionWire,
  updateMessage,
  withParams,
  withResult,
  withUpdate,
} from './enrich.ts';
import { modeConfigId } from './modes.ts';
import {
  contextFrom,
  contextWindow,
  PRICE_CURRENCY,
  turnCost,
} from './prices.ts';
import { tokensOf } from './usage.ts';

/**
 * Prices a turn whose answer carries its tokens, for an agent that has given
 * no cost of its own: a `usage_update` with chord's estimate of the session's
 * cost so far goes ahead of the answer, as Claude's adapter sends its own,
 * with the context as the agent last gave it, or else as the turn's tokens
 * make it. An agent's own `usage_update` without a cost gets the estimate so
 * far.
 */
export const costFromTokens: Enricher = (message, wire) => {
  const notification = notificationOf(message);

  if (notification !== undefined) {
    const { update } = notification;
    const session = wire.sessions[notification.sessionId];

    if (
      update.sessionUpdate !== 'usage_update' ||
      update.cost ||
      session?.estimate === undefined ||
      session.agentCost
    ) {
      return [message];
    }

    return [
      withUpdate(message, {
        ...update,
        cost: { amount: session.estimate, currency: PRICE_CURRENCY },
        _meta: markFilled(update._meta, ['cost']),
      }),
    ];
  }

  const answer = answerOf(message, wire);

  if (answer?.method !== 'session/prompt' || answer.sessionId === undefined) {
    return [message];
  }

  const usage = recordOf(answer.result).usage as Usage | null | undefined;
  const session = wire.sessions[answer.sessionId];
  const model = session === undefined ? undefined : modelIn(session);

  if (!usage || session === undefined || session.agentCost || !model) {
    return [message];
  }

  const tokens = tokensOf(usage);
  const cost = turnCost(model, tokens);

  if (cost === undefined) {
    return [message];
  }

  const known = session.usage;

  return [
    updateMessage(answer.sessionId, {
      sessionUpdate: 'usage_update',
      used: known?.used ?? contextFrom(tokens),
      size: known?.size ?? 0,
      cost: {
        amount: (session.estimate ?? 0) + cost,
        currency: PRICE_CURRENCY,
      },
      _meta: markFilled(undefined, known ? ['cost'] : ['used', 'cost']),
    }),
    message,
  ];
};

/** A `usage_update` with no window gets the model's, when the data has it. */
export const windowFromModel: Enricher = (message, wire) => {
  const notification = notificationOf(message);
  const update = notification?.update;

  if (
    notification === undefined ||
    update?.sessionUpdate !== 'usage_update' ||
    (typeof update.size === 'number' && update.size > 0)
  ) {
    return [message];
  }

  const session = wire.sessions[notification.sessionId];
  const model = session === undefined ? undefined : modelIn(session);
  const size = model ? contextWindow(model) : undefined;

  return size === undefined
    ? [message]
    : [
        withUpdate(message, {
          ...update,
          size,
          _meta: markFilled(update._meta, ['size']),
        }),
      ];
};

/**
 * A `tool_call_update`, or the tool call a permission asks about, gets the
 * title and kind the call had when the agent gave them before and leaves them
 * out now.
 */
export const toolCallFacts: Enricher = (message, wire) => {
  const notification = notificationOf(message);

  if (notification?.update.sessionUpdate === 'tool_call_update') {
    const filled = carried(
      notification.update,
      wire.sessions[notification.sessionId],
    );

    return [
      filled === undefined
        ? message
        : withUpdate(message, {
            ...filled,
            sessionUpdate: 'tool_call_update',
          }),
    ];
  }

  if (
    !('method' in message) ||
    !('id' in message) ||
    message.method !== 'session/request_permission'
  ) {
    return [message];
  }

  const params = recordOf(message.params);
  const toolCall = params.toolCall as ToolCallUpdate | undefined;
  const session =
    typeof params.sessionId === 'string'
      ? wire.sessions[params.sessionId]
      : undefined;
  const filled =
    toolCall === undefined ? undefined : carried(toolCall, session);

  return [
    filled === undefined
      ? message
      : withParams(message, { ...params, toolCall: filled }),
  ];
};

/**
 * Reads back a mode change the agent answered with nothing, as Codex's
 * adapter does, though its mode moved: an empty answer to `session/set_mode`
 * is followed by the `current_mode_update` it left out, and an answer to
 * `session/set_config_option` for the mode that carries no options gets them
 * as they now stand. An agent that already said so is left as it is, and so
 * is one that reported a mode while the request was open: the mode it named
 * then may not be the one chord asked for, and it is the agent's word.
 */
export const modeReadBack: Enricher = (message, wire) => {
  const answer = answerOf(message, wire);
  const session =
    answer?.sessionId === undefined
      ? undefined
      : wire.sessions[answer.sessionId];

  if (
    answer?.sessionId === undefined ||
    session === undefined ||
    answer.modeReported
  ) {
    return [message];
  }

  if (answer.method === 'session/set_mode') {
    const modeId = answer.params.modeId;

    if (
      typeof modeId !== 'string' ||
      modesOf(session.agent)?.current === modeId
    ) {
      return [message];
    }

    return [
      updateMessage(answer.sessionId, {
        sessionUpdate: 'current_mode_update',
        currentModeId: modeId,
        _meta: markFilled(undefined, ['currentModeId']),
      }),
      message,
    ];
  }

  const result = recordOf(answer.result);
  const key = modeConfigId(session.agent.configOptions);
  const value = answer.params.value;

  if (
    answer.method !== 'session/set_config_option' ||
    key === undefined ||
    answer.params.configId !== key ||
    typeof value !== 'string' ||
    (Array.isArray(result.configOptions) && result.configOptions.length > 0)
  ) {
    return [message];
  }

  const configOptions = session.agent.configOptions.map(
    (option): SessionConfigOption =>
      option.id === key && option.type === 'select'
        ? { ...option, currentValue: value }
        : option,
  );

  return [
    withResult(message, {
      ...result,
      configOptions,
      _meta: markFilled(recordOf(result._meta), ['configOptions']),
    }),
  ];
};

/**
 * The `_meta` key on a `subagent_update` made from the adapters' draft shape,
 * holding what that shape said that ACP's has no field for: its own kind, and
 * the rest, such as `prompt`, so nothing the agent sent is lost.
 */
export const SUBAGENT_DRAFT = 'chord/subagent_draft';

/**
 * A subagent as ACP's `subagent_update` says it, from the shape Claude's and
 * Codex's adapters send (ACP's draft PR #1992): `subagent_spawned`'s
 * `subagentSessionId`, `name`, `task` and `capabilities` become `sessionId`,
 * `title`, `description` and `capabilities`, and `subagent_state_update`'s
 * `state`, a word, becomes a state object of that word. The rest of the draft
 * goes under `_meta`. An agent that sends `subagent_update` already passes as
 * it is, so the rest of chord reads one shape, and a later change to either
 * touches only this.
 */
export const subagentShape: Enricher = (message) => {
  const notification = notificationOf(message);
  const draft = recordOf(notification?.update);
  const { sessionUpdate, subagentSessionId } = draft;

  if (
    notification === undefined ||
    typeof subagentSessionId !== 'string' ||
    (sessionUpdate !== 'subagent_spawned' &&
      sessionUpdate !== 'subagent_state_update')
  ) {
    return [message];
  }

  const rest: Record<string, unknown> = {};
  const update: Record<string, unknown> = {
    sessionUpdate: 'subagent_update',
    sessionId: subagentSessionId,
  };
  const renamed: Readonly<Record<string, string>> = {
    name: 'title',
    task: 'description',
  };

  for (const [key, value] of Object.entries(draft)) {
    if (
      key === 'sessionUpdate' ||
      key === 'subagentSessionId' ||
      key === '_meta'
    ) {
      continue;
    }

    const as = renamed[key];

    if (as !== undefined && typeof value === 'string') {
      update[as] = value;
    } else if (key === 'capabilities' && isRecord(value)) {
      update.capabilities = value;
    } else if (key === 'state' && typeof value === 'string') {
      update.state = { state: value };
    } else {
      rest[key] = value;
    }
  }

  update._meta = {
    ...recordOf(draft._meta),
    [SUBAGENT_DRAFT]: { sessionUpdate, ...rest },
  };

  return [withUpdate(message, update as SessionUpdate)];
};

/** Every enricher, in the order each runs over what the last one made. */
export const ENRICHERS: readonly Enricher[] = [
  subagentShape,
  toolCallFacts,
  modeReadBack,
  costFromTokens,
  windowFromModel,
];

/** The id of the model the session is on, as the agent last said it. */
function modelIn(session: SessionWire): string | undefined {
  return modelsOf(session.agent)?.current;
}

/**
 * `call` with the title and kind the session knows for it, where it has none;
 * undefined when nothing is missing or nothing is known.
 */
function carried<T extends ToolCallUpdate>(
  call: T,
  session: SessionWire | undefined,
): T | undefined {
  const known = session?.tools[call.toolCallId];
  const title = !call.title && known?.title ? { title: known.title } : {};
  const kind = !call.kind && known?.kind ? { kind: known.kind } : {};
  const fields = Object.keys({ ...title, ...kind });

  return fields.length === 0
    ? undefined
    : {
        ...call,
        ...title,
        ...kind,
        _meta: markFilled(call._meta, fields),
      };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}
