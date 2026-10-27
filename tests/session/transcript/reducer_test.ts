import { beforeAll, describe, expect, test } from 'bun:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { openSession } from '../../../src/session/session.ts';
import type {
  Transcript,
  TranscriptAction,
} from '../../../src/session/transcript/types.ts';
import { EDIT_NEW, EDIT_OLD } from '../../fixtures/edits.ts';
import { fakeAgentCommand } from '../../fixtures/fake.ts';
import { MARKDOWN_REPLY } from '../../fixtures/markdown.ts';
import { FX_ERROR_NOTICE } from '../../fixtures/fake_agent/scenarios/fx.ts';
import { withSession } from '../session_fake.ts';
import { play, type PlayOptions } from '../../fixtures/recorder.ts';
import { fold, states } from './fold.ts';

describe('CHD-534 synthetic fx failures', () => {
  test('two synthetic failed turns retain separate errors and completed tools before a subsequent success', () =>
    withSession(async (session) => {
      // Repeated synthetic turns cover retention, not the historical session.
      const first = await play(session, 'fxerror');
      const second = await play(session, 'fxerror');
      const failed = fold([...first, ...second]);
      const errors = failed.entries.filter((entry) => entry.kind === 'error');
      const tools = failed.entries.flatMap((entry) =>
        entry.kind === 'tool' ? [entry.call] : [],
      );

      expect(errors).toHaveLength(2);
      expect(new Set(errors.map((entry) => entry.turnId)).size).toBe(2);
      expect(errors.map((entry) => entry.message)).toEqual([
        'ResponseLanguageMismatch',
        'ResponseLanguageMismatch',
      ]);
      expect(tools).toHaveLength(14);
      expect(new Set(tools.map((call) => call.id)).size).toBe(14);
      expect(tools.every((call) => call.status === 'completed')).toBe(true);
      expect(
        failed.entries.filter(
          (entry) =>
            entry.kind === 'assistant' && entry.text === FX_ERROR_NOTICE,
        ),
      ).toHaveLength(2);
      expect(failed.turn).toEqual({ status: 'idle' });

      const next = fold(await play(session, 'text'), failed);

      expect(next.turn).toEqual({ status: 'idle' });
      expect(next.entries.filter((entry) => entry.kind === 'error')).toEqual(
        errors,
      );
      expect(next.entries.at(-1)).toMatchObject({
        kind: 'assistant',
        text: 'Hello, world. This reply came in chunks.',
      });
    }));
});

function at(actions: readonly TranscriptAction[], type: string): number {
  const action = actions.find((candidate) => candidate.type === type);

  assert(action && 'at' in action, `no ${type} action`);

  return action.at;
}

function events(actions: readonly TranscriptAction[]): TranscriptAction[] {
  return actions.filter((action) => action.type === 'update');
}

const PLAYS: Record<string, [string, PlayOptions?]> = {
  text: ['text'],
  thought: ['thought'],
  tools: ['tools'],
  unordered: ['unordered'],
  edit: ['edit'],
  markdown: ['markdown'],
  allowed: ['permission', { answer: 'allow' }],
  rejected: ['permission', { answer: 'reject' }],
  'cancelled permission': ['permission', { answer: 'cancel' }],
  plan: ['plan'],
  status: ['status'],
  error: ['error'],
  'text after error': ['text'],
  'cancelled stream': ['slow', { cancelAfterEvents: 3 }],
  calls: ['calls'],
  'calls again': ['calls'],
};

/**
 * Every scenario played once through one session on the fake agent, as the
 * interface would see it; the tests below fold the recordings.
 */
async function recordAll(): Promise<Record<string, TranscriptAction[]>> {
  const dir = await mkdtemp(join(tmpdir(), 'chord-transcript-'));
  const session = await openSession({
    agent: 'fake',
    cwd: dir,
    agentCommand: fakeAgentCommand(),
  });
  const recorded: Record<string, TranscriptAction[]> = {};

  try {
    for (const [name, [prompt, options]] of Object.entries(PLAYS)) {
      recorded[name] = await play(session, prompt, options);
    }
  } finally {
    await session.close();
    await rm(dir, { recursive: true });
  }

  return recorded;
}

describe("the transcript of each of the fake agent's scenarios", () => {
  let recorded: Record<string, TranscriptAction[]> = {};

  beforeAll(async () => {
    recorded = await recordAll();
  });

  const get = (name: string) => {
    const actions = recorded[name];

    assert(actions, `nothing recorded for ${name}`);

    return actions;
  };

  test('a reply is one block, and the turn works until its result', () => {
    const actions = get('text');
    const seen = states(actions);

    expect(fold(actions).entries).toStrictEqual([
      { kind: 'user', turnId: actions[0]!.turnId, text: 'text' },
      {
        kind: 'assistant',
        turnId: actions[0]!.turnId,
        text: 'Hello, world. This reply came in chunks.',
      },
    ]);
    // An update the agent sent before this first play listened is handed
    // to it ahead of the prompt, so the turn is read where the prompt is.
    expect(
      seen[actions.findIndex((action) => action.type === 'prompt')]?.turn,
    ).toStrictEqual({
      status: 'working',
      turnId: actions[0]!.turnId,
      since: at(actions, 'prompt'),
    });
    // The last chunk is not the end of the turn; the result is.
    expect(seen.at(-2)?.turn.status).toStrictEqual('working');
    expect(fold(actions).turn).toStrictEqual({ status: 'idle' });
  });

  test('thought is kept apart from the reply', () => {
    expect(
      fold(get('thought')).entries.map((e) => [e.kind, 'text' in e && e.text]),
    ).toStrictEqual([
      ['user', 'thought'],
      ['thought', 'Considering the question.'],
      ['assistant', 'Here is the answer.'],
    ]);
  });

  test('a tool call is one entry through all its updates', () => {
    const actions = get('tools');
    const tools = (state: Transcript) =>
      state.entries.flatMap((e) => (e.kind === 'tool' ? [e.call] : []));

    expect(
      states(actions).flatMap((s) => tools(s).map((c) => c.status)),
    ).toStrictEqual([
      'pending',
      'in_progress',
      'completed',
      'completed',
      'completed',
      'completed',
    ]);
    expect(tools(fold(actions))).toStrictEqual([
      {
        id: 'read-1',
        title: 'Read README.md',
        kind: 'read',
        status: 'completed',
        locations: [{ path: 'README.md' }],
        rawInput: { path: 'README.md' },
        rawOutput: { lines: 1 },
        content: [
          {
            type: 'content',
            content: { type: 'text', text: '# chord' },
          },
        ],
      },
    ]);
    expect(fold(actions).entries.map((e) => e.kind)).toStrictEqual([
      'user',
      'tool',
      'assistant',
    ]);
  });

  test('an update before its call, a repeated call and a stale status', () => {
    const entries = fold(get('unordered')).entries;

    expect(entries.map((e) => e.kind)).toStrictEqual([
      'user',
      'tool',
      'assistant',
    ]);
    expect(entries[1]?.kind === 'tool' && entries[1].call).toStrictEqual({
      id: 'grep-2',
      title: 'Search for TODO',
      kind: 'search',
      status: 'completed',
      content: [
        {
          type: 'content',
          content: { type: 'text', text: 'src/main.tsx:1: TODO' },
        },
      ],
    });
  });

  test('an edit keeps its diff', () => {
    const tool = fold(get('edit')).entries.find((e) => e.kind === 'tool');

    assert(tool?.kind === 'tool');
    expect(tool.call.kind).toStrictEqual('edit');
    expect(tool.call.status).toStrictEqual('completed');
    expect(tool.call.content).toStrictEqual([
      {
        type: 'diff',
        path: 'src/greeting.ts',
        oldText: EDIT_OLD,
        newText: EDIT_NEW,
      },
    ]);
  });

  test('a markdown reply arrives as the text it was sent as', () => {
    const replies = fold(get('markdown')).entries.filter(
      (e) => e.kind === 'assistant',
    );

    expect(replies.map((e) => 'text' in e && e.text)).toStrictEqual([
      MARKDOWN_REPLY,
    ]);
  });

  test('a permission request holds the turn until it is answered', () => {
    const actions = get('allowed');
    const turns = states(actions).map((s) => s.turn.status);
    const asked = turns.indexOf('awaiting_permission');

    expect(asked > 0, 'never awaited permission').toBeTruthy();
    expect(turns[asked + 1]).toStrictEqual('working');
    expect(turns.at(-1)).toStrictEqual('idle');

    const waiting = states(actions)[asked]?.turn;

    assert(waiting?.status === 'awaiting_permission');
    expect(waiting.since).toStrictEqual(at(actions, 'prompt'));
    expect(waiting.permissions.map((p) => p.toolCallId)).toStrictEqual([
      'write-4',
    ]);

    const tool = fold(actions).entries.find((e) => e.kind === 'tool');

    assert(tool?.kind === 'tool');
    expect([tool.call.title, tool.call.status]).toStrictEqual([
      'Write notes.txt',
      'completed',
    ]);

    const answer = fold(actions).entries.find((e) => e.kind === 'permission');

    assert(answer?.kind === 'permission');
    expect([answer.title, answer.option?.optionId]).toStrictEqual([
      'Write notes.txt',
      'allow',
    ]);
  });

  test("a request carries the agent's options, as it sent them", () => {
    const asked = get('allowed').find((a) => a.type === 'permission_requested');

    assert(asked?.type === 'permission_requested');
    expect(asked.permission.title).toStrictEqual('Write notes.txt');
    expect(asked.permission.locations).toStrictEqual([{ path: 'notes.txt' }]);
    expect(asked.permission.options.map((o) => o.optionId)).toStrictEqual([
      'allow',
      'always',
      'deny',
    ]);
  });

  test('a rejected permission fails the call, not the turn', () => {
    const state = fold(get('rejected'));
    const tool = state.entries.find((e) => e.kind === 'tool');

    assert(tool?.kind === 'tool');
    expect(tool.call.status).toStrictEqual('failed');

    const answer = state.entries.find((e) => e.kind === 'permission');

    // Rejected with Esc: no option was chosen.
    assert(answer?.kind === 'permission');
    expect(answer.option).toStrictEqual(undefined);
    expect(state.entries.at(-1)).toStrictEqual({
      kind: 'assistant',
      turnId: get('rejected')[0]!.turnId,
      text: 'Permission: deny.',
    });
    expect(state.turn).toStrictEqual({ status: 'idle' });
  });

  test("a later turn's call is its own entry, not the earlier one's", () => {
    const allowed = get('allowed');
    const rejected = get('rejected');
    const calls = fold(rejected, fold(allowed)).entries.flatMap((e) =>
      e.kind === 'tool' ? [[e.turnId, e.call.id, e.call.status]] : [],
    );

    expect(calls).toStrictEqual([
      [allowed[0]!.turnId, 'write-4', 'completed'],
      [rejected[0]!.turnId, 'write-5', 'failed'],
    ]);
  });

  test('cancelling while a permission waits ends the turn cancelled', () => {
    const actions = get('cancelled permission');
    const turns = states(actions).map((s) => s.turn.status);

    expect(turns.includes('awaiting_permission')).toBeTruthy();
    expect(turns[actions.findIndex((a) => a.type === 'cancel')]).toStrictEqual(
      'cancelling',
    );
    expect(fold(actions).entries.at(-1)?.kind).toStrictEqual('cancelled');
    // A withdrawn request was never answered, so it leaves no line.
    expect(
      !fold(actions).entries.some((e) => e.kind === 'permission'),
    ).toBeTruthy();
    expect(fold(actions).turn).toStrictEqual({ status: 'idle' });
  });

  test('a plan replaces the plan', () => {
    const plans = states(get('plan')).map((state) =>
      state.plan.map((e) => e.status).join(' '),
    );

    expect(plans.includes('completed in_progress pending')).toBeTruthy();
    expect(plans.includes('completed completed completed')).toBeTruthy();
  });

  test('a finished plan moves into the transcript at the end', () => {
    const state = fold(get('plan'));
    const last = state.entries.at(-1);

    expect(state.plan).toStrictEqual([]);
    expect(state.entries.map((e) => e.kind)).toStrictEqual([
      'user',
      'assistant',
      'plan',
    ]);
    expect(
      last?.kind === 'plan' && last.entries.map((e) => [e.content, e.status]),
    ).toStrictEqual([
      ['Read the code', 'completed'],
      ['Write the change', 'completed'],
      ['Run the tests', 'completed'],
    ]);
  });

  test('an unfinished plan stays live after its turn', () => {
    const actions = get('plan');
    const result = actions.findLastIndex((a) => a.type === 'result');
    const cut = actions.findIndex(
      (a) =>
        a.type === 'update' &&
        a.update.sessionUpdate === 'plan' &&
        a.update.entries.some((e) => e.status === 'in_progress'),
    );
    const state = fold([...actions.slice(0, cut + 1), actions[result]!]);

    expect(state.turn).toStrictEqual({ status: 'idle' });
    expect(state.plan.map((e) => e.status)).toStrictEqual([
      'completed',
      'in_progress',
      'pending',
    ]);
    expect(!state.entries.some((e) => e.kind === 'plan')).toBeTruthy();
  });

  test('usage and the mode reach the state', () => {
    const state = fold(get('status'));

    expect(state.mode).toStrictEqual('plan');
    expect(state.usage).toStrictEqual({
      used: 1200,
      size: 200000,
      cost: { amount: 0.01, currency: 'USD' },
    });
  });

  test('a failed turn is an entry, and the next turn starts clean', () => {
    const failed = get('error');
    const state = fold(failed);

    expect(state.entries.slice(1)).toStrictEqual([
      {
        kind: 'assistant',
        turnId: failed[0]!.turnId,
        text: 'About to fail.',
      },
      {
        kind: 'error',
        turnId: failed[0]!.turnId,
        message: 'The fake agent failed on purpose.',
        code: '-32603',
      },
    ]);
    expect(state.turn).toStrictEqual({ status: 'idle' });

    const next = fold(get('text after error'), state);

    expect(next.entries.length).toStrictEqual(5);
    expect(next.entries.at(-1)?.kind).toStrictEqual('assistant');
    expect(next.turn).toStrictEqual({ status: 'idle' });
  });

  test('the same scenario twice leaves each turn its own calls', () => {
    const first = get('calls');
    const again = get('calls again');
    const calls = fold(again, fold(first)).entries.flatMap((e) =>
      e.kind === 'tool' ? [[e.turnId, e.call.id, e.call.status]] : [],
    );

    expect(calls).toStrictEqual([
      [first[0]!.turnId, 'read-7', 'completed'],
      [first[0]!.turnId, 'bash-8', 'completed'],
      [first[0]!.turnId, 'read-9', 'failed'],
      [again[0]!.turnId, 'read-10', 'completed'],
      [again[0]!.turnId, 'bash-11', 'completed'],
      [again[0]!.turnId, 'read-12', 'failed'],
    ]);
  });

  test('a cancel mid-stream keeps what came and marks the turn', () => {
    const actions = get('cancelled stream');
    const cancel = actions.findIndex((a) => a.type === 'cancel');
    const seen = states(actions);

    expect(seen[cancel]?.turn).toStrictEqual({
      status: 'cancelling',
      turnId: actions[0]!.turnId,
      since: at(actions, 'prompt'),
      cancelledAt: at(actions, 'cancel'),
    });

    const { entries, turn } = fold(actions);
    const reply = entries[1];

    assert(reply?.kind === 'assistant');
    expect(reply.text).toMatch(/^Working\.+$/);
    expect(entries.slice(2)).toStrictEqual([
      {
        kind: 'cancelled',
        turnId: actions[0]!.turnId,
      },
    ]);
    expect(turn).toStrictEqual({ status: 'idle' });
  });

  test('tool updates in any order, any number of times, make one call', () => {
    const actions = get('tools');
    const prompt = actions.slice(0, 1);
    const toolEvents = events(actions).filter(
      (a) =>
        a.type === 'update' &&
        (a.update.sessionUpdate === 'tool_call' ||
          a.update.sessionUpdate === 'tool_call_update'),
    );
    const expected = fold(actions).entries.slice(0, 2);
    const orders = [
      [...toolEvents].reverse(),
      toolEvents.flatMap((e) => [e, e]),
      [...toolEvents, ...toolEvents],
      [toolEvents[2]!, toolEvents[0]!, toolEvents[1]!],
    ];

    for (const order of orders) {
      expect(fold([...prompt, ...order]).entries).toStrictEqual(expected);
    }
  });

  test('a late event from an earlier turn stays out of the turn in flight', () => {
    const first = get('tools');
    const second = get('text');
    const late = events(first).at(-2);

    assert(late);

    const state = fold([...first, ...second.slice(0, 2), late]);

    expect(state.turn.status).toStrictEqual('working');
    assert(state.turn.status === 'working');
    expect(state.turn.turnId).toStrictEqual(second[0]!.turnId);
    expect(state.entries.filter((e) => e.kind === 'tool').length).toStrictEqual(
      1,
    );

    const stale = fold([...first, ...second.slice(0, 2), ...first.slice(-1)]);

    expect(stale.turn.status).toStrictEqual('working');
  });
});

test('a message put into a running turn draws where it went, among that turn, which goes on working', () => {
  const actions: TranscriptAction[] = [
    { type: 'prompt', turnId: 't1', text: 'slow', at: 1 },
    {
      type: 'update',
      turnId: 't1',
      update: {
        sessionUpdate: 'agent_message_chunk',
        content: { type: 'text', text: 'Working' },
      },
    },
    {
      type: 'prompt',
      turnId: 'm1',
      text: 'Stop.',
      at: 2,
      from: { name: 'main', reachable: true },
      into: 't1',
    },
    {
      type: 'update',
      turnId: 't1',
      update: {
        sessionUpdate: 'agent_message_chunk',
        content: { type: 'text', text: 'Stopping.' },
      },
    },
  ];
  const state = fold(actions);

  expect(
    state.entries.map((entry) => [
      entry.kind,
      entry.turnId,
      'text' in entry ? entry.text : undefined,
    ]),
  ).toStrictEqual([
    ['user', 't1', 'slow'],
    ['assistant', 't1', 'Working'],
    ['message', 't1', 'Stop.'],
    ['assistant', 't1', 'Stopping.'],
  ]);
  expect(state.turn).toStrictEqual({
    status: 'working',
    turnId: 't1',
    since: 1,
  });
});

test("a turn the agent started on its own draws as a block of its own, closed by chord's line, what came after the cancel above it", () => {
  const main = { name: 'main', reachable: true } as const;
  const said = (turnId: string, text: string): TranscriptAction => ({
    type: 'update',
    turnId,
    update: {
      sessionUpdate: 'agent_message_chunk',
      content: { type: 'text', text },
    },
  });
  const closed = fold([
    { type: 'prompt', turnId: 't1', text: 'go', at: 1 },
    said('t1', 'I will run the tests.'),
    {
      type: 'result',
      turnId: 't1',
      result: { status: 'completed', stopReason: 'end_turn' },
    },
    { type: 'self_started', turnId: 'own', from: main },
  ]);

  expect(closed.entries.at(-1)).toStrictEqual({
    kind: 'self_started',
    turnId: 'own',
    from: main,
    alone: true,
  });

  const state = fold(
    [said('own', 'Received '), said('own', 'the message.')],
    closed,
  );

  expect(
    state.entries.map((entry) => [
      entry.kind,
      entry.turnId,
      'text' in entry ? entry.text : 'alone' in entry ? entry.alone : undefined,
    ]),
  ).toStrictEqual([
    ['user', 't1', 'go'],
    ['assistant', 't1', 'I will run the tests.'],
    ['assistant', 'own', 'Received the message.'],
    ['self_started', 'own', false],
  ]);
  expect(state.turn).toStrictEqual({ status: 'idle' });
});

test("an agent's own cycle works as a turn does, with nothing of the person's drawn, until its result (CHD-426)", () => {
  const working = fold([
    { type: 'prompt', turnId: 't1', text: 'hi', at: 0 },
    {
      type: 'result',
      turnId: 't1',
      result: { status: 'completed', stopReason: 'end_turn' },
    },
    { type: 'cycle_started', turnId: 'c1', at: 5000 },
  ]);

  expect(working.turn).toStrictEqual({
    status: 'working',
    turnId: 'c1',
    since: 5000,
    cycle: true,
  });
  expect(working.entries.map((entry) => entry.kind)).toStrictEqual(['user']);
  expect(
    fold(
      [
        {
          type: 'result',
          turnId: 'c1',
          result: { status: 'completed', stopReason: 'end_turn' },
        },
      ],
      working,
    ).turn,
  ).toStrictEqual({ status: 'idle' });
});

test("a permission held between turns stays held through the agent's own cycle (the owner's Q48)", () => {
  const held = fold([
    {
      type: 'permission_requested',
      turnId: 'session',
      permission: { id: 'p1', options: [] },
      at: 100,
      between: true,
    },
    { type: 'cycle_started', turnId: 'c1', at: 5000 },
  ]);

  expect(held.turn).toMatchObject({
    status: 'awaiting_permission',
    turnId: 'c1',
    between: true,
  });
});

test("a permission asked in the agent's own cycle is held, and once answered the cycle works on (the owner's Q48, CHD-426)", () => {
  const asked = fold([
    { type: 'cycle_started', turnId: 'c1', at: 5000 },
    {
      type: 'permission_requested',
      turnId: 'c1',
      permission: { id: 'p1', options: [] },
      at: 6000,
      between: true,
    },
  ]);

  // The wait counts from the request; the cycle's own start is kept.
  expect(asked.turn).toMatchObject({
    status: 'awaiting_permission',
    turnId: 'c1',
    since: 6000,
    between: true,
    cycle: true,
    cycleSince: 5000,
  });
  expect(
    fold(
      [
        {
          type: 'permission_settled',
          turnId: 'c1',
          id: 'p1',
          answer: { type: 'chosen', optionId: 'allow' },
        },
      ],
      asked,
    ).turn,
  ).toStrictEqual({
    status: 'working',
    turnId: 'c1',
    since: 5000,
    cycle: true,
  });
});

test('a permission held before the cycle, answered during it, leaves the cycle working until its end (CHD-426)', () => {
  const answered = fold([
    {
      type: 'permission_requested',
      turnId: 'session',
      permission: { id: 'p1', options: [] },
      at: 100,
      between: true,
    },
    { type: 'cycle_started', turnId: 'c1', at: 5000 },
    {
      type: 'permission_settled',
      turnId: 'c1',
      id: 'p1',
      answer: { type: 'chosen', optionId: 'allow' },
    },
  ]);

  // Working again from when the cycle started, not from the old request.
  expect(answered.turn).toStrictEqual({
    status: 'working',
    turnId: 'c1',
    since: 5000,
    cycle: true,
  });
  expect(
    fold(
      [
        {
          type: 'result',
          turnId: 'c1',
          result: { status: 'completed', stopReason: 'end_turn' },
        },
      ],
      answered,
    ).turn,
  ).toStrictEqual({ status: 'idle' });
});

describe('CHD-426 U3 tester: several held requests keep the cycle clock', () => {
  for (const order of [
    ['old', 'new'],
    ['new', 'old'],
  ] as const) {
    const permission = (id: string, at: number): TranscriptAction => ({
      type: 'permission_requested',
      turnId: id === 'old' ? 'session' : 'cycle',
      permission: { id, options: [] },
      at,
      between: true,
    });
    const settle = (id: string): TranscriptAction => ({
      type: 'permission_settled',
      turnId: 'cycle',
      id,
      answer: { type: 'chosen', optionId: 'allow' },
    });
    const opening: TranscriptAction[] = [
      permission('old', 100),
      { type: 'cycle_started', turnId: 'cycle', at: 5000 },
      permission('new', 9000),
    ];

    test(`${order.join(' then ')}: the last answer resumes the original cycle clock`, () => {
      const waiting = fold([...opening, settle(order[0])]);

      expect(waiting.turn).toMatchObject({
        status: 'awaiting_permission',
        cycle: true,
        cycleSince: 5000,
      });
      expect(fold([settle(order[1])], waiting).turn).toEqual({
        status: 'working',
        turnId: 'cycle',
        since: 5000,
        cycle: true,
      });
    });

    test(`${order.join(' then ')}: answers after the cycle ends cannot restart its clock`, () => {
      const ended = fold([
        ...opening,
        {
          type: 'result',
          turnId: 'cycle',
          result: { status: 'completed', stopReason: 'end_turn' },
        },
      ]);

      assert(ended.turn.status === 'awaiting_permission');
      expect(ended.turn.permissions).toHaveLength(2);
      expect(fold(order.map(settle), ended).turn).toEqual({ status: 'idle' });
    });
  }
});

describe('CHD-534 tester: failure boundaries', () => {
  test('cancelling after a completed shell preserves it without inventing a mismatch, then a failed retry stays distinct', () =>
    withSession(
      async (session) => {
        let didCancel = false;
        const unsubscribe = session.subscribe((update) => {
          if (
            !didCancel &&
            update.sessionUpdate === 'tool_call_update' &&
            update.status === 'completed'
          ) {
            didCancel = true;

            void session.cancel();
          }
        });

        const cancelled = fold(
          await play(session, 'fxerror').finally(unsubscribe),
        );

        const completed = cancelled.entries.flatMap((entry) =>
          entry.kind === 'tool' && entry.call.status === 'completed'
            ? [entry.call]
            : [],
        );

        expect(didCancel).toBe(true);
        expect(completed).toHaveLength(1);
        expect(completed[0]?.kind).toBe('execute');
        expect(cancelled.turn).toEqual({ status: 'idle' });
        expect(cancelled.entries.at(-1)?.kind).toBe('cancelled');
        expect(
          cancelled.entries.filter((entry) => entry.kind === 'error'),
        ).toEqual([]);
        expect(
          cancelled.entries.filter(
            (entry) =>
              entry.kind === 'assistant' && entry.text === FX_ERROR_NOTICE,
          ),
        ).toEqual([]);

        const retried = fold(await play(session, 'fxerror'), cancelled);
        const errors = retried.entries.filter(
          (entry) => entry.kind === 'error',
        );
        const tools = retried.entries.flatMap((entry) =>
          entry.kind === 'tool' ? [entry.call] : [],
        );

        expect(retried.turn).toEqual({ status: 'idle' });
        expect(errors).toHaveLength(1);
        expect(errors[0]?.message).toBe('ResponseLanguageMismatch');
        expect(
          tools.filter((call) => call.status === 'completed'),
        ).toHaveLength(8);
        expect(tools.find((call) => call.id === completed[0]?.id)).toEqual(
          completed[0],
        );
        expect(
          retried.entries.filter((entry) => entry.kind === 'cancelled'),
        ).toHaveLength(1);

        const next = fold(await play(session, 'text'), retried);

        expect(next.turn).toEqual({ status: 'idle' });
        expect(next.entries.filter((entry) => entry.kind === 'error')).toEqual(
          errors,
        );
        expect(next.entries.at(-1)).toMatchObject({
          kind: 'assistant',
          text: 'Hello, world. This reply came in chunks.',
        });
      },
      undefined,
      '--step-ms',
      '40',
    ));
});
