import { describe, expect, test } from 'bun:test';
import type {
  ClientCapabilities,
  ContentBlock,
  SessionConfigOption,
  SessionUpdate,
} from '@agentclientprotocol/sdk/unstable';
import type { AgentState } from '../../src/session/agent_state.ts';
import type { PlanWait } from '../../src/session/transcript/types.ts';
import {
  aliasFor,
  answeredConfig,
  childOf,
  configChange,
  configOptionsOf,
  configSetter,
  elicitationReplyOf,
  mapUpdate,
  messageChunk,
  permissionAnswerOf,
  planAnswerOf,
  planPermission,
  promptOf,
  reaches,
  upstreamSession,
} from '../../src/session/upstream.ts';

const NONE: ClientCapabilities = {};
const ALL: ClientCapabilities = {
  subagents: {},
  plan: {},
  session: { compaction: {}, notices: {} },
};

describe('what is not sent', () => {
  const needs: [string, ClientCapabilities][] = [
    ['subagent_update', { subagents: {} }],
    ['session_message', { subagents: {} }],
    ['session_message_chunk', { subagents: {} }],
    ['plan_update', { plan: {} }],
    ['plan_removed', { plan: {} }],
    ['compaction_update', { session: { compaction: {} } }],
    ['compaction_summary_chunk', { session: { compaction: {} } }],
    ['notice', { session: { notices: {} } }],
  ];

  for (const [kind, declared] of needs) {
    test(`${kind} goes only to a client that declares it`, () => {
      expect(reaches(NONE, kind, false)).toBe(false);
      expect(reaches(declared, kind, false)).toBe(true);
    });

    test(`${kind} is not let through by another capability`, () => {
      const others = needs
        .filter(([other]) => other !== kind)
        .map(([, capability]) => capability)
        .filter(
          (capability) =>
            JSON.stringify(capability) !== JSON.stringify(declared),
        );

      for (const other of others) {
        expect(reaches(other, kind, false)).toBe(false);
      }
    });
  }

  for (const kind of [
    'user_message_chunk',
    'agent_message_chunk',
    'agent_thought_chunk',
    'tool_call',
    'tool_call_update',
    'plan',
    'available_commands_update',
    'config_option_update',
    'session_info_update',
    'usage_update',
  ]) {
    test(`${kind} needs nothing declared, and a child's needs subagents`, () => {
      expect(reaches(NONE, kind, false)).toBe(true);
      expect(reaches(NONE, kind, true)).toBe(false);
      expect(reaches({ subagents: {} }, kind, true)).toBe(true);
    });
  }

  test('a kind the v1 schema lacks never goes', () => {
    expect(reaches(ALL, 'never_heard_of', false)).toBe(false);
    expect(reaches(ALL, 'toString', false)).toBe(false);
    expect(reaches(ALL, 'constructor', false)).toBe(false);
    expect(reaches(ALL, '__proto__', false)).toBe(false);
    expect(reaches(ALL, 'current_mode_update', false)).toBe(false);
  });
});

describe('aliases', () => {
  test('a free id stays; a taken one counts up', () => {
    expect(aliasFor(new Set(), 's1')).toBe('s1');
    expect(aliasFor(new Set(['s1']), 's1')).toBe('s1~2');
    expect(aliasFor(new Set(['s1', 's1~2']), 's1')).toBe('s1~3');
  });
});

describe('ids going up', () => {
  const chunk: SessionUpdate = {
    sessionUpdate: 'agent_message_chunk',
    content: { type: 'text', text: 'hi' },
  };
  const announce = (
    id: string,
  ): Extract<SessionUpdate, { sessionUpdate: 'subagent_update' }> => ({
    sessionUpdate: 'subagent_update',
    sessionId: id,
    state: { state: 'running' },
  });

  test('main goes under its upstream id, whole, _meta too', () => {
    const update: SessionUpdate = {
      ...chunk,
      _meta: { 'chord/filled': ['x'] },
    };
    const { notification } = mapUpdate(
      upstreamSession('s1', 's1~2'),
      NONE,
      update,
    );

    expect(notification).toEqual({ sessionId: 's1~2', update });
  });

  test('a child goes under <main>/<child>, its own under <main>/<child>/<id>', () => {
    let session = upstreamSession('s1');

    ({ session } = mapUpdate(session, ALL, announce('c')));

    const nested = mapUpdate(session, ALL, announce('d'), 'c');

    session = nested.session;

    expect(nested.notification).toEqual({
      sessionId: 's1/c',
      update: { ...announce('d'), sessionId: 's1/c/d' },
    });
    expect(mapUpdate(session, ALL, chunk, 'd').notification?.sessionId).toBe(
      's1/c/d',
    );
  });

  test('under an alias the composite takes the alias', () => {
    const { session } = mapUpdate(
      upstreamSession('s1', 's1~2'),
      ALL,
      announce('c'),
    );

    expect(mapUpdate(session, ALL, chunk, 'c').notification?.sessionId).toBe(
      's1~2/c',
    );
  });

  test('a composite is looked up exactly, a slash in an id no matter', () => {
    const { session } = mapUpdate(
      upstreamSession('s1'),
      ALL,
      announce('tool/1'),
    );

    expect(childOf(session, 's1/tool/1')).toBe('tool/1');
    expect(childOf(session, 's1/tool')).toBeUndefined();
    expect(childOf(session, 's1')).toBeUndefined();
  });

  test('a child is known even to a client that never hears of it', () => {
    const { session, notification } = mapUpdate(
      upstreamSession('s1'),
      NONE,
      announce('c'),
    );

    expect(notification).toBeUndefined();
    expect(childOf(session, 's1/c')).toBe('c');
    expect(mapUpdate(session, NONE, chunk, 'c').notification).toBeUndefined();
  });

  test('a message between sessions names them as the client knows them', () => {
    const { session } = mapUpdate(upstreamSession('s1'), ALL, announce('c'));
    const { notification } = mapUpdate(session, ALL, {
      sessionUpdate: 'session_message',
      messageId: 'm',
      senderSessionId: 's1',
      recipientSessionId: 'c',
    });

    expect(notification?.update).toMatchObject({
      senderSessionId: 's1',
      recipientSessionId: 's1/c',
    });
  });
});

describe('subagent state words', () => {
  const table: [string, object][] = [
    ['completed', { state: 'idle', stopReason: 'end_turn' }],
    ['failed', { state: 'idle', stopReason: 'error' }],
    ['cancelled', { state: 'idle', stopReason: 'cancelled' }],
    ['disconnected', { state: 'unknown' }],
  ];

  for (const [word, state] of table) {
    test(`a draft's ${word} goes as ACP's, the word in _meta`, () => {
      const { notification } = mapUpdate(upstreamSession('s1'), ALL, {
        sessionUpdate: 'subagent_update',
        sessionId: 'c',
        state: { state: word },
        _meta: { kept: 1 },
      });

      expect(notification?.update).toMatchObject({
        state,
        _meta: { kept: 1, 'chord/agent': { state: word } },
      });
    });
  }

  for (const word of [
    'running',
    'idle',
    'requires_action',
    'unknown',
    'toString',
    'constructor',
  ]) {
    test(`the word ${word} goes as it is`, () => {
      const { notification } = mapUpdate(upstreamSession('s1'), ALL, {
        sessionUpdate: 'subagent_update',
        sessionId: 'c',
        state: { state: word },
      });

      expect(notification?.update).toEqual({
        sessionUpdate: 'subagent_update',
        sessionId: 's1/c',
        state: { state: word },
      });
    });
  }
});

describe('one shape for configuration', () => {
  const select = (
    id: string,
    category: string | undefined,
    currentValue: string,
    values: readonly string[],
  ): SessionConfigOption => ({
    type: 'select',
    id,
    name: id.toUpperCase(),
    ...(category === undefined ? {} : { category }),
    currentValue,
    options: values.map((value) => ({ value, name: value })),
  });
  const state = (over: Partial<AgentState>): AgentState => ({
    configOptions: [],
    commands: [],
    ...over,
  });
  const legacyModes = {
    currentModeId: 'ask',
    availableModes: [{ id: 'ask', name: 'Ask' }],
  };
  const legacyModels = {
    currentModelId: 'big',
    availableModels: [{ modelId: 'big', name: 'Big' }],
  };

  test('modes the older way become a mode option', () => {
    expect(configOptionsOf(state({ modes: legacyModes }))).toEqual([
      {
        type: 'select',
        id: 'mode',
        name: 'Mode',
        category: 'mode',
        currentValue: 'ask',
        options: [{ value: 'ask', name: 'Ask' }],
      },
    ]);
  });

  test('an agent with only session/set_model shows the same model option', () => {
    expect(configOptionsOf(state({ models: legacyModels }))).toEqual([
      {
        type: 'select',
        id: 'model',
        name: 'Model',
        category: 'model',
        currentValue: 'big',
        options: [{ value: 'big', name: 'Big' }],
      },
    ]);
  });

  test("the agent's own options keep their ids and names", () => {
    const own = state({
      configOptions: [
        select('approvals', 'mode', 'a', ['a', 'b']),
        select('engine', 'model', 'x', ['x']),
        select('effort', undefined, 'low', ['low', 'high']),
      ],
    });

    expect(configOptionsOf(own).map(({ id, name }) => [id, name])).toEqual([
      ['approvals', 'APPROVALS'],
      ['engine', 'ENGINE'],
      ['effort', 'EFFORT'],
    ]);
    expect(configSetter(own, 'approvals')).toBe('mode');
    expect(configSetter(own, 'engine')).toBe('model');
    expect(configSetter(own, 'effort')).toBe('option');
    expect(configSetter(own, 'nothing')).toBeUndefined();
  });

  test('both kinds of agent read alike', () => {
    const made = state({ modes: legacyModes, models: legacyModels });
    const own = state({
      configOptions: [
        {
          type: 'select',
          id: 'mode',
          category: 'mode',
          currentValue: 'ask',
          options: [{ value: 'ask', name: 'Ask' }],
          name: 'Mode',
        },
        {
          type: 'select',
          id: 'model',
          category: 'model',
          currentValue: 'big',
          options: [{ value: 'big', name: 'Big' }],
          name: 'Model',
        },
      ],
    });

    expect(configOptionsOf(own)).toEqual(configOptionsOf(made));
    expect(configSetter(made, 'model')).toBe('model');
  });

  test('what an agent lacks is absent; booleans never appear', () => {
    expect(configOptionsOf(state({}))).toEqual([]);
    expect(
      configOptionsOf(
        state({
          configOptions: [
            { type: 'boolean', id: 'fast', name: 'Fast', currentValue: true },
          ],
        }),
      ),
    ).toEqual([]);
  });

  test("grouped values are flattened in the agent's order", () => {
    const grouped: SessionConfigOption = {
      type: 'select',
      id: 'effort',
      name: 'Effort',
      currentValue: 'b',
      options: [
        { group: 'one', name: 'One', options: [{ value: 'a', name: 'A' }] },
        { group: 'two', name: 'Two', options: [{ value: 'b', name: 'B' }] },
      ],
    };

    expect(
      configOptionsOf(state({ configOptions: [grouped] }))[0],
    ).toMatchObject({
      options: [
        { value: 'a', name: 'A' },
        { value: 'b', name: 'B' },
      ],
    });
  });

  test('an update goes only when the list differs, marked and whole', () => {
    const before = state({ modes: legacyModes });
    const { session } = answeredConfig(upstreamSession('s1', 'up'), before);

    expect(configChange(session, before).notification).toBeUndefined();

    const after = state({
      modes: { ...legacyModes, currentModeId: 'ask', availableModes: [] },
    });
    const changed = configChange(session, after);

    expect(changed.notification).toEqual({
      sessionId: 'up',
      update: {
        sessionUpdate: 'config_option_update',
        configOptions: [],
        _meta: { 'chord/filled': ['configOptions'] },
      },
    });
    expect(configChange(changed.session, after).notification).toBeUndefined();
  });

  test("the agent's own config updates never go as it sent them", () => {
    for (const update of [
      { sessionUpdate: 'current_mode_update', currentModeId: 'x' },
      { sessionUpdate: 'config_option_update', configOptions: [] },
    ] as SessionUpdate[]) {
      expect(
        mapUpdate(upstreamSession('s1'), ALL, update).notification,
      ).toBeUndefined();
    }
  });
});

describe('a plan ask', () => {
  const plan: PlanWait = {
    id: 'p',
    agent: 'cursor',
    toolCallId: 'call',
    name: 'Rewrite',
    overview: 'Why',
    plan: '# How',
    todos: [
      { id: '1', content: 'one', status: 'completed' },
      { id: '2', content: 'two', status: 'pending' },
    ],
    phases: [
      {
        name: 'Later',
        todos: [{ id: '3', content: 'three', status: 'pending' }],
      },
    ],
  };
  const grok: PlanWait = { id: 'g', agent: 'grok', toolCallId: 'call' };
  const selected = (optionId: string) => ({
    outcome: { outcome: 'selected' as const, optionId },
  });

  test('goes as a permission, its plan as markdown', () => {
    expect(planPermission('up', plan)).toEqual({
      sessionId: 'up',
      toolCall: {
        toolCallId: 'call',
        title: 'Rewrite',
        content: [
          {
            type: 'content',
            content: {
              type: 'text',
              text: 'Why\n\n# How\n\n- [x] one\n- [ ] two\n\n## Later\n- [ ] three',
            },
          },
        ],
      },
      options: [
        {
          optionId: 'accepted',
          name: 'Yes, accept the plan',
          kind: 'allow_once',
        },
        { optionId: 'kept', name: 'No, keep planning', kind: 'reject_once' },
      ],
    });
  });

  test("grok's has a third, and a title of its own", () => {
    const request = planPermission('up', grok);

    expect(request.toolCall.title).toBe('Plan');
    expect(
      request.options.map(({ optionId, kind }) => [optionId, kind]),
    ).toEqual([
      ['accepted', 'allow_once'],
      ['kept', 'reject_once'],
      ['left', 'reject_once'],
    ]);
  });

  test('each answer', () => {
    expect(planAnswerOf(plan, selected('accepted'))).toEqual({
      type: 'accepted',
    });
    expect(planAnswerOf(plan, selected('kept'))).toEqual({ type: 'kept' });
    expect(planAnswerOf(grok, selected('left'))).toEqual({ type: 'left' });
  });

  test('a cancel, an error, an unknown id: cancelled, never a yes', () => {
    for (const response of [
      { outcome: { outcome: 'cancelled' as const } },
      undefined,
      selected('nope'),
      selected('left'),
    ]) {
      expect(planAnswerOf(plan, response)).toEqual({ type: 'cancelled' });
    }
  });
});

describe("a permission's answer", () => {
  const options = [
    { optionId: 'yes', name: 'Yes', kind: 'allow_once' as const },
    { optionId: 'no', name: 'No', kind: 'reject_once' as const },
  ];

  test('an offered option is chosen', () => {
    expect(
      permissionAnswerOf(options, {
        outcome: { outcome: 'selected', optionId: 'yes' },
      }),
    ).toEqual({ optionId: 'yes' });
  });

  test('anything else is a refusal', () => {
    expect(
      permissionAnswerOf(options, {
        outcome: { outcome: 'selected', optionId: 'maybe' },
      }),
    ).toBe('reject');
    expect(
      permissionAnswerOf(options, { outcome: { outcome: 'cancelled' } }),
    ).toBe('reject');
    expect(permissionAnswerOf(options, undefined)).toBe('reject');
  });
});

describe("a form's answer", () => {
  test("each of ACP's words passes as it came", () => {
    const accept = { action: 'accept', content: { name: 'x' } };

    expect(elicitationReplyOf(accept)).toEqual(accept as never);
    expect(elicitationReplyOf({ action: 'decline' })).toEqual({
      action: 'decline',
    });
    expect(elicitationReplyOf({ action: 'cancel' })).toEqual({
      action: 'cancel',
    });
  });

  test('an error, or any other word, is cancel', () => {
    expect(elicitationReplyOf(undefined)).toEqual({ action: 'cancel' });
    expect(elicitationReplyOf({ action: 'maybe' })).toEqual({
      action: 'cancel',
    });
  });
});

describe("a prompt's blocks", () => {
  const text = (value: string): ContentBlock => ({ type: 'text', text: value });
  const image: ContentBlock = {
    type: 'image',
    data: 'AAAA',
    mimeType: 'image/png',
  };
  const link: ContentBlock = {
    type: 'resource_link',
    name: 'a.ts',
    uri: 'file:///a.ts',
  };

  test('text joined in order, images and links apart', () => {
    expect(promptOf([text('a'), link, image, text('b')], 'fake', true)).toEqual(
      {
        text: 'a\nb',
        attachments: [{ mediaType: 'image/png', data: 'AAAA' }],
        links: [link],
      },
    );
  });

  test("an image to an agent without them is refused in the window's words", () => {
    expect(promptOf([image], 'fake', false)).toEqual({
      refused: 'fake does not take images',
    });
  });

  test('resource and audio are refused', () => {
    const resource: ContentBlock = {
      type: 'resource',
      resource: { uri: 'file:///a', text: 'x' },
    };
    const audio: ContentBlock = {
      type: 'audio',
      data: 'AAAA',
      mimeType: 'audio/wav',
    };

    expect(promptOf([resource], 'fake', true)).toHaveProperty('refused');
    expect(promptOf([audio], 'fake', true)).toHaveProperty('refused');
  });
});

describe('a message no prompt began', () => {
  test('is a user chunk, marked who from', () => {
    expect(messageChunk('up', 'hi', { name: 'lead' })).toEqual({
      sessionId: 'up',
      update: {
        sessionUpdate: 'user_message_chunk',
        content: { type: 'text', text: 'hi' },
        _meta: { 'chord/from': { name: 'lead' } },
      },
    });
  });
});

describe('CHD-574 tester: mapper session boundaries', () => {
  test('equal child ids stay under separate aliases without changing the input', () => {
    const original = upstreamSession('main', 'first');
    const update: SessionUpdate = {
      sessionUpdate: 'subagent_update',
      sessionId: 'child/opaque',
      state: { state: 'completed' },
      _meta: { kept: 'value' },
    };
    const before = structuredClone(update);
    const first = mapUpdate(original, ALL, update);
    const second = mapUpdate(upstreamSession('main', 'second'), ALL, update);

    expect(first.notification?.update).toMatchObject({
      sessionId: 'first/child/opaque',
      state: { state: 'idle', stopReason: 'end_turn' },
    });
    expect(second.notification?.update).toMatchObject({
      sessionId: 'second/child/opaque',
    });
    expect(original.children.size).toBe(0);
    expect(update).toEqual(before);
  });

  test('one session announcing config does not suppress another session', () => {
    const state: AgentState = { commands: [], configOptions: [] };
    const first = configChange(upstreamSession('same', 'first'), state);
    const second = configChange(upstreamSession('same', 'second'), state);

    expect(first.notification?.sessionId).toBe('first');
    expect(second.notification?.sessionId).toBe('second');
    expect(configChange(first.session, state).notification).toBeUndefined();
  });

  test('a prototype-like option id is accepted only when explicitly offered', () => {
    const selected = {
      outcome: { outcome: 'selected' as const, optionId: 'toString' },
    };

    expect(permissionAnswerOf([], selected)).toBe('reject');
    expect(
      permissionAnswerOf(
        [{ optionId: 'toString', name: 'Allow', kind: 'allow_once' }],
        selected,
      ),
    ).toEqual({ optionId: 'toString' });
  });
});
