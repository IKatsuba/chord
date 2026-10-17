/**
 * The enrichers chord runs on every session, in order: a subagent in the
 * adapters' draft shape put in ACP's, a cost from the turn's tokens, the
 * context window from the model, a tool call's title and kind carried onto
 * its updates, a mode read back from an answer that says nothing, and the
 * questions in each adapter's question form read into one shape. Each fills
 * in only what the agent left out.
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
  MCP_CALL,
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
  choices,
  formFields,
  type FormFields,
  isText,
  type Question,
  type Questions,
  QUESTIONS,
  text,
} from './questions.ts';
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

/** A form field: its key and its schema. */
type Field = readonly [string, Readonly<Record<string, unknown>>];

/**
 * A form's questions as one adapter lays them out, read from the request's
 * params and its fields; none unless every mark of the adapter's is there
 * and every field has its place, so no field a person must fill in is hidden.
 */
type QuestionReader = (
  params: Readonly<Record<string, unknown>>,
  fields: FormFields,
) => Questions | undefined;

/**
 * The enricher that puts what `read` finds under `_meta["chord/questions"]`,
 * leaving the form as the agent sent it. A request another enricher has
 * already read passes as it is.
 */
function questionShape(read: QuestionReader): Enricher {
  return (message) => {
    if (
      !('method' in message) ||
      !('id' in message) ||
      message.method !== 'elicitation/create'
    ) {
      return [message];
    }

    const params = recordOf(message.params);
    const meta = recordOf(params._meta);
    const fields = formFields(params);

    if (meta[QUESTIONS] !== undefined || fields === undefined) {
      return [message];
    }

    const questions = read(params, fields);

    return questions === undefined
      ? [message]
      : [
          withParams(message, {
            ...params,
            _meta: markFilled({ ...meta, [QUESTIONS]: questions }, [QUESTIONS]),
          }),
        ];
  };
}

/**
 * Pairs each question field with the own-answer field its key names, as
 * claude's, factory-droid's and opencode's forms key them: `question` and
 * `own` match a key, `own` with the question's key as its first group. Every
 * key must be one or the other, and every own answer must have its question.
 */
function pairedByKey(
  fields: FormFields,
  question: RegExp,
  own: RegExp,
): { id: string; property: Field[1]; own?: Field }[] | undefined {
  const owns = new Map<string, Field>();
  const questions: Field[] = [];

  for (const [key, property] of fields.properties) {
    const ownOf = own.exec(key)?.[1];

    if (ownOf !== undefined) {
      owns.set(ownOf, [key, property]);
    } else if (question.test(key)) {
      questions.push([key, property]);
    } else {
      return undefined;
    }
  }

  if ([...owns.keys()].some((id) => !questions.some(([key]) => key === id))) {
    return undefined;
  }

  return questions.map(([id, property]) => {
    const pair = owns.get(id);

    return { id, property, ...(pair === undefined ? {} : { own: pair }) };
  });
}

/**
 * claude's AskUserQuestion: `question_<n>` with its header as the title and
 * the question as the description, or, alone, as the form's message; then
 * `question_<n>_custom`, titled `Other`, the own answer beside the pick.
 */
export const claudeQuestions = questionShape((params, fields) => {
  const pairs = pairedByKey(
    fields,
    /^question_\d+$/,
    /^(question_\d+)_custom$/,
  );
  const questions: Question[] = [];

  for (const { id, property, own } of pairs ?? []) {
    const picks = choices(property);
    const question =
      text(property.description) ??
      (pairs?.length === 1 ? text(params.message) : undefined);
    const header = text(property.title);

    if (
      picks === undefined ||
      picks.options.length === 0 ||
      question === undefined ||
      own === undefined ||
      own[1].title !== 'Other' ||
      !isText(own[1])
    ) {
      return undefined;
    }

    const placeholder = text(own[1].description);

    questions.push({
      id,
      ...(header === undefined ? {} : { header }),
      text: question,
      ...picks,
      required: fields.required.has(id),
      own: {
        field: own[0],
        mode: 'beside',
        ...(placeholder === undefined ? {} : { placeholder }),
      },
    });
  }

  return pairs === undefined ? undefined : { agent: 'claude', questions };
});

/**
 * codex's `request_user_input`: each question's field carries
 * `_meta.codex`, with the question as its title and the header as its
 * description, options or none, and its note, which `_meta.codex` marks a
 * `user_note` for its `questionId`, goes beside the pick. The request's own
 * `_meta.codex` gives how long codex waits for the person.
 */
export const codexQuestions = questionShape((params, fields) => {
  const codex = recordOf(params._meta).codex;

  if (!isRecord(codex)) {
    return undefined;
  }

  const notes = new Map<string, Field>();
  const asked: [...Field, Readonly<Record<string, unknown>>][] = [];

  for (const [key, property] of fields.properties) {
    const mark = recordOf(property._meta).codex;

    if (!isRecord(mark)) {
      return undefined;
    }

    if (mark.role === 'user_note') {
      if (
        typeof mark.questionId !== 'string' ||
        !isText(property) ||
        notes.has(mark.questionId)
      ) {
        return undefined;
      }

      notes.set(mark.questionId, [key, property]);
    } else {
      asked.push([key, property, mark]);
    }
  }

  if ([...notes.keys()].some((id) => !asked.some(([key]) => key === id))) {
    return undefined;
  }

  const questions: Question[] = [];

  for (const [id, property, mark] of asked) {
    const picks = isText(property)
      ? { options: [], multiSelect: false }
      : choices(property);
    const question = text(property.title);
    const header = text(property.description);
    const note = notes.get(id);
    const placeholder =
      note === undefined
        ? undefined
        : (text(note[1].description) ?? text(note[1].title));

    if (picks === undefined || question === undefined) {
      return undefined;
    }

    questions.push({
      id,
      ...(header === undefined ? {} : { header }),
      text: question,
      ...picks,
      required: fields.required.has(id),
      ...(mark.isSecret === true ? { secret: true } : {}),
      ...(note === undefined
        ? {}
        : {
            own: {
              field: note[0],
              mode: 'beside',
              ...(placeholder === undefined ? {} : { placeholder }),
            },
          }),
    });
  }

  const wait = codex.autoResolutionMs;

  return {
    agent: 'codex',
    questions,
    ...(typeof wait === 'number' && wait >= 0 ? { expiresInMs: wait } : {}),
  };
});

/** The message factory-droid's question forms open with. */
const DROID_MESSAGE = 'Droid needs your answers to continue.';

/**
 * factory-droid's questions: `question_<i>`, its topic as the title and the
 * question as the description, its options `option_<k>` and a last `other`,
 * which `question_<i>_other` gives the text of; or a typed question with no
 * options.
 */
export const droidQuestions = questionShape((params, fields) => {
  const pairs =
    params.message === DROID_MESSAGE
      ? pairedByKey(fields, /^question_\d+$/, /^(question_\d+)_other$/)
      : undefined;
  const questions: Question[] = [];

  for (const { id, property, own } of pairs ?? []) {
    const picks = isText(property)
      ? { options: [], multiSelect: false }
      : choices(property);
    const question = text(property.description);
    const header = text(property.title);
    const options = picks?.options.filter((option) => option.value !== 'other');
    const offersOther = options?.length !== picks?.options.length;

    if (
      picks === undefined ||
      options === undefined ||
      question === undefined ||
      options.some((option) => !/^option_\d+$/.test(option.value)) ||
      offersOther !== (own !== undefined) ||
      (own !== undefined && !isText(own[1]))
    ) {
      return undefined;
    }

    questions.push({
      id,
      ...(header === undefined ? {} : { header }),
      text: question,
      options,
      multiSelect: picks.multiSelect,
      required: fields.required.has(id),
      ...(own === undefined
        ? {}
        : { own: { field: own[0], mode: 'withValue', value: 'other' } }),
    });
  }

  return pairs === undefined ? undefined : { agent: 'droid', questions };
});

/**
 * opencode's questions, under the message `Questions`: `q<i>`, its header as
 * the title and the question as the description, then `q<i>_custom`, titled
 * `(other)`, the own answer beside the pick.
 */
export const opencodeQuestions = questionShape((params, fields) => {
  const pairs =
    params.message === 'Questions'
      ? pairedByKey(fields, /^q\d+$/, /^(q\d+)_custom$/)
      : undefined;
  const questions: Question[] = [];

  for (const { id, property, own } of pairs ?? []) {
    const picks = choices(property);
    const question = text(property.description);
    const header = text(property.title);

    if (
      picks === undefined ||
      picks.options.length === 0 ||
      question === undefined ||
      own === undefined ||
      own[1].title !== '(other)' ||
      !isText(own[1])
    ) {
      return undefined;
    }

    const placeholder = text(own[1].description);

    questions.push({
      id,
      ...(header === undefined ? {} : { header }),
      text: question,
      ...picks,
      required: fields.required.has(id),
      own: {
        field: own[0],
        mode: 'beside',
        ...(placeholder === undefined ? {} : { placeholder }),
      },
    });
  }

  return pairs === undefined ? undefined : { agent: 'opencode', questions };
});

/**
 * dimcode's questions, the request marked `_meta.lody.elicitation`: each
 * question's field keyed by its id, its header as the title and the question
 * as the description, and `__custom_<i>`, whose `_meta.lody.elicitation`
 * names the question it answers instead of a pick, as dimcode refuses both.
 */
export const dimcodeQuestions = questionShape((params, fields) => {
  const lody = (value: unknown) =>
    recordOf(recordOf(recordOf(value)._meta).lody).elicitation;

  if (!isRecord(lody(params))) {
    return undefined;
  }

  const owns = new Map<string, Field>();
  const asked: Field[] = [];

  for (const [key, property] of fields.properties) {
    const answers = recordOf(lody(property)).customAnswerFor;

    if (typeof answers === 'string') {
      if (
        !/^__custom_\d+$/.test(key) ||
        !isText(property) ||
        owns.has(answers)
      ) {
        return undefined;
      }

      owns.set(answers, [key, property]);
    } else {
      asked.push([key, property]);
    }
  }

  if ([...owns.keys()].some((id) => !asked.some(([key]) => key === id))) {
    return undefined;
  }

  const questions: Question[] = [];

  for (const [id, property] of asked) {
    const picks = choices(property);
    const question = text(property.description);
    const header = text(property.title);
    const own = owns.get(id);

    if (
      picks === undefined ||
      picks.options.length === 0 ||
      question === undefined
    ) {
      return undefined;
    }

    questions.push({
      id,
      ...(header === undefined ? {} : { header }),
      text: question,
      ...picks,
      required: fields.required.has(id),
      ...(own === undefined ? {} : { own: { field: own[0], mode: 'instead' } }),
    });
  }

  return { agent: 'dimcode', questions };
});

/**
 * The enricher that files an MCP call's tool and arguments under
 * `_meta["chord/mcp"]` where codex-acp wraps them in the call's `rawInput`,
 * `{server, tool, arguments}`, and says `_meta.is_mcp_tool_call`: Claude's
 * adapter sends the arguments as `rawInput` itself, which is what chord
 * ties a request its own server served to the call by (CHD-377). The
 * `rawInput` stays as the agent sent it.
 */
export const codexMcpCall: Enricher = (message) => {
  const update = notificationOf(message)?.update;

  if (
    update?.sessionUpdate !== 'tool_call' &&
    update?.sessionUpdate !== 'tool_call_update'
  ) {
    return [message];
  }

  const meta = recordOf(update._meta);
  const wrapped = recordOf(update.rawInput);

  if (
    meta.is_mcp_tool_call !== true ||
    meta[MCP_CALL] !== undefined ||
    typeof wrapped.tool !== 'string' ||
    !('arguments' in wrapped)
  ) {
    return [message];
  }

  return [
    withUpdate(message, {
      ...update,
      _meta: {
        ...markFilled(update._meta, [MCP_CALL]),
        [MCP_CALL]: { tool: wrapped.tool, arguments: wrapped.arguments },
      },
    }),
  ];
};

/** Every enricher, in the order each runs over what the last one made. */
export const ENRICHERS: readonly Enricher[] = [
  subagentShape,
  toolCallFacts,
  codexMcpCall,
  modeReadBack,
  costFromTokens,
  windowFromModel,
  claudeQuestions,
  codexQuestions,
  droidQuestions,
  opencodeQuestions,
  dimcodeQuestions,
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
