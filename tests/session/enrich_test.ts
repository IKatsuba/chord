import type { SessionUpdate } from '@agentclientprotocol/sdk';
import { describe, expect, test } from 'bun:test';
import {
  EMPTY_WIRE,
  enricherRelay,
  FILLED,
  notificationOf,
  type Wire,
  heardFromAgent,
  recalled,
  updateMessage,
} from '../../src/session/enrich.ts';
import { ENRICHERS } from '../../src/session/enrichers.ts';

/** A past with tool calls, their updates, chord's filled content and text. */
function pastOf(calls: number): SessionUpdate[] {
  return Array.from({ length: calls }, (_, at): SessionUpdate[] => [
    {
      sessionUpdate: 'agent_message_chunk',
      content: { type: 'text', text: `before ${at}` },
    },
    {
      sessionUpdate: 'tool_call',
      toolCallId: `call-${at}`,
      title: `Read ${at}.ts`,
      kind: 'read',
      status: 'pending',
    },
    {
      sessionUpdate: 'tool_call_update',
      toolCallId: `call-${at}`,
      status: 'completed',
      content: [
        { type: 'content', content: { type: 'text', text: `out ${at}` } },
      ],
      // Every third call's content is chord's, not the agent's.
      ...(at % 3 === 0 ? { _meta: { 'chord/filled': ['content'] } } : {}),
    },
    {
      sessionUpdate: 'tool_call_update',
      toolCallId: `call-${at}`,
      ...(at % 2 === 0 ? { title: `Read ${at}.ts again` } : {}),
    },
    {
      sessionUpdate: 'usage_update',
      used: at * 10,
      size: 1000,
      cost: { amount: at / 100, currency: 'USD' },
    },
  ]).flat();
}

test("a recalled past folds each tool call's facts as hearing it an update at a time does (CHD-559)", () => {
  const past = pastOf(50);
  const whole = recalled(EMPTY_WIRE, 'session', past, { inputTokens: 7 });
  const stepwise = past.reduce(
    (wire, update) => recalled(wire, 'session', [update]),
    EMPTY_WIRE,
  );

  expect(whole).toStrictEqual(
    recalled(stepwise, 'session', [], { inputTokens: 7 }),
  );
  expect(whole.sessions['session']?.tools['call-0']).toStrictEqual({
    title: 'Read 0.ts again',
    kind: 'read',
    ownContent: false,
  });
  expect(whole.sessions['session']?.tools['call-1']).toStrictEqual({
    title: 'Read 1.ts',
    kind: 'read',
    ownContent: true,
  });
  expect(Object.keys(whole.sessions['session']?.tools ?? {})).toHaveLength(50);
  expect(whole.sessions['session']?.usage).toStrictEqual({
    used: 490,
    size: 1000,
  });
});

test('recalling a past leaves the wire it was given as it was (CHD-559)', () => {
  const before = recalled(EMPTY_WIRE, 'session', pastOf(2));
  const tools = { ...before.sessions['session']!.tools };

  recalled(before, 'session', pastOf(5));
  expect(before.sessions['session']!.tools).toStrictEqual(tools);
});

test('a long past is recalled in linear time (CHD-559)', () => {
  const past = pastOf(20_000);
  const started = performance.now();

  recalled(EMPTY_WIRE, 'session', past);
  // Quadratic, 20,000 calls took seconds; linear, well under one.
  expect(performance.now() - started).toBeLessThan(1_000);
});

test('a recalled past keeps every tool call id as its own entry, as hearing it live does, reserved names too (CHD-559)', () => {
  const past = ['__proto__', 'constructor', 'toString', 'call-1'].flatMap(
    (id): SessionUpdate[] => [
      {
        sessionUpdate: 'tool_call',
        toolCallId: id,
        title: `Run ${id}`,
        kind: 'execute',
        status: 'pending',
      },
      {
        sessionUpdate: 'tool_call_update',
        toolCallId: id,
        status: 'completed',
        content: [{ type: 'content', content: { type: 'text', text: id } }],
      },
    ],
  );
  const live = past.reduce(
    (wire, update) => heardFromAgent(wire, updateMessage('session', update)),
    EMPTY_WIRE,
  );
  const tools = recalled(EMPTY_WIRE, 'session', past).sessions['session']!
    .tools;
  const heard = live.sessions['session']!.tools;

  expect(Object.getPrototypeOf(tools)).toBe(Object.getPrototypeOf(heard));
  expect(Object.keys(tools)).toStrictEqual(Object.keys(heard));
  expect(Object.keys(tools)).toContain('__proto__');

  for (const id of Object.keys(heard)) {
    expect(Object.getOwnPropertyDescriptor(tools, id)).toStrictEqual(
      Object.getOwnPropertyDescriptor(heard, id),
    );
  }
});

describe('CHD-559 tester: independent live replay and session isolation', () => {
  const live = (wire: Wire, id: string, past: readonly SessionUpdate[]) =>
    past.reduce(
      (state, update) => heardFromAgent(state, updateMessage(id, update)),
      wire,
    );
  const content = (text: string) => [
    { type: 'content' as const, content: { type: 'text' as const, text } },
  ];

  test('mixed updates retain tool ownership, agent state, usage and key order as live traffic does', () => {
    const past: SessionUpdate[] = [
      {
        sessionUpdate: 'available_commands_update',
        availableCommands: [{ name: 'greet', description: 'Fixture command' }],
      },
      {
        sessionUpdate: 'config_option_update',
        configOptions: [
          {
            id: 'effort',
            name: 'Effort',
            type: 'select',
            currentValue: 'high',
            options: [{ value: 'high', name: 'High' }],
          },
        ],
      },
      {
        sessionUpdate: 'tool_call_update',
        toolCallId: '01',
        title: 'Before its call',
        content: content('agent original'),
      },
      {
        sessionUpdate: 'tool_call',
        toolCallId: '2',
        title: 'Second',
        kind: 'execute',
      },
      {
        sessionUpdate: 'tool_call',
        toolCallId: '__proto__',
        title: 'Reserved',
        kind: 'read',
      },
      { sessionUpdate: 'tool_call', toolCallId: '01', title: 'Repeated call' },
      {
        sessionUpdate: 'usage_update',
        used: 10,
        size: 100,
        cost: { amount: 0.2, currency: 'USD' },
        _meta: { [FILLED]: ['cost', 'size'] },
      },
      {
        sessionUpdate: 'tool_call_update',
        toolCallId: '01',
        content: content('generated'),
        _meta: { [FILLED]: ['content'] },
      },
      {
        sessionUpdate: 'tool_call_update',
        toolCallId: '__proto__',
        content: [],
      },
      {
        sessionUpdate: 'usage_update',
        used: 999,
        size: 9999,
        cost: { amount: 0.7, currency: 'USD' },
        _meta: { [FILLED]: ['used', 'cost'] },
      },
      {
        sessionUpdate: 'tool_call_update',
        toolCallId: '01',
        status: 'completed',
      },
      {
        sessionUpdate: 'usage_update',
        used: 12,
        size: 500,
        cost: { amount: 0, currency: 'USD' },
      },
    ];
    const encoded = JSON.stringify(past);
    const replay = recalled(EMPTY_WIRE, 'a', past);
    const heard = live(EMPTY_WIRE, 'a', past);
    const session = replay.sessions['a']!;

    expect(replay).toStrictEqual(heard);
    expect(Object.keys(session.tools)).toEqual(
      Object.keys(heard.sessions['a']!.tools),
    );
    expect(session.tools['01']).toEqual({
      title: 'Repeated call',
      ownContent: false,
    });
    expect(session.tools['__proto__']?.ownContent).toBe(false);
    expect(session.usage).toEqual({ used: 12, size: 500 });
    expect(session.estimate).toBe(0.7);
    expect(session.agentCost).toBe(true);
    expect(session.agent.configOptions[0]?.currentValue).toBe('high');
    expect(JSON.stringify(past)).toBe(encoded);
  });

  test('repeated recalls clone frozen input without crossing session or request boundaries', () => {
    const first = live(EMPTY_WIRE, 'a', [
      {
        sessionUpdate: 'tool_call',
        toolCallId: 'shared',
        title: 'A',
        kind: 'read',
        content: content('A content'),
      },
    ]);
    const both = live(first, 'b', [
      {
        sessionUpdate: 'tool_call',
        toolCallId: 'shared',
        title: 'B',
        kind: 'execute',
      },
    ]);
    const seed: Wire = Object.freeze({
      ...both,
      totals: true,
      asked: Object.freeze({
        pending: { method: 'session/prompt', params: { sessionId: 'a' } },
      }),
      sessions: Object.freeze({
        ...both.sessions,
        a: Object.freeze({
          ...both.sessions['a']!,
          total: { inputTokens: 17 },
        }),
      }),
    });

    for (const session of Object.values(seed.sessions)) {
      for (const facts of Object.values(session.tools)) {
        Object.freeze(facts);
      }

      Object.freeze(session.tools);
      Object.freeze(session);
    }

    const original = JSON.stringify(seed);
    const past: SessionUpdate[] = [
      {
        sessionUpdate: 'tool_call_update',
        toolCallId: 'shared',
        title: 'A resumed',
      },
    ];
    const a = recalled(seed, 'a', past);
    const b = recalled(
      a,
      'b',
      [
        {
          sessionUpdate: 'tool_call_update',
          toolCallId: 'shared',
          title: 'B resumed',
        },
      ],
      { inputTokens: 31 },
    );

    expect(a).toStrictEqual(live(seed, 'a', past));
    expect(a.asked).toBe(seed.asked);
    expect(a.sessions['b']).toBe(seed.sessions['b']);
    expect(a.sessions['a']?.tools).not.toBe(seed.sessions['a']?.tools);
    expect(a.sessions['a']?.total).toEqual({ inputTokens: 17 });
    expect(b.sessions['a']).toBe(a.sessions['a']);
    expect(b.sessions['b']?.tools['shared']?.title).toBe('B resumed');
    expect(a.sessions['b']?.tools['shared']?.title).toBe('B');
    expect(b.sessions['b']?.total).toEqual({ inputTokens: 31 });
    expect(recalled(b, 'a', [])).toStrictEqual(b);
    expect(JSON.stringify(seed)).toBe(original);
  });

  test('real enrichers handle late raw output identically after live traffic or recall', () => {
    const heard = enricherRelay(ENRICHERS);
    const replay = enricherRelay(ENRICHERS);

    for (const [id, own] of [
      ['a', true],
      ['b', false],
    ] as const) {
      const recorded = heard
        .fromAgent(
          updateMessage(id, {
            sessionUpdate: 'tool_call',
            toolCallId: '__proto__',
            title: `Run ${id}`,
            kind: 'execute',
            ...(own
              ? { content: content('agent content') }
              : { rawOutput: 'initial fallback' }),
          }),
        )
        .flatMap((message) => {
          const notification = notificationOf(message);

          return notification ? [notification.update] : [];
        });

      replay.recall(id, recorded);
    }

    for (const id of ['b', 'a', 'b']) {
      const message = updateMessage(id, {
        sessionUpdate: 'tool_call_update',
        toolCallId: '__proto__',
        status: 'completed',
        rawOutput: `late ${id}`,
      });
      const expected = heard.fromAgent(message);
      const actual = replay.fromAgent(message);

      expect(actual).toStrictEqual(expected);

      const update = notificationOf(actual[0]!)?.update;

      if (id === 'a') {
        expect(update).not.toHaveProperty('content');
      } else {
        expect(update).toHaveProperty('content', content('late b'));
      }
    }
  });
});
