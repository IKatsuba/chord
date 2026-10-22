import { describe, expect, test } from 'bun:test';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import {
  Conversation,
  type ConversationEvent,
} from '../../src/session/conversation.ts';
import { PlanBridge, planResponse } from '../../src/session/plan_asks.ts';
import { openSession } from '../../src/session/session.ts';
import type { PlanWait } from '../../src/session/transcript/types.ts';
import { fakeAgentCommand } from '../fixtures/fake.ts';

test("the person's answer in each agent's words, a note only with keep; anything not theirs is cancelled (CHD-437, CHD-457)", () => {
  expect(planResponse('cursor', { type: 'accepted' })).toStrictEqual({
    outcome: 'accepted',
  });
  expect(
    planResponse('cursor', { type: 'kept', note: 'Keep it small.' }),
  ).toStrictEqual({ outcome: 'rejected', reason: 'Keep it small.' });
  expect(planResponse('cursor', { type: 'kept' })).toStrictEqual({
    outcome: 'rejected',
  });
  expect(planResponse('grok', { type: 'accepted' })).toStrictEqual({
    outcome: 'approved',
  });
  expect(
    planResponse('grok', { type: 'kept', note: 'More tests.' }),
  ).toStrictEqual({ outcome: 'revise', feedback: 'More tests.' });
  expect(planResponse('grok', { type: 'left' })).toStrictEqual({
    outcome: 'abandoned',
  });

  for (const agent of ['cursor', 'grok'] as const) {
    for (const type of ['cancelled', 'withdrawn'] as const) {
      expect(planResponse(agent, { type })).toStrictEqual({
        outcome: 'cancelled',
      });
    }
  }

  // cursor has no way out of planning but a no; its box never offers it.
  expect(planResponse('cursor', { type: 'left' })).toStrictEqual({
    outcome: 'cancelled',
  });
});

describe('the bridge answers cancelled for every answer that is not the person’s', () => {
  const request = {
    agent: 'cursor',
    toolCallId: 'c',
    plan: '# Route',
    todos: [],
  } as const;

  test('a request that did not read, or nobody to ask', async () => {
    const bridge = new PlanBridge();

    expect(
      await bridge.handler(undefined, new AbortController().signal),
    ).toStrictEqual({ outcome: 'cancelled' });
    expect(
      await bridge.handler(request, new AbortController().signal),
    ).toStrictEqual({ outcome: 'cancelled' });
  });

  test('a withdrawn request, and one waiting when the session closes', async () => {
    const bridge = new PlanBridge();
    const waits: PlanWait[] = [];

    bridge.subscribe((pending) => waits.push(pending.wait));

    const withdraw = new AbortController();
    const withdrawn = bridge.handler(request, withdraw.signal);

    withdraw.abort();
    expect(await withdrawn).toStrictEqual({ outcome: 'cancelled' });

    const closed = bridge.handler(request, new AbortController().signal);

    bridge.close();
    expect(await closed).toStrictEqual({ outcome: 'cancelled' });
    expect(
      waits.map(({ agent, toolCallId }) => [agent, toolCallId]),
    ).toStrictEqual([
      ['cursor', 'c'],
      ['cursor', 'c'],
    ]);
  });
});

/** A conversation with the fake agent, up, in a directory of its own. */
async function withAgent(
  body: (
    conversation: Conversation,
    events: ConversationEvent[],
  ) => Promise<void>,
): Promise<void> {
  const dir = await mkdtemp(join(tmpdir(), 'chord-plan-'));
  const events: ConversationEvent[] = [];
  const conversation = new Conversation(
    (signal) =>
      openSession({
        agent: 'fake',
        cwd: dir,
        agentCommand: fakeAgentCommand(),
        signal,
      }),
    (event) => events.push(event),
    Date.now,
  );

  try {
    conversation.start();
    await until(() => events.some((event) => event.type === 'connected'));
    await body(conversation, events);
  } finally {
    await conversation.close();
    await rm(dir, { recursive: true });
  }
}

async function until(condition: () => boolean): Promise<void> {
  const by = Date.now() + 10_000;

  while (!condition()) {
    if (Date.now() > by) {
      throw new Error('timed out');
    }

    await new Promise((resolve) => setTimeout(resolve, 10));
  }
}

/** The plans put to the person, as the window heard them. */
const asked = (events: readonly ConversationEvent[]) =>
  events.flatMap((event) =>
    event.type === 'plan_requested' ? [event.plan] : [],
  );

/** What the agent said it was answered, once it has said. */
const heard = (events: readonly ConversationEvent[]) =>
  events
    .flatMap((event) =>
      event.type === 'update' &&
      event.update.sessionUpdate === 'agent_message_chunk' &&
      event.update.content.type === 'text'
        ? [event.update.content.text]
        : [],
    )
    .join('')
    .match(/Plan answer: (.*)$/)?.[1];

describe('a plan through the session layer, on the fake (CHD-437, CHD-457)', () => {
  for (const [scenario, answer, outcome] of [
    ['cursorplan', { type: 'accepted' }, { outcome: 'accepted' }],
    [
      'cursorplan',
      { type: 'kept', note: 'Keep it small.' },
      { outcome: 'rejected', reason: 'Keep it small.' },
    ],
    ['grokplan', { type: 'accepted' }, { outcome: 'approved' }],
    [
      'grokplan',
      { type: 'kept', note: 'More tests.' },
      { outcome: 'revise', feedback: 'More tests.' },
    ],
    ['grokplan', { type: 'left' }, { outcome: 'abandoned' }],
  ] as const) {
    test(`${scenario}: ${JSON.stringify(answer)} reaches the agent as ${JSON.stringify(outcome)}`, () =>
      withAgent(async (conversation, events) => {
        conversation.send(scenario);
        await until(() => asked(events).length === 1);

        const [plan] = asked(events);

        conversation.answerPlan(plan!.id, answer);
        await until(() => heard(events) !== undefined);
        expect(JSON.parse(heard(events)!)).toStrictEqual(outcome);
        expect(
          events.findLast((event) => event.type === 'plan_settled'),
        ).toMatchObject({ id: plan!.id, answer });
      }));
  }

  test("cursor's plan comes whole, its todos and phases; grok's with no plan says none", () =>
    withAgent(async (conversation, events) => {
      conversation.send('cursorplan');
      await until(() => asked(events).length === 1);

      expect(asked(events)[0]).toMatchObject({
        agent: 'cursor',
        name: 'Route updates by session',
        overview: 'Split the session routing out of the connection.',
        todos: [
          { id: 'read', status: 'completed' },
          { id: 'move', status: 'in_progress' },
          { id: 'test', status: 'pending' },
        ],
        phases: [{ name: 'Move', todos: [{ id: 'move' }, { id: 'test' }] }],
      });
      conversation.answerPlan(asked(events)[0]!.id, { type: 'cancelled' });
      await until(() => heard(events) !== undefined);

      conversation.send('grokplanempty');
      await until(() => asked(events).length === 2);
      expect(asked(events)[1]).toStrictEqual({
        id: asked(events)[1]!.id,
        agent: 'grok',
        toolCallId: asked(events)[1]!.toolCallId,
      });
    }));

  test('the person interrupting the turn answers it cancelled, never a yes', () =>
    withAgent(async (conversation, events) => {
      conversation.send('grokplan');
      await until(() => asked(events).length === 1);
      conversation.interrupt();
      await until(() =>
        events.some(
          (event) =>
            event.type === 'plan_settled' && event.answer.type === 'cancelled',
        ),
      );
      // The turn it was cut from never says; the next one tells what came.
      await until(() =>
        events.some(
          (event) =>
            event.type === 'result' && event.result.status === 'cancelled',
        ),
      );
      conversation.send('planheard');
      await until(() => heard(events) !== undefined);
      expect(JSON.parse(heard(events)!)).toStrictEqual({
        outcome: 'cancelled',
      });
    }));

  for (const scenario of ['cursorplanbad', 'cursorplanearly']) {
    test(`${scenario}: answered cancelled at once, never put to the person (Q95)`, () =>
      withAgent(async (conversation, events) => {
        conversation.send(scenario);
        await until(() => heard(events) !== undefined);
        expect(JSON.parse(heard(events)!)).toStrictEqual({
          outcome: 'cancelled',
        });
        expect(asked(events)).toStrictEqual([]);
      }));
  }

  test('one waiting when the conversation closes is withdrawn, the agent never told a yes', () =>
    withAgent(async (conversation, events) => {
      conversation.send('cursorplan');
      await until(() => asked(events).length === 1);
      await conversation.close();
      expect(
        events.findLast((event) => event.type === 'plan_settled'),
      ).toMatchObject({ answer: { type: 'withdrawn' } });
      // The agent had no answer it could say: none but cancelled was sent.
      expect(heard(events)).toBe(undefined);
    }));
});
