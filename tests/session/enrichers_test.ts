import { expect, test } from 'bun:test';
import assert from 'node:assert/strict';
import type {
  AnyMessage,
  SessionConfigOption,
  SessionUpdate,
} from '@agentclientprotocol/sdk';
import { enricherRelay, FILLED } from '../../src/session/enrich.ts';
import {
  costFromTokens,
  modeReadBack,
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
