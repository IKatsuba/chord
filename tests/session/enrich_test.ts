import type { SessionUpdate } from '@agentclientprotocol/sdk';
import { expect, test } from 'bun:test';
import { EMPTY_WIRE, recalled } from '../../src/session/enrich.ts';

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
