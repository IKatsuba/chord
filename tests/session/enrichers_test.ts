import { describe, expect, test } from 'bun:test';
import assert from 'node:assert/strict';
import type {
  AnyMessage,
  SessionConfigOption,
  SessionUpdate,
} from '@agentclientprotocol/sdk';
import { enricherRelay, FILLED, MCP_CALL } from '../../src/session/enrich.ts';
import { reduceTranscript } from '../../src/session/transcript/reducer.ts';
import { emptyTranscript } from '../../src/session/transcript/types.ts';
import {
  codexMcpCall,
  costFromTokens,
  ENRICHERS,
  modeReadBack,
  rawOutputContent,
  SUBAGENT_DRAFT,
  subagentShape,
  toolCallFacts,
  windowFromModel,
} from '../../src/session/enrichers.ts';
import {
  contextFrom,
  contextWindow,
  turnCost,
} from '../../src/session/prices.ts';
import { type Questions, QUESTIONS } from '../../src/session/questions.ts';
import { FORM_SCHEMA } from '../fixtures/forms.ts';
import {
  CLAUDE_QUESTION,
  CLAUDE_QUESTIONS,
  CODEX_QUESTIONS,
  DIMCODE_QUESTIONS,
  DROID_QUESTIONS,
  OPENCODE_QUESTIONS,
  type QuestionForm,
} from '../fixtures/questions.ts';

const SESSION = 'session-1';

const TOKENS = {
  inputTokens: 1000,
  outputTokens: 200,
  cachedReadTokens: 800,
  totalTokens: 2000,
};

function modelOption(current: string): SessionConfigOption {
  return {
    id: 'model',
    name: 'Model',
    category: 'model',
    type: 'select',
    currentValue: current,
    options: [{ value: current, name: current }],
  };
}

function modeOption(current: string): SessionConfigOption {
  return {
    id: 'mode',
    name: 'Mode',
    category: 'mode',
    type: 'select',
    currentValue: current,
    options: [
      { value: 'default', name: 'Default' },
      {
        value: 'plan',
        name: 'Plan',
      },
    ],
  };
}

/**
 * A relay running `enrichers` on a session `session/new` opened with
 * `configOptions`, and a way to play a request and its answer through it.
 */
function relayOn(
  enrichers: Parameters<typeof enricherRelay>[0],
  configOptions: SessionConfigOption[] = [modelOption('gpt-5.3-codex')],
  extra: Record<string, unknown> = {},
) {
  const relay = enricherRelay(enrichers);
  let id = 0;

  const ask = (method: string, params: unknown, result: unknown) => {
    id += 1;

    relay.fromChord({ jsonrpc: '2.0', id, method, params });

    return relay.fromAgent({ jsonrpc: '2.0', id, result });
  };

  ask(
    'session/new',
    { cwd: '/' },
    {
      sessionId: SESSION,
      configOptions,
      ...extra,
    },
  );

  const update = (update: SessionUpdate) =>
    relay.fromAgent({
      jsonrpc: '2.0',
      method: 'session/update',
      params: { sessionId: SESSION, update },
    });

  const prompt = (usage?: unknown) =>
    ask(
      'session/prompt',
      { sessionId: SESSION, prompt: [] },
      {
        stopReason: 'end_turn',
        ...(usage === undefined ? {} : { usage }),
      },
    );

  return { relay, ask, update, prompt };
}

/** The updates among `messages`, in order. */
function updates(messages: readonly AnyMessage[]): SessionUpdate[] {
  return messages.flatMap((message) =>
    'method' in message && message.method === 'session/update'
      ? [(message.params as { update: SessionUpdate }).update]
      : [],
  );
}

test("a turn priced from its tokens goes ahead of its answer, marked as chord's", () => {
  const { prompt } = relayOn([costFromTokens, windowFromModel]);
  const cost = turnCost('gpt-5.3-codex', TOKENS);
  const out = prompt(TOKENS);

  assert(cost !== undefined && cost > 0);
  expect(out.length).toStrictEqual(2);
  expect('result' in out[1]!).toBeTruthy();
  expect(updates(out)).toStrictEqual([
    {
      sessionUpdate: 'usage_update',
      used: 2000,
      size: 400_000,
      cost: { amount: cost, currency: 'USD' },
      _meta: { [FILLED]: ['used', 'cost', 'size'] },
    },
  ]);
});

test("each turn adds to the estimate, and an agent's own cost stops it", () => {
  const { prompt, update } = relayOn([costFromTokens]);
  const cost = turnCost('gpt-5.3-codex', TOKENS) ?? 0;

  prompt(TOKENS);

  const second = updates(prompt(TOKENS))[0];

  expect(
    second?.sessionUpdate === 'usage_update' && second.cost?.amount,
  ).toStrictEqual(cost * 2);

  // A costless usage_update of the agent's own gets the estimate so far.
  const own = updates(
    update({
      sessionUpdate: 'usage_update',
      used: 5000,
      size: 400_000,
    }),
  )[0];

  expect(own).toStrictEqual({
    sessionUpdate: 'usage_update',
    used: 5000,
    size: 400_000,
    cost: { amount: cost * 2, currency: 'USD' },
    _meta: { [FILLED]: ['cost'] },
  });

  update({
    sessionUpdate: 'usage_update',
    used: 6000,
    size: 400_000,
    cost: { amount: 1, currency: 'USD' },
  });
  expect(updates(prompt(TOKENS))).toStrictEqual([]);
});

test('a priced turn keeps the context the agent last gave', () => {
  const { prompt, update } = relayOn([costFromTokens]);

  update({ sessionUpdate: 'usage_update', used: 3000, size: 128_000 });

  const priced = updates(prompt(TOKENS))[0];

  expect(
    priced?.sessionUpdate === 'usage_update' && [
      priced.used,
      priced.size,
      priced._meta,
    ],
  ).toStrictEqual([3000, 128_000, { [FILLED]: ['cost'] }]);
});

test('no estimate for a model the data does not know, a turn with no tokens, or no model', () => {
  expect(
    updates(
      relayOn([costFromTokens], [modelOption('fake-large')]).prompt(TOKENS),
    ),
  ).toStrictEqual([]);
  expect(updates(relayOn([costFromTokens]).prompt())).toStrictEqual([]);
  expect(updates(relayOn([costFromTokens], []).prompt(TOKENS))).toStrictEqual(
    [],
  );
});

test("a model the older way, by session/new's models, is priced too", () => {
  const { prompt } = relayOn([costFromTokens], [], {
    models: {
      currentModelId: 'claude-haiku-4-5',
      availableModels: [{ modelId: 'claude-haiku-4-5', name: 'Haiku' }],
    },
  });

  expect(updates(prompt(TOKENS)).length).toStrictEqual(1);
});

test("a usage_update with no window gets the model's, and one with a window keeps it", () => {
  const { update } = relayOn([windowFromModel]);

  expect(
    updates(update({ sessionUpdate: 'usage_update', used: 10, size: 0 })),
  ).toStrictEqual([
    {
      sessionUpdate: 'usage_update',
      used: 10,
      size: 400_000,
      _meta: { [FILLED]: ['size'] },
    },
  ]);
  expect(
    updates(update({ sessionUpdate: 'usage_update', used: 10, size: 64 })),
  ).toStrictEqual([{ sessionUpdate: 'usage_update', used: 10, size: 64 }]);

  const unknown = relayOn([windowFromModel], [modelOption('fake-large')]);

  expect(
    updates(
      unknown.update({ sessionUpdate: 'usage_update', used: 1, size: 0 }),
    ),
  ).toStrictEqual([{ sessionUpdate: 'usage_update', used: 1, size: 0 }]);
});

test("a tool call's title and kind are carried onto updates that leave them out", () => {
  const { update } = relayOn([toolCallFacts]);

  update({
    sessionUpdate: 'tool_call',
    toolCallId: 'call-1',
    title: 'Read README.md',
    kind: 'read',
    status: 'pending',
  });

  expect(
    updates(
      update({
        sessionUpdate: 'tool_call_update',
        toolCallId: 'call-1',
        status: 'completed',
      }),
    ),
  ).toStrictEqual([
    {
      sessionUpdate: 'tool_call_update',
      toolCallId: 'call-1',
      status: 'completed',
      title: 'Read README.md',
      kind: 'read',
      _meta: { [FILLED]: ['title', 'kind'] },
    },
  ]);

  // A title the update gives is the one kept, and carried after.
  update({
    sessionUpdate: 'tool_call_update',
    toolCallId: 'call-1',
    title: 'Read docs/README.md',
  });
  expect(
    updates(
      update({ sessionUpdate: 'tool_call_update', toolCallId: 'call-1' }),
    )[0],
  ).toStrictEqual({
    sessionUpdate: 'tool_call_update',
    toolCallId: 'call-1',
    title: 'Read docs/README.md',
    kind: 'read',
    _meta: { [FILLED]: ['title', 'kind'] },
  });
  expect(
    updates(update({ sessionUpdate: 'tool_call_update', toolCallId: 'other' })),
  ).toStrictEqual([{ sessionUpdate: 'tool_call_update', toolCallId: 'other' }]);
});

test("Codex's MCP call has its server, tool and arguments filed beside its rawInput, which stays as sent", () => {
  const { update } = relayOn([codexMcpCall]);
  const rawInput = {
    server: 'chord',
    tool: 'send_message',
    arguments: { to: 'ship', text: 'ready' },
  };

  expect(
    updates(
      update({
        sessionUpdate: 'tool_call',
        toolCallId: 'exec-1',
        title: 'mcp.chord.send_message',
        kind: 'execute',
        status: 'in_progress',
        rawInput,
        _meta: { is_mcp_tool_call: true },
      }),
    ),
  ).toStrictEqual([
    {
      sessionUpdate: 'tool_call',
      toolCallId: 'exec-1',
      title: 'mcp.chord.send_message',
      kind: 'execute',
      status: 'in_progress',
      rawInput,
      _meta: {
        is_mcp_tool_call: true,
        [FILLED]: [MCP_CALL],
        [MCP_CALL]: {
          server: 'chord',
          tool: 'send_message',
          arguments: { to: 'ship', text: 'ready' },
        },
      },
    },
  ]);

  // Claude's shape, and a command that is no MCP call, are left alone.
  for (const call of [
    { title: 'mcp__chord__list_agents', kind: 'other', rawInput: {} },
    {
      title: 'Run a.sh',
      kind: 'execute',
      rawInput: { server: 'x', tool: 'y', arguments: {} },
    },
  ] as const) {
    const sent: SessionUpdate = {
      sessionUpdate: 'tool_call',
      toolCallId: 'other',
      ...call,
    };

    expect(updates(update(sent))).toStrictEqual([sent]);
  }
});

test('a permission asked about a known call names it', () => {
  const { relay, update } = relayOn([toolCallFacts]);

  update({
    sessionUpdate: 'tool_call',
    toolCallId: 'call-1',
    title: 'Write notes.md',
    kind: 'edit',
  });

  const [asked] = relay.fromAgent({
    jsonrpc: '2.0',
    id: 'p-1',
    method: 'session/request_permission',
    params: {
      sessionId: SESSION,
      toolCall: { toolCallId: 'call-1' },
      options: [],
    },
  });

  expect(
    asked &&
      'params' in asked &&
      (asked.params as { toolCall: unknown }).toolCall,
  ).toStrictEqual({
    toolCallId: 'call-1',
    title: 'Write notes.md',
    kind: 'edit',
    _meta: { [FILLED]: ['title', 'kind'] },
  });
});

test('an empty answer to set_mode is followed by the mode it moved to', () => {
  const { ask } = relayOn([modeReadBack], [], {
    modes: {
      currentModeId: 'default',
      availableModes: [
        { id: 'default', name: 'Default' },
        {
          id: 'plan',
          name: 'Plan',
        },
      ],
    },
  });
  const out = ask(
    'session/set_mode',
    {
      sessionId: SESSION,
      modeId: 'plan',
    },
    {},
  );

  expect(updates(out)).toStrictEqual([
    {
      sessionUpdate: 'current_mode_update',
      currentModeId: 'plan',
      _meta: { [FILLED]: ['currentModeId'] },
    },
  ]);
  expect(out.length).toStrictEqual(2);

  // The mode it is in now is not said again.
  expect(
    updates(
      ask('session/set_mode', { sessionId: SESSION, modeId: 'plan' }, {}),
    ),
  ).toStrictEqual([]);
});

test('an agent that reported its mode before answering set_mode is left as it is', () => {
  const { ask, update } = relayOn([modeReadBack], [modeOption('default')]);

  update({ sessionUpdate: 'current_mode_update', currentModeId: 'plan' });
  expect(
    updates(
      ask('session/set_mode', { sessionId: SESSION, modeId: 'plan' }, {}),
    ),
  ).toStrictEqual([]);
});

/**
 * Plays a request chord sent, the updates the agent sent while it was open,
 * and its empty answer, through `relay`.
 */
function askAround(
  relay: ReturnType<typeof relayOn>['relay'],
  id: number,
  method: string,
  params: unknown,
  meanwhile: readonly SessionUpdate[],
) {
  relay.fromChord({ jsonrpc: '2.0', id, method, params });

  for (const update of meanwhile) {
    relay.fromAgent({
      jsonrpc: '2.0',
      method: 'session/update',
      params: { sessionId: SESSION, update },
    });
  }

  return relay.fromAgent({ jsonrpc: '2.0', id, result: {} });
}

test('a mode the agent reported while set_mode was open is not read over', () => {
  const { relay, ask } = relayOn([modeReadBack], [modeOption('default')]);

  expect(
    askAround(
      relay,
      10,
      'session/set_mode',
      {
        sessionId: SESSION,
        modeId: 'plan',
      },
      [
        {
          sessionUpdate: 'current_mode_update',
          currentModeId: 'acceptEdits',
        },
      ],
    ),
  ).toStrictEqual([{ jsonrpc: '2.0', id: 10, result: {} }]);

  // The next request that hears nothing in the meantime is read back again.
  expect(
    updates(
      ask('session/set_mode', { sessionId: SESSION, modeId: 'plan' }, {}),
    ),
  ).toStrictEqual([
    {
      sessionUpdate: 'current_mode_update',
      currentModeId: 'plan',
      _meta: { [FILLED]: ['currentModeId'] },
    },
  ]);
});

test('a mode the agent reported while set_config_option was open is not read over', () => {
  const options = [modelOption('gpt-5.3-codex'), modeOption('default')];
  const { relay, ask } = relayOn([modeReadBack], options);
  const params = { sessionId: SESSION, configId: 'mode', value: 'plan' };

  expect(
    askAround(relay, 10, 'session/set_config_option', params, [
      {
        sessionUpdate: 'current_mode_update',
        currentModeId: 'acceptEdits',
      },
    ]),
  ).toStrictEqual([{ jsonrpc: '2.0', id: 10, result: {} }]);

  // The mode it reported holds: the next read back starts from acceptEdits.
  const [answer] = ask(
    'session/set_config_option',
    {
      ...params,
      value: 'default',
    },
    {},
  );

  expect(answer && 'result' in answer && answer.result).toStrictEqual({
    configOptions: [modelOption('gpt-5.3-codex'), modeOption('default')],
    _meta: { [FILLED]: ['configOptions'] },
  });

  // The mode's config option counts as a report as much as the mode update.
  expect(
    askAround(relay, 11, 'session/set_config_option', params, [
      {
        sessionUpdate: 'config_option_update',
        configOptions: [
          modelOption('gpt-5.3-codex'),
          modeOption('acceptEdits'),
        ],
      },
    ]),
  ).toStrictEqual([{ jsonrpc: '2.0', id: 11, result: {} }]);

  // The options again with the mode where it was, for another option, do not.
  expect(
    askAround(relay, 12, 'session/set_config_option', params, [
      {
        sessionUpdate: 'config_option_update',
        configOptions: [modelOption('gpt-5.4'), modeOption('acceptEdits')],
      },
    ])[0],
  ).toStrictEqual({
    jsonrpc: '2.0',
    id: 12,
    result: {
      configOptions: [modelOption('gpt-5.4'), modeOption('plan')],
      _meta: { [FILLED]: ['configOptions'] },
    },
  });
});

test('an answer to set_config_option for the mode with no options gets them as they now stand', () => {
  const options = [modelOption('gpt-5.3-codex'), modeOption('default')];
  const { ask } = relayOn([modeReadBack], options);
  const [answer] = ask(
    'session/set_config_option',
    {
      sessionId: SESSION,
      configId: 'mode',
      value: 'plan',
    },
    {},
  );

  expect(answer && 'result' in answer && answer.result).toStrictEqual({
    configOptions: [modelOption('gpt-5.3-codex'), modeOption('plan')],
    _meta: { [FILLED]: ['configOptions'] },
  });

  // Another option's answer, or one that carries the options, passes as sent.
  const effort = { configOptions: options };

  expect(
    ask(
      'session/set_config_option',
      {
        sessionId: SESSION,
        configId: 'mode',
        value: 'default',
      },
      effort,
    )[0],
  ).toStrictEqual({ jsonrpc: '2.0', id: 3, result: effort });
  expect(
    ask(
      'session/set_config_option',
      {
        sessionId: SESSION,
        configId: 'effort',
        value: 'high',
      },
      {},
    )[0],
  ).toStrictEqual({ jsonrpc: '2.0', id: 4, result: {} });
});

test('an error answers a request and moves nothing', () => {
  const { relay } = relayOn([modeReadBack], [modeOption('default')]);

  relay.fromChord({
    jsonrpc: '2.0',
    id: 'x',
    method: 'session/set_config_option',
    params: { sessionId: SESSION, configId: 'mode', value: 'plan' },
  });
  expect(
    relay.fromAgent({
      jsonrpc: '2.0',
      id: 'x',
      error: { code: -32603, message: 'no' },
    }),
  ).toStrictEqual([
    { jsonrpc: '2.0', id: 'x', error: { code: -32603, message: 'no' } },
  ]);
  // The request is answered: a stray answer under its id is not read back.
  expect(
    relay.fromAgent({ jsonrpc: '2.0', id: 'x', result: {} }),
  ).toStrictEqual([{ jsonrpc: '2.0', id: 'x', result: {} }]);
});

test('a session reopened from its record goes on from the estimate it had', () => {
  const { relay, prompt } = relayOn([costFromTokens]);
  const cost = turnCost('gpt-5.3-codex', TOKENS) ?? 0;

  relay.recall(SESSION, [
    {
      sessionUpdate: 'usage_update',
      used: 2000,
      size: 400_000,
      cost: { amount: 0.5, currency: 'USD' },
      _meta: { [FILLED]: ['cost'] },
    },
  ]);

  const next = updates(prompt(TOKENS))[0];

  expect(
    next?.sessionUpdate === 'usage_update' && next.cost?.amount,
  ).toStrictEqual(0.5 + cost);
});

test('prices: a model by the names agents give it, and the counts as either sum', () => {
  const bare = turnCost('gpt-5.3-codex', TOKENS);

  expect(bare !== undefined).toBeTruthy();
  expect(turnCost('gpt-5.3-codex/medium', TOKENS)).toStrictEqual(bare);
  expect(turnCost('openai/gpt-5.3-codex', TOKENS)).toStrictEqual(bare);
  expect(turnCost('fake-large', TOKENS)).toStrictEqual(undefined);
  // An input that already includes the cache, as OpenAI counts it, says so
  // by its total, and costs the same as the counts kept apart.
  expect(
    turnCost('gpt-5.3-codex', {
      inputTokens: 1800,
      outputTokens: 200,
      cachedReadTokens: 800,
      totalTokens: 2000,
    }),
  ).toStrictEqual(bare);
  expect(contextFrom(TOKENS)).toStrictEqual(2000);
  expect(contextWindow('claude-haiku-4-5')).toStrictEqual(200_000);
  expect(contextWindow('fake-large')).toStrictEqual(undefined);
});

/** What the adapters send, which ACP's schema does not have, played raw. */
function draft(relay: ReturnType<typeof enricherRelay>, update: unknown) {
  return updates(
    relay.fromAgent({
      jsonrpc: '2.0',
      method: 'session/update',
      params: { sessionId: SESSION, update },
    }),
  );
}

test("the adapters' subagent_spawned reads as ACP's subagent_update, with the rest of the draft kept", () => {
  const relay = enricherRelay([subagentShape]);

  expect(
    draft(relay, {
      sessionUpdate: 'subagent_spawned',
      subagentSessionId: 'child-1',
      name: 'Find the session layer',
      task: 'Find where chord routes updates.',
      prompt: [{ type: 'text', text: 'Find where chord routes updates.' }],
      capabilities: {},
      _meta: { claudeCode: { parentToolUseId: 'tool-1' } },
    }),
  ).toStrictEqual([
    {
      sessionUpdate: 'subagent_update',
      sessionId: 'child-1',
      title: 'Find the session layer',
      description: 'Find where chord routes updates.',
      capabilities: {},
      _meta: {
        claudeCode: { parentToolUseId: 'tool-1' },
        [SUBAGENT_DRAFT]: {
          sessionUpdate: 'subagent_spawned',
          prompt: [{ type: 'text', text: 'Find where chord routes updates.' }],
        },
      },
    },
  ]);
});

test("the adapters' subagent_state_update reads as a subagent_update carrying its state", () => {
  const relay = enricherRelay([subagentShape]);

  for (const state of ['completed', 'failed', 'cancelled', 'disconnected']) {
    expect(
      draft(relay, {
        sessionUpdate: 'subagent_state_update',
        subagentSessionId: 'child-1',
        state,
      }),
    ).toStrictEqual([
      {
        sessionUpdate: 'subagent_update',
        sessionId: 'child-1',
        state: { state },
        _meta: {
          [SUBAGENT_DRAFT]: { sessionUpdate: 'subagent_state_update' },
        },
      },
    ]);
  }
});

test('a field of the draft ACP has no place for, or of the wrong type, is kept, not lost', () => {
  const relay = enricherRelay([subagentShape]);
  const [update] = draft(relay, {
    sessionUpdate: 'subagent_spawned',
    subagentSessionId: 'child-1',
    name: 7,
    task: 'Look.',
    model: 'haiku',
  });

  expect(update).toStrictEqual({
    sessionUpdate: 'subagent_update',
    sessionId: 'child-1',
    description: 'Look.',
    _meta: {
      [SUBAGENT_DRAFT]: {
        sessionUpdate: 'subagent_spawned',
        name: 7,
        model: 'haiku',
      },
    },
  } as unknown as SessionUpdate);
});

test("an agent's own subagent_update, and a draft with no subagent named, pass as they came", () => {
  const relay = enricherRelay([subagentShape]);
  const own: SessionUpdate = {
    sessionUpdate: 'subagent_update',
    sessionId: 'child-1',
    title: 'Look',
    state: { state: 'idle' },
  };

  expect(draft(relay, own)).toStrictEqual([own]);
  expect(
    draft(relay, { sessionUpdate: 'subagent_spawned', name: 'Look' }),
  ).toStrictEqual([
    {
      sessionUpdate: 'subagent_spawned',
      name: 'Look',
    } as unknown as SessionUpdate,
  ]);
});

/** What the whole chain makes of an elicitation request for `form`. */
function asked(form: QuestionForm): Record<string, unknown> {
  const [message] = enricherRelay(ENRICHERS).fromAgent({
    jsonrpc: '2.0',
    id: 'e-1',
    method: 'elicitation/create',
    params: { ...form, sessionId: SESSION },
  });

  assert(message !== undefined && 'params' in message);

  return message.params as Record<string, unknown>;
}

/** The questions the chain read from `form`, checking it left the form be. */
function questionsIn(form: QuestionForm): Questions | undefined {
  const params = asked(form);
  const { _meta, ...rest } = params;
  const {
    [QUESTIONS]: questions,
    [FILLED]: filled,
    ...meta
  } = (_meta ?? {}) as Record<string, unknown>;

  expect(rest).toStrictEqual({
    ...Object.fromEntries(
      Object.entries(form).filter(([key]) => key !== '_meta'),
    ),
    sessionId: SESSION,
  });
  expect(meta).toStrictEqual(form._meta ?? {});

  if (questions !== undefined) {
    expect(filled).toStrictEqual([QUESTIONS]);
  }

  return questions as Questions | undefined;
}

test("claude's questions: its header, the question, the options and the Other beside the pick", () => {
  expect(questionsIn(CLAUDE_QUESTIONS)).toStrictEqual({
    agent: 'claude',
    questions: [
      {
        id: 'question_0',
        header: 'Language',
        text: 'Which language should helper scripts use?',
        options: [
          {
            value: 'Deno (TypeScript) (Recommended)',
            title: 'Deno (TypeScript) (Recommended)',
            description:
              'Runs from source with inline npm: and jsr: imports, no package manager',
          },
          {
            value: 'Python',
            title: 'Python',
            description: 'Only where a library has no JS or TS equivalent',
            preview: 'print("hi")',
          },
        ],
        multiSelect: false,
        required: false,
        own: {
          field: 'question_0_custom',
          mode: 'beside',
          placeholder:
            'Type your own answer, or add a note to the option you chose above (optional).',
        },
      },
      {
        id: 'question_1',
        header: 'Checks',
        text: 'Which checks should run before a commit?',
        options: [
          { value: 'Types', title: 'Types' },
          { value: 'Lint', title: 'Lint' },
          { value: 'Tests', title: 'Tests' },
        ],
        multiSelect: true,
        required: false,
        own: {
          field: 'question_1_custom',
          mode: 'beside',
          placeholder:
            'Type your own answer to add to your selection above (optional).',
        },
      },
    ],
  });
});

test("claude's lone question is its form's message", () => {
  expect(questionsIn(CLAUDE_QUESTION)?.questions[0]?.text).toBe(
    'Which language should helper scripts use?',
  );
});

test("codex's questions: the question its title, the header its description, the note beside, a secret and the wait", () => {
  expect(questionsIn(CODEX_QUESTIONS)).toStrictEqual({
    agent: 'codex',
    expiresInMs: 300_000,
    questions: [
      {
        id: 'next',
        header: 'Next step',
        text: 'What would you like to focus on next?',
        options: [
          {
            value: 'Plan a change (Recommended)',
            title: 'Plan a change (Recommended)',
          },
          {
            value: 'Review existing work',
            title: 'Review existing work',
            description: 'Read what is there first',
          },
          {
            value: 'None of the above',
            title: 'None of the above',
            description: 'Provide a different answer in the note field.',
          },
        ],
        multiSelect: false,
        required: true,
        own: {
          field: 'next_note',
          mode: 'beside',
          placeholder: 'Additional answer or note',
        },
      },
      {
        id: 'token',
        header: 'Token',
        text: 'Paste the API token for the staging deploy.',
        options: [],
        multiSelect: false,
        required: true,
        secret: true,
      },
    ],
  });
});

test("factory-droid's questions: its other option taken out, to go with the text typed", () => {
  expect(questionsIn(DROID_QUESTIONS)).toStrictEqual({
    agent: 'droid',
    questions: [
      {
        id: 'question_0',
        header: 'Storage',
        text: 'Where should uploads be kept?',
        options: [
          { value: 'option_0', title: 'Local disk' },
          { value: 'option_1', title: 'S3 bucket' },
        ],
        multiSelect: false,
        required: true,
        own: { field: 'question_0_other', mode: 'withValue', value: 'other' },
      },
      {
        id: 'question_1',
        header: 'Formats',
        text: 'Which formats should be accepted?',
        options: [
          { value: 'option_0', title: 'PNG' },
          { value: 'option_1', title: 'JPEG' },
        ],
        multiSelect: true,
        required: true,
        own: { field: 'question_1_other', mode: 'withValue', value: 'other' },
      },
      {
        id: 'question_2',
        header: 'Bucket',
        text: 'What should the bucket be called?',
        options: [],
        multiSelect: false,
        required: true,
      },
    ],
  });
});

test("opencode's and dimcode's questions, dimcode's own answer instead of a pick", () => {
  expect(questionsIn(OPENCODE_QUESTIONS)).toStrictEqual({
    agent: 'opencode',
    questions: [
      {
        id: 'q0',
        header: 'Tests',
        text: 'Where should the new tests go?',
        options: [
          {
            value: 'Beside the module',
            title: 'Beside the module',
            description: 'tests/ mirrors src/',
          },
          { value: 'In one file', title: 'In one file' },
        ],
        multiSelect: false,
        required: false,
        own: { field: 'q0_custom', mode: 'beside' },
      },
    ],
  });
  expect(questionsIn(DIMCODE_QUESTIONS)).toStrictEqual({
    agent: 'dimcode',
    questions: [
      {
        id: 'deploy',
        header: 'Deploy',
        text: 'Where should it deploy?',
        options: [
          { value: 'Staging', title: 'Staging' },
          { value: 'Production', title: 'Production' },
        ],
        multiSelect: false,
        required: false,
        own: { field: '__custom_0', mode: 'instead' },
      },
    ],
  });
});

test("a form with no adapter's marks passes as it came", () => {
  const form: QuestionForm = {
    mode: 'form',
    message: 'Set up the deploy target',
    requestedSchema: FORM_SCHEMA,
  };

  expect(asked(form)).toStrictEqual({ ...form, sessionId: SESSION });
});

test('a form with a field no question has a place for gets no questions', () => {
  const schema = CLAUDE_QUESTIONS.requestedSchema;
  const extra = (properties: Record<string, unknown>): QuestionForm => ({
    ...CLAUDE_QUESTIONS,
    requestedSchema: {
      ...schema,
      properties: { ...schema.properties, ...properties },
    } as QuestionForm['requestedSchema'],
  });

  // A field of another kind.
  expect(questionsIn(extra({ count: { type: 'integer' } }))).toBeUndefined();
  // An own answer whose question is not there.
  expect(
    questionsIn(
      extra({ question_9_custom: { type: 'string', title: 'Other' } }),
    ),
  ).toBeUndefined();

  // A codex note for a question it does not ask.
  const codex = CODEX_QUESTIONS.requestedSchema;

  expect(
    questionsIn({
      ...CODEX_QUESTIONS,
      requestedSchema: {
        ...codex,
        properties: {
          ...codex.properties,
          lost_note: {
            type: 'string',
            _meta: { codex: { questionId: 'lost', role: 'user_note' } },
          },
        },
      } as QuestionForm['requestedSchema'],
    }),
  ).toBeUndefined();
  // factory-droid's form under another message.
  expect(
    questionsIn({ ...DROID_QUESTIONS, message: 'Answer these.' }),
  ).toBeUndefined();
});

test('a second own answer for one question, or options as a plain enum, get no questions', () => {
  const withFields = (
    form: QuestionForm,
    properties: Record<string, unknown>,
  ): QuestionForm => ({
    ...form,
    requestedSchema: {
      ...form.requestedSchema,
      properties: { ...form.requestedSchema.properties, ...properties },
    } as QuestionForm['requestedSchema'],
  });

  // codex: two notes for `next`.
  expect(
    questionsIn(
      withFields(CODEX_QUESTIONS, {
        next_note1: {
          type: 'string',
          _meta: { codex: { questionId: 'next', role: 'user_note' } },
        },
      }),
    ),
  ).toBeUndefined();
  // dimcode: two custom answers for `deploy`.
  expect(
    questionsIn(
      withFields(DIMCODE_QUESTIONS, {
        __custom_1: {
          type: 'string',
          _meta: { lody: { elicitation: { customAnswerFor: 'deploy' } } },
        },
      }),
    ),
  ).toBeUndefined();
  // codex and factory-droid: options as an `enum`, not `oneOf`.
  expect(
    questionsIn(
      withFields(CODEX_QUESTIONS, {
        size: {
          type: 'string',
          title: 'How big?',
          enum: ['small', 'large'],
          _meta: { codex: { isOther: false, isSecret: false } },
        },
      }),
    ),
  ).toBeUndefined();
  expect(
    questionsIn(
      withFields(DROID_QUESTIONS, {
        question_3: {
          type: 'string',
          title: 'Size',
          description: 'How big?',
          enum: ['option_0', 'option_1'],
        },
      }),
    ),
  ).toBeUndefined();
});

describe('CHD-1 tester: conservative question enrichment', () => {
  const forms = [
    CLAUDE_QUESTIONS,
    CLAUDE_QUESTION,
    CODEX_QUESTIONS,
    DROID_QUESTIONS,
    OPENCODE_QUESTIONS,
    DIMCODE_QUESTIONS,
  ];
  const freeze = (value: unknown): void => {
    if (value !== null && typeof value === 'object') {
      Object.values(value).forEach(freeze);
      Object.freeze(value);
    }
  };

  test('frozen requests keep every original field and metadata key, and enrichment is idempotent', () => {
    for (const fixture of forms) {
      const form = structuredClone(fixture);

      form._meta = {
        ...form._meta,
        untouched: { list: ['keep', 'these'] },
        [FILLED]: ['existing'],
      };

      const original = structuredClone(form);

      freeze(form);

      const result = asked(form);
      const meta = result._meta as Record<string, unknown>;
      const questions = meta[QUESTIONS] as Questions;
      const represented = questions.questions.flatMap((question) => [
        question.id,
        ...(question.own === undefined ? [] : [question.own.field]),
      ]);

      expect(form).toStrictEqual(original);
      expect(new Set(represented).size).toBe(represented.length);
      expect([...represented].sort()).toStrictEqual(
        Object.keys(form.requestedSchema.properties ?? {}).sort(),
      );
      expect(result.requestedSchema).toStrictEqual(form.requestedSchema);
      expect(meta.untouched).toStrictEqual({ list: ['keep', 'these'] });
      expect(meta[FILLED]).toStrictEqual(['existing', QUESTIONS]);
      expect(
        enricherRelay(ENRICHERS).fromAgent({
          jsonrpc: '2.0',
          id: 'again',
          method: 'elicitation/create',
          params: result,
        }),
      ).toStrictEqual([
        {
          jsonrpc: '2.0',
          id: 'again',
          method: 'elicitation/create',
          params: result,
        },
      ]);
    }
  });

  test('one unsupported field leaves the whole original request available to the generic form', () => {
    for (const fixture of forms) {
      for (const extra of [
        { type: 'integer', minimum: 1 },
        { type: 'string', enum: ['small', 'large'] },
        { type: 'array', items: { type: 'string', enum: ['one', 'two'] } },
      ]) {
        const form = structuredClone(fixture);

        form.requestedSchema.properties!.extra = extra;
        form.requestedSchema.required = [
          ...(form.requestedSchema.required ?? []),
          'extra',
        ];

        freeze(form);
        expect(asked(form)).toStrictEqual({ ...form, sessionId: SESSION });
      }
    }
  });

  test('malformed choices and own answers fall back without dropping any fields', () => {
    for (const fixture of forms) {
      const id = Object.keys(fixture.requestedSchema.properties ?? {})[0];

      assert(id !== undefined);

      for (const options of [[], [{ const: 7, title: 'Seven' }]]) {
        const form = structuredClone(fixture);
        const property: Record<string, unknown> | undefined =
          form.requestedSchema.properties![id];

        assert(property !== undefined);
        Object.assign(property, { type: 'string', oneOf: options });
        freeze(form);
        expect(asked(form)).toStrictEqual({ ...form, sessionId: SESSION });
      }

      const own = structuredClone(fixture);
      const ownId = Object.keys(own.requestedSchema.properties ?? {}).find(
        (key) => /(?:_custom|_note|_other)$|^__custom_/.test(key),
      );

      assert(ownId !== undefined);
      Object.assign(own.requestedSchema.properties![ownId]!, {
        type: 'integer',
      });
      freeze(own);
      expect(asked(own)).toStrictEqual({ ...own, sessionId: SESSION });
    }
  });

  test('codex note pairing follows questionId even when the note precedes its text question', () => {
    const form = structuredClone(CODEX_QUESTIONS);
    const properties = form.requestedSchema.properties;

    form.requestedSchema.properties = {
      token_note: {
        type: 'string',
        title: 'Token note',
        _meta: { codex: { role: 'user_note', questionId: 'token' } },
      },
      ...properties,
    };

    const questions = questionsIn(form);

    expect(questions?.questions.map((question) => question.id)).toStrictEqual([
      'next',
      'token',
    ]);
    expect(questions?.questions[1]?.own).toStrictEqual({
      field: 'token_note',
      mode: 'beside',
      placeholder: 'Token note',
    });
    expect(questions?.questions[1]?.secret).toBe(true);
  });
});

describe('CHD-377 tester: wrapped MCP enrichment boundaries', () => {
  test('an update alone retains raw input and metadata, and enriching twice is idempotent', () => {
    const { update } = relayOn([codexMcpCall]);
    const rawInput = Object.freeze({
      server: 'chord-2',
      tool: 'send_message',
      arguments: Object.freeze({ to: 'reviewer', text: 'ready' }),
    });
    const sent: SessionUpdate = {
      sessionUpdate: 'tool_call_update',
      toolCallId: 'late-args',
      rawInput,
      _meta: {
        is_mcp_tool_call: true,
        [FILLED]: ['existing'],
        untouched: { keep: true },
      },
    };
    const original = structuredClone(sent);
    const [enriched] = updates(update(sent));

    assert(enriched?.sessionUpdate === 'tool_call_update');
    expect(sent).toEqual(original);
    expect(enriched.rawInput).toBe(rawInput);
    expect(enriched._meta).toEqual({
      is_mcp_tool_call: true,
      [FILLED]: ['existing', MCP_CALL],
      untouched: { keep: true },
      [MCP_CALL]: {
        server: 'chord-2',
        tool: 'send_message',
        arguments: rawInput.arguments,
      },
    });
    expect(updates(update(enriched))).toEqual([enriched]);
  });

  test('missing server or tool and unmarked wrappers remain unfilled', () => {
    const { update } = relayOn([codexMcpCall]);

    for (const rawInput of [
      undefined,
      { server: 'chord-2', tool: 7, arguments: {} },
      { tool: 'send_message' },
    ]) {
      const sent: SessionUpdate = {
        sessionUpdate: 'tool_call_update',
        toolCallId: 'guard',
        rawInput,
        _meta: { is_mcp_tool_call: true },
      };

      expect(updates(update(sent))).toEqual([sent]);
    }

    for (const marked of [false, 'true', undefined]) {
      const sent: SessionUpdate = {
        sessionUpdate: 'tool_call_update',
        toolCallId: 'guard',
        rawInput: { server: 'chord-2', tool: 'send_message', arguments: {} },
        _meta: { is_mcp_tool_call: marked },
      };

      expect(updates(update(sent))).toEqual([sent]);
    }
  });
});

describe('CHD-419 tester: optional wrapper arguments and replay', () => {
  test('missing, null and empty arguments retain their wire shape through replay', () => {
    for (const extra of [{}, { arguments: null }, { arguments: {} }]) {
      const { update } = relayOn([codexMcpCall]);

      const rawInput = Object.freeze({
        server: 'my.notes',
        tool: 'notes.v2',
        ...extra,
      });
      const sent: SessionUpdate = {
        sessionUpdate: 'tool_call_update',
        toolCallId: 'optional',
        rawInput,
        _meta: { is_mcp_tool_call: true },
      };
      const [enriched] = updates(update(sent));

      assert(enriched?.sessionUpdate === 'tool_call_update');
      expect(enriched.rawInput).toBe(rawInput);
      expect(enriched._meta?.[MCP_CALL]).toEqual({
        server: 'my.notes',
        tool: 'notes.v2',
        arguments: 'arguments' in extra ? extra.arguments : undefined,
      });

      const replay = JSON.parse(JSON.stringify(enriched)) as SessionUpdate;

      expect(updates(update(replay))).toEqual([replay]);
    }
  });

  test('malformed server or tool and an unmarked valid wrapper stay untouched', () => {
    const { update } = relayOn([codexMcpCall]);

    for (const [rawInput, marked] of [
      [{ tool: 'list' }, true],
      [{ server: null, tool: 'list' }, true],
      [{ server: 3, tool: 'list' }, true],
      [{ server: 'notes', tool: null }, true],
      [{ server: 'notes', tool: 'list' }, false],
    ] as const) {
      const sent: SessionUpdate = {
        sessionUpdate: 'tool_call_update',
        toolCallId: 'guard',
        rawInput,
        _meta: { is_mcp_tool_call: marked },
      };

      expect(updates(update(sent))).toEqual([sent]);
    }
  });
});

describe("a result sent only as rawOutput is filled in as the call's content (CHD-440)", () => {
  const { update } = relayOn([rawOutputContent]);
  const done = (
    rawOutput: unknown,
    more: Partial<
      Extract<SessionUpdate, { sessionUpdate: 'tool_call_update' }>
    > = {},
  ) =>
    updates(
      update({
        sessionUpdate: 'tool_call_update',
        toolCallId: 'call-1',
        status: 'completed',
        rawOutput,
        ...more,
      }),
    )[0] as
      Extract<SessionUpdate, { sessionUpdate: 'tool_call_update' }> | undefined;
  const text = (said: string) => [
    {
      type: 'content' as const,
      content: { type: 'text' as const, text: said },
    },
  ];

  test('a string is its text', () => {
    expect(done('built in 3s\n')).toStrictEqual({
      sessionUpdate: 'tool_call_update',
      toolCallId: 'call-1',
      status: 'completed',
      rawOutput: 'built in 3s\n',
      content: text('built in 3s\n'),
      _meta: { [FILLED]: ['content'] },
    });
  });

  test("cursor's shell: stdout then stderr; a non-zero exitCode fails the call", () => {
    const shell = { exitCode: 0, stdout: 'ok 1\nok 2\n', stderr: 'warn\n' };

    expect(done(shell)).toMatchObject({
      status: 'completed',
      content: text('ok 1\nok 2\nwarn'),
      _meta: { [FILLED]: ['content'] },
    });
    expect(done({ ...shell, exitCode: 2 })).toMatchObject({
      status: 'failed',
      content: text('ok 1\nok 2\nwarn'),
      _meta: { [FILLED]: ['content', 'status'] },
    });
    // Nothing printed, yet failed: the status alone.
    expect(done({ exitCode: 1, stdout: '', stderr: '' })).toStrictEqual({
      sessionUpdate: 'tool_call_update',
      toolCallId: 'call-1',
      status: 'failed',
      rawOutput: { exitCode: 1, stdout: '', stderr: '' },
      _meta: { [FILLED]: ['status'] },
    });
  });

  test("auggie's output and bob's result are their text; any other object its JSON", () => {
    expect(done({ output: 'file text' })?.content).toStrictEqual(
      text('file text'),
    );
    expect(done({ result: 'done' })?.content).toStrictEqual(text('done'));
    expect(done({ files: ['a.ts'], count: 1 })?.content).toStrictEqual(
      text('{\n  "files": [\n    "a.ts"\n  ],\n  "count": 1\n}'),
    );
    expect(done([1, 2])?.content).toStrictEqual(text('[\n  1,\n  2\n]'));
  });

  test('a running call is filled too, so its output shows as it comes', () => {
    expect(done('line 1', { status: 'in_progress' })?.content).toStrictEqual(
      text('line 1'),
    );
  });

  test('content the agent sent stays, and a call with no rawOutput passes as it came', () => {
    const own: SessionUpdate = {
      sessionUpdate: 'tool_call_update',
      toolCallId: 'call-1',
      status: 'completed',
      content: text('its own'),
      rawOutput: { stdout: 'other' },
    } as SessionUpdate;
    const bare: SessionUpdate = {
      sessionUpdate: 'tool_call_update',
      toolCallId: 'call-1',
      status: 'completed',
    };

    expect(updates(update(own))).toStrictEqual([own]);
    expect(updates(update(bare))).toStrictEqual([bare]);
    expect(done('')).toStrictEqual({
      sessionUpdate: 'tool_call_update',
      toolCallId: 'call-1',
      status: 'completed',
      rawOutput: '',
    });
  });

  test('content the agent sent earlier stays when a later update brings only rawOutput, through the whole chain and the transcript', () => {
    const chain = relayOn(ENRICHERS);
    const sent: SessionUpdate[] = [
      {
        sessionUpdate: 'tool_call',
        toolCallId: 'call-2',
        title: 'Run npm test',
        kind: 'execute',
        status: 'in_progress',
        content: text('its own'),
      },
      {
        sessionUpdate: 'tool_call_update',
        toolCallId: 'call-2',
        status: 'completed',
        rawOutput: 'raw',
      },
    ];
    const read = sent.flatMap((each) => updates(chain.update(each)));
    const transcript = read.reduce(
      (state, update) =>
        reduceTranscript(state, {
          type: 'update',
          turnId: 't1',
          at: 1,
          update,
        }),
      emptyTranscript,
    );
    const call = transcript.entries.find((entry) => entry.kind === 'tool');

    // Its title and kind carried on, as `toolCallFacts` does; no content.
    expect(read[1]).toMatchObject({ rawOutput: 'raw', status: 'completed' });
    expect('content' in read[1]!).toBe(false);
    assert(call?.kind === 'tool');
    expect(call.call.content).toStrictEqual(text('its own'));

    // Content the agent clears is its own word too: then rawOutput fills it.
    const cleared = updates(
      chain.update({
        sessionUpdate: 'tool_call_update',
        toolCallId: 'call-2',
        content: [],
      }),
    );
    const after = updates(
      chain.update({
        sessionUpdate: 'tool_call_update',
        toolCallId: 'call-2',
        status: 'completed',
        rawOutput: 'raw',
      }),
    )[0] as Extract<SessionUpdate, { sessionUpdate: 'tool_call_update' }>;

    expect(cleared).toHaveLength(1);
    expect(after.content).toStrictEqual(text('raw'));
  });

  test('a clear sent with rawOutput in one update is the agent clearing too, so a newer rawOutput fills again', () => {
    const chain = relayOn(ENRICHERS);
    const content = (each: SessionUpdate) =>
      (updates(chain.update(each))[0] as { content?: unknown }).content;

    content({
      sessionUpdate: 'tool_call',
      toolCallId: 'call-3',
      title: 'Run npm test',
      kind: 'execute',
      status: 'in_progress',
      content: text('its own'),
    });

    expect(
      content({
        sessionUpdate: 'tool_call_update',
        toolCallId: 'call-3',
        content: [],
        rawOutput: 'first',
      }),
    ).toStrictEqual(text('first'));
    expect(
      content({
        sessionUpdate: 'tool_call_update',
        toolCallId: 'call-3',
        status: 'completed',
        rawOutput: 'second',
      }),
    ).toStrictEqual(text('second'));
  });

  test('it runs in the chain every session gets', () => {
    expect(ENRICHERS).toContain(rawOutputContent);
  });
});
