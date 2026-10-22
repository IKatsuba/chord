import { describe, expect, test } from 'bun:test';
import assert from 'node:assert/strict';
import type { ContentBlock, SessionUpdate } from '@agentclientprotocol/sdk';
import { subagentsIn } from '../../../src/session/subagents.ts';
import { taskUpdate } from '../../../src/session/tasks.ts';
import type {
  Entry,
  Subagent,
  Transcript,
  TranscriptAction,
} from '../../../src/session/transcript/types.ts';
import { fold } from './fold.ts';

const TURN = 't1';

const PROMPT: TranscriptAction = {
  type: 'prompt',
  turnId: TURN,
  text: 'look',
  at: 1,
};

/** A subagent announced from the session, or from `from`. */
function spawned(id: string, title: string, from?: string): TranscriptAction {
  return {
    type: 'update',
    turnId: TURN,
    update: {
      sessionUpdate: 'subagent_update',
      sessionId: id,
      title,
      description: `${title}, short`,
      state: { state: 'running' },
    },
    ...(from === undefined ? {} : { subagentId: from }),
  };
}

/** A `session_message` heard on the subagent `to`'s session. */
function message(
  to: string,
  messageId: string,
  content: ContentBlock[] | null | undefined,
  senderSessionId?: string,
): TranscriptAction {
  return {
    type: 'update',
    turnId: TURN,
    subagentId: to,
    update: {
      sessionUpdate: 'session_message',
      messageId,
      recipientSessionId: to,
      ...(content === undefined ? {} : { content }),
      ...(senderSessionId === undefined ? {} : { senderSessionId }),
    },
  };
}

function text(value: string): ContentBlock[] {
  return [{ type: 'text', text: value }];
}

function only(transcript: Transcript, id: string): Subagent {
  const found = subagentsIn(transcript.entries).find((each) => each.id === id);

  assert(found, `no subagent ${id}`);

  return found;
}

/** A subagent's messages among its work: who from, and what they say. */
function messages(subagent: Subagent) {
  return subagent.entries.flatMap((entry: Entry) =>
    entry.kind === 'message'
      ? [
          {
            from: entry.byAgent ? 'agent' : entry.from.name,
            text: entry.text,
          },
        ]
      : [],
  );
}

test("a subagent's first message is its whole task, which a later upsert of it replaces or clears", () => {
  const told = fold([
    PROMPT,
    spawned('a', 'explorer (Explore)'),
    message('a', 'call-1', text('Find the session layer.\n\nIn full.'), 's'),
  ]);

  expect(only(told, 'a').prompt).toStrictEqual(
    'Find the session layer.\n\nIn full.',
  );
  expect(messages(only(told, 'a'))).toStrictEqual([]);
  expect(
    only(fold([message('a', 'call-1', text('Rewritten.'))], told), 'a').prompt,
  ).toStrictEqual('Rewritten.');
  // Content left out keeps it.
  expect(
    only(fold([message('a', 'call-1', undefined)], told), 'a').prompt,
  ).toStrictEqual('Find the session layer.\n\nIn full.');

  const cleared = only(fold([message('a', 'call-1', null)], told), 'a');

  expect(cleared.prompt).toStrictEqual(undefined);
  expect(cleared.description).toStrictEqual('explorer (Explore), short');
});

test("a later message is a row among the subagent's work where it came, upserted by its id", () => {
  const work: TranscriptAction = {
    type: 'update',
    turnId: TURN,
    subagentId: 'a',
    update: {
      sessionUpdate: 'agent_message_chunk',
      content: { type: 'text', text: 'Found it.' },
    },
  };
  const told = fold([
    PROMPT,
    spawned('a', 'explorer (Explore)'),
    spawned('g', 'reader', 'a'),
    message('a', 'call-1', text('Find it.'), 's'),
    work,
    message('a', 'call-2', text('Now the tests.'), 's'),
    message('g', 'call-3', text('Read the tests.'), 'a'),
    message('g', 'call-4', text('And the docs.'), 'a'),
  ]);

  expect(only(told, 'a').entries.map((entry) => entry.kind)).toStrictEqual([
    'subagent',
    'assistant',
    'message',
  ]);
  // From the transcript's own agent, or another subagent, named as its block.
  expect(messages(only(told, 'a'))).toStrictEqual([
    { from: 'agent', text: 'Now the tests.' },
  ]);
  expect(messages(only(told, 'g'))).toStrictEqual([
    { from: 'Agent(explorer (Explore))', text: 'And the docs.' },
  ]);
  expect(only(told, 'g').prompt).toStrictEqual('Read the tests.');

  // Replaced in place, its sender kept when left out, and gone once cleared.
  const replaced = fold(
    [message('g', 'call-4', text('And the README.'))],
    told,
  );

  expect(messages(only(replaced, 'g'))).toStrictEqual([
    { from: 'Agent(explorer (Explore))', text: 'And the README.' },
  ]);
  expect(
    messages(only(fold([message('g', 'call-4', [])], replaced), 'g')),
  ).toStrictEqual([]);
});

test("a later message cleared leaves the subagent's plan where it first came among its work", () => {
  const child = (update: SessionUpdate): TranscriptAction => ({
    type: 'update',
    turnId: TURN,
    subagentId: 'a',
    update,
  });
  const told = fold([
    PROMPT,
    spawned('a', 'explorer'),
    message('a', 'call-1', text('Find it.'), 's'),
    message('a', 'call-2', text('Then the tests.'), 's'),
    child({
      sessionUpdate: 'plan',
      entries: [
        { content: 'Find it', priority: 'medium', status: 'in_progress' },
      ],
    }),
    child({
      sessionUpdate: 'tool_call',
      toolCallId: 'c1',
      title: 'Read c1',
      status: 'in_progress',
    }),
    message('a', 'call-3', text('And the docs.'), 's'),
  ]);
  const work = (transcript: Transcript) => {
    const { entries, planAt } = only(transcript, 'a');

    return { kinds: entries.map((entry) => entry.kind), planAt };
  };

  expect(work(told)).toStrictEqual({
    kinds: ['message', 'tool', 'message'],
    planAt: 1,
  });
  // Before the plan, its place moves with the work; after it, it stays.
  expect(work(fold([message('a', 'call-2', null)], told))).toStrictEqual({
    kinds: ['tool', 'message'],
    planAt: 0,
  });
  expect(work(fold([message('a', 'call-3', null)], told))).toStrictEqual({
    kinds: ['message', 'tool'],
    planAt: 1,
  });
});

describe('CHD-432 tester: message identity and nested routing', () => {
  test('the same message id in two subagents replaces and clears only its recipient', () => {
    const before = fold([
      PROMPT,
      spawned('a', 'A'),
      spawned('b', 'B'),
      message('a', 'task', text('Task A')),
      message('b', 'task', text('Task B')),
      message('a', 'followup', text('For A')),
      message('b', 'followup', text('For B')),
    ]);
    const after = fold(
      [
        message('a', 'task', []),
        message('a', 'followup', text('Rewritten A')),
        message('b', 'followup', null),
      ],
      before,
    );

    expect(only(after, 'a').prompt).toBeUndefined();
    expect(only(after, 'a').description).toBe('A, short');
    expect(only(after, 'b').prompt).toBe('Task B');
    expect(messages(only(after, 'a'))).toStrictEqual([
      { from: 'agent', text: 'Rewritten A' },
    ]);
    expect(messages(only(after, 'b'))).toStrictEqual([]);
    expect(only(before, 'a').prompt).toBe('Task A');
    expect(messages(only(before, 'b'))).toStrictEqual([
      { from: 'agent', text: 'For B' },
    ]);
  });

  test('clearing a task keeps its id so a new followup never becomes the task', () => {
    const transcript = fold([
      PROMPT,
      spawned('a', 'A'),
      message('a', 'task', text('Original task')),
      message('a', 'task', null),
      message('a', 'later', text('Followup')),
      message('a', 'task', [
        { type: 'text', text: 'Restored' },
        { type: 'text', text: ' task' },
      ]),
    ]);

    expect(only(transcript, 'a').prompt).toBe('Restored task');
    expect(messages(only(transcript, 'a'))).toStrictEqual([
      { from: 'agent', text: 'Followup' },
    ]);
  });

  test('a nested sender is named on another branch and a later explicit sender replaces it', () => {
    const before = fold([
      PROMPT,
      spawned('a', 'A'),
      spawned('g', 'Nested', 'a'),
      spawned('b', 'B'),
      message('b', 'task', text('Task B')),
      message('b', 'later', text('From nested'), 'g'),
    ]);

    expect(messages(only(before, 'b'))).toStrictEqual([
      { from: 'Agent(Nested)', text: 'From nested' },
    ]);
    expect(
      messages(
        only(
          fold([message('b', 'later', text('From runtime'), 'root')], before),
          'b',
        ),
      ),
    ).toStrictEqual([{ from: 'agent', text: 'From runtime' }]);
    expect(fold([message('missing', 'id', text('No leak'))], before)).toBe(
      before,
    );
  });
});

test('a subagent waits while its agent says requires_action, and keeps having offered a cancel it lost', () => {
  const stood = (
    state: { state: string } | undefined,
    at: number,
    capabilities?: { cancel?: object } | null,
  ): TranscriptAction => ({
    type: 'update',
    turnId: TURN,
    at,
    update: {
      sessionUpdate: 'subagent_update',
      sessionId: 'a',
      ...(state === undefined ? {} : { state: state as never }),
      ...(capabilities === undefined ? {} : { capabilities }),
    },
  });
  const after = (...actions: TranscriptAction[]) =>
    only(
      fold([
        PROMPT,
        { ...spawned('a', 'explorer'), at: 5 } as TranscriptAction,
        stood(undefined, 5, { cancel: {} }),
        ...actions,
      ]),
      'a',
    );

  expect(after(stood({ state: 'requires_action' }, 9)).waiting).toStrictEqual({
    since: 9,
  });
  // A second one keeps the first time; a patch with no state keeps it.
  expect(
    after(
      stood({ state: 'requires_action' }, 9),
      stood({ state: 'requires_action' }, 12),
      stood(undefined, 14),
    ).waiting,
  ).toStrictEqual({ since: 9 });
  expect(
    after(
      stood({ state: 'requires_action' }, 9),
      stood({ state: 'running' }, 12),
    ).waiting,
  ).toStrictEqual(undefined);

  const lost = after(stood(undefined, 9, null));

  expect([lost.cancellable, lost.offeredCancel]).toStrictEqual([
    undefined,
    true,
  ]);
});

describe('CHD-2 tester: retained capability and wait clocks', () => {
  const patch = (
    at: number,
    update: Extract<SessionUpdate, { sessionUpdate: 'subagent_update' }>,
  ): TranscriptAction => ({ type: 'update', turnId: TURN, at, update });

  test('a late cancel offer stays remembered after it is revoked and waiting restarts after recovery', () => {
    const before = fold([
      PROMPT,
      spawned('a', 'A'),
      patch(10, {
        sessionUpdate: 'subagent_update',
        sessionId: 'a',
        state: { state: 'requires_action' },
      }),
      patch(20, {
        sessionUpdate: 'subagent_update',
        sessionId: 'a',
        capabilities: { cancel: {} },
      }),
      patch(30, {
        sessionUpdate: 'subagent_update',
        sessionId: 'a',
        capabilities: {},
      }),
    ]);

    expect(only(before, 'a')).toMatchObject({
      offeredCancel: true,
      waiting: { since: 10 },
    });
    expect(only(before, 'a').cancellable).toBeUndefined();

    const after = fold(
      [
        patch(40, {
          sessionUpdate: 'subagent_update',
          sessionId: 'a',
          state: { state: 'unknown' },
        }),
        patch(50, {
          sessionUpdate: 'subagent_update',
          sessionId: 'a',
          state: { state: 'requires_action' },
        }),
      ],
      before,
    );

    expect(only(after, 'a')).toMatchObject({
      offeredCancel: true,
      waiting: { since: 50 },
      state: 'running',
    });
    expect(only(after, 'a').endedAt).toBeUndefined();
    expect(only(after, 'a').cancellable).toBeUndefined();
  });
});

test('a subagent stopped alone reads stopping until its agent tells a state it is not at work in, or the stop could not go', () => {
  const stop = (stopping: boolean): TranscriptAction => ({
    type: 'subagent_stopping',
    turnId: 'stop',
    subagentId: 'a',
    stopping,
  });
  const told = (state: string): TranscriptAction => ({
    type: 'update',
    turnId: TURN,
    update: {
      sessionUpdate: 'subagent_update',
      sessionId: 'a',
      state: { state } as never,
    },
  });
  const stopped = fold([PROMPT, spawned('a', 'explorer'), stop(true)]);

  expect(only(stopped, 'a').stopping).toBe(true);
  expect(only(fold([told('running')], stopped), 'a').stopping).toBe(true);
  expect(only(fold([told('idle')], stopped), 'a').stopping).toBe(undefined);
  expect(only(fold([told('unknown')], stopped), 'a').stopping).toBe(undefined);
  expect(only(fold([stop(false)], stopped), 'a').stopping).toBe(undefined);
  // An ended one is not marked.
  expect(only(fold([told('idle'), stop(true)], stopped), 'a').stopping).toBe(
    undefined,
  );
});

describe('CHD-2 tester: completion crossing a stop', () => {
  test('completion stays done after late rollback and a second run can be stopped independently', () => {
    const stop = (stopping: boolean): TranscriptAction => ({
      type: 'subagent_stopping',
      turnId: 'stop',
      subagentId: 'a',
      stopping,
    });
    const state = (word: 'running' | 'idle', at: number): TranscriptAction => ({
      type: 'update',
      turnId: TURN,
      at,
      update: {
        sessionUpdate: 'subagent_update',
        sessionId: 'a',
        state:
          word === 'running'
            ? { state: 'running' }
            : { state: 'idle', stopReason: 'end_turn' },
      },
    });
    const done = fold([
      PROMPT,
      spawned('a', 'A'),
      stop(true),
      state('idle', 20),
      stop(false),
    ]);

    expect(only(done, 'a')).toMatchObject({ state: 'completed', endedAt: 20 });
    expect(only(done, 'a').stopping).toBeUndefined();

    const again = fold([state('running', 30), stop(true)], done);

    expect(only(again, 'a').state).toBe('running');
    expect(only(again, 'a').stopping).toBe(true);
    expect(only(again, 'a').endedAt).toBeUndefined();
  });
});

test("a task's block keeps what its ending update says it spent, beside its task (CHD-373)", () => {
  const update = (meta: Record<string, unknown>, state: string) => ({
    type: 'update' as const,
    turnId: 't1',
    update: {
      sessionUpdate: 'subagent_update',
      sessionId: 'task-1',
      state: { state },
      _meta: meta,
    } as SessionUpdate,
    at: 0,
  });
  const ended = fold([
    { type: 'prompt', turnId: 't1', text: 'task', at: 0 },
    update({ 'chord/task': { name: 'Fix it', runtime: 'fake' } }, 'running'),
    update(
      {
        'chord/spent': {
          tokens: { inputTokens: 1000, totalTokens: 2000 },
          cost: { amount: 0.0125, currency: 'USD' },
          estimated: true,
        },
      },
      'completed',
    ),
  ]);
  const block = ended.entries.find((entry) => entry.kind === 'subagent');

  assert(block?.kind === 'subagent');
  expect(block.subagent.task).toStrictEqual({
    name: 'Fix it',
    runtime: 'fake',
    spent: {
      tokens: { inputTokens: 1000, totalTokens: 2000 },
      cost: { amount: 0.0125, currency: 'USD' },
      estimated: true,
    },
  });
});

test("a task's spend that a record or an agent bent is read part by part, what does not read left out (CHD-373)", () => {
  const spentFrom = (spent: unknown) => {
    const block = fold([
      { type: 'prompt', turnId: 't1', text: 'task', at: 0 },
      {
        type: 'update',
        turnId: 't1',
        update: {
          sessionUpdate: 'subagent_update',
          sessionId: 'task-1',
          state: { state: 'running' },
          _meta: { 'chord/task': { name: 'Fix it', runtime: 'fake' } },
        } as SessionUpdate,
        at: 0,
      },
      {
        type: 'update',
        turnId: 't1',
        update: {
          sessionUpdate: 'subagent_update',
          sessionId: 'task-1',
          state: { state: 'completed' },
          _meta: { 'chord/spent': spent },
        } as SessionUpdate,
        at: 0,
      },
    ]).entries.find((entry) => entry.kind === 'subagent');

    assert(block?.kind === 'subagent');

    return block.subagent.task?.spent;
  };

  const cost = { amount: 0.0125, currency: 'USD' };

  // A cost with no amount or currency is no cost; its estimate goes with it.
  expect(
    spentFrom({ cost: {}, estimated: true, tokens: { totalTokens: 2000 } }),
  ).toStrictEqual({ tokens: { totalTokens: 2000 } });
  expect(spentFrom({ cost: { amount: 'x', currency: 'USD' } })).toBe(undefined);
  // A token count that is not one is left out, the others kept.
  expect(
    spentFrom({
      tokens: { totalTokens: 'bad', inputTokens: 1000, outputTokens: -1 },
      cost,
    }),
  ).toStrictEqual({ tokens: { inputTokens: 1000 }, cost });
  expect(spentFrom({ tokens: { totalTokens: 1.5 } })).toBe(undefined);
  // `estimated` stands only with a cost, and only as true.
  expect(spentFrom({ cost, estimated: 'yes' })).toStrictEqual({ cost });
  expect(spentFrom({ cost, estimated: true })).toStrictEqual({
    cost,
    estimated: true,
  });
  // Not an object at all: nothing.
  expect(spentFrom('lots')).toBe(undefined);
  expect(spentFrom(null)).toBe(undefined);
});

describe("an agent item's end, once its turn has ended (CHD-479)", () => {
  /** Claude's subagent `id`, open to a cancel, announced at 2. */
  const announced = (id: string): TranscriptAction => ({
    type: 'update',
    turnId: TURN,
    at: 2,
    update: {
      sessionUpdate: 'subagent_update',
      sessionId: id,
      title: `${id} (Explore)`,
      description: `Find ${id}`,
      state: { state: 'running' },
      capabilities: { cancel: {} },
    },
  });
  const told = (
    id: string,
    state: Record<string, unknown>,
    at: number,
  ): TranscriptAction => ({
    type: 'update',
    turnId: TURN,
    at,
    update: {
      sessionUpdate: 'subagent_update',
      sessionId: id,
      state,
    } as unknown as SessionUpdate,
  });
  const ENDED: TranscriptAction = {
    type: 'result',
    turnId: TURN,
    result: { status: 'completed', stopReason: 'end_turn' },
  };
  const ends = (transcript: Transcript) =>
    transcript.entries.filter((entry) => entry.kind === 'item_ended');

  test('one that ends after its turn says so once, with its name, end and times', () => {
    expect(
      ends(
        fold([
          PROMPT,
          announced('a'),
          ENDED,
          told('a', { state: 'completed' }, 6002),
        ]),
      ),
    ).toStrictEqual([
      {
        kind: 'item_ended',
        turnId: TURN,
        item: 'agent',
        name: 'Find a',
        end: 'done',
        startedAt: 2,
        endedAt: 6002,
      },
    ]);
  });

  test('one that ends while its turn runs is said by its own block, not by a line', () => {
    expect(
      ends(
        fold([PROMPT, announced('a'), told('a', { state: 'completed' }, 9)]),
      ),
    ).toStrictEqual([]);
  });

  test('a subagent that is no item, offering no cancel of its own, gets none', () => {
    expect(
      ends(
        fold([
          PROMPT,
          spawned('a', 'Find'),
          ENDED,
          told('a', { state: 'completed' }, 9),
        ]),
      ),
    ).toStrictEqual([]);
  });

  test("a failure carries its agent's reason, a stop the person's x, a gone agent its disconnect", () => {
    const failed = fold([
      PROMPT,
      announced('a'),
      announced('b'),
      announced('c'),
      ENDED,
      told(
        'a',
        {
          state: 'idle',
          stopReason: 'error',
          error: { message: 'tsc exited 2' },
        },
        9,
      ),
      {
        type: 'subagent_stopping',
        turnId: TURN,
        subagentId: 'b',
        stopping: true,
      },
      told('b', { state: 'cancelled' }, 10),
      { type: 'disconnected', turnId: TURN, at: 11 },
    ]);

    expect(
      ends(failed).map((entry) =>
        entry.kind === 'item_ended'
          ? [entry.name, entry.end, entry.byPerson, entry.error]
          : [],
      ),
    ).toStrictEqual([
      ['Find a', 'failed', undefined, 'tsc exited 2'],
      ['Find b', 'stopped', true, undefined],
      ['Find c', 'disconnected', undefined, undefined],
    ]);
  });

  test("a subagent's own agent item, its end told in its parent's work, is said once at the top after the root turn, and not while it runs", () => {
    /** `action` as it comes in `a`'s own work. */
    const inA = (action: TranscriptAction): TranscriptAction => {
      assert(action.type === 'update');

      return { ...action, subagentId: 'a' };
    };

    const inner = [
      PROMPT,
      announced('a'),
      inA(announced('g')),
    ] satisfies TranscriptAction[];
    const everyLine = (entries: readonly Entry[]): Entry[] =>
      entries.flatMap((entry) =>
        entry.kind === 'item_ended'
          ? [entry]
          : entry.kind === 'subagent'
            ? everyLine(entry.subagent.entries)
            : [],
      );

    const during = fold([...inner, inA(told('g', { state: 'completed' }, 9))]);

    expect(everyLine(during.entries)).toStrictEqual([]);

    const after = fold([
      ...inner,
      ENDED,
      inA(told('g', { state: 'completed' }, 9)),
    ]);

    expect(everyLine(after.entries)).toHaveLength(1);
    expect(after.entries.at(-1)).toMatchObject({
      kind: 'item_ended',
      turnId: TURN,
      name: 'Find g',
      end: 'done',
    });
  });

  test('an ended one told again says nothing more', () => {
    expect(
      ends(
        fold([
          PROMPT,
          announced('a'),
          ENDED,
          told('a', { state: 'completed' }, 9),
          told('a', { state: 'completed' }, 10),
        ]),
      ),
    ).toHaveLength(1);
  });
});

describe('CHD-479 tester: late item transitions keep the announcing root turn', () => {
  const update = (
    id: string,
    state: string,
    at: number,
    parent?: string,
  ): TranscriptAction => ({
    type: 'update',
    turnId: TURN,
    at,
    ...(parent === undefined ? {} : { subagentId: parent }),
    update: {
      sessionUpdate: 'subagent_update',
      sessionId: id,
      description: `Find ${id}`,
      state: { state },
      capabilities: { cancel: {} },
    } as SessionUpdate,
  });
  const result = (status: 'completed' | 'cancelled'): TranscriptAction => ({
    type: 'result',
    turnId: TURN,
    result:
      status === 'completed'
        ? { status, stopReason: 'end_turn' }
        : { status, stopReason: 'cancelled' },
  });
  const lines = (transcript: Transcript) =>
    transcript.entries.filter((entry) => entry.kind === 'item_ended');

  test('an old root ends during another live turn without ending or duplicating that turn', () => {
    const transcript = fold([
      PROMPT,
      update('old', 'running', 2),
      result('completed'),
      { type: 'prompt', turnId: 'next', text: 'next turn', at: 10 },
      update('old', 'completed', 12),
      update('old', 'failed', 13),
    ]);

    expect(lines(transcript)).toHaveLength(1);
    expect(lines(transcript)[0]).toMatchObject({
      turnId: TURN,
      name: 'Find old',
      end: 'done',
    });
    expect(transcript.turn).toMatchObject({
      turnId: 'next',
      status: 'working',
    });
  });

  test('a nested unknown survives its root cancel, then disconnects once at the top', () => {
    const transcript = fold([
      PROMPT,
      update('outer', 'running', 2),
      update('inner', 'unknown', 3, 'outer'),
      result('cancelled'),
      { type: 'disconnected', turnId: TURN, at: 20 },
      { type: 'disconnected', turnId: TURN, at: 21 },
    ]);

    expect(lines(transcript).map(({ name, end }) => [name, end])).toStrictEqual(
      [
        ['Find outer', 'disconnected'],
        ['Find inner', 'disconnected'],
      ],
    );
    expect(
      only(transcript, 'outer').entries.some(
        (entry) => entry.kind === 'item_ended',
      ),
    ).toBe(false);
  });

  test('a late nested completion after a cancelled root is emitted once; a live-root end never reappears later', () => {
    const prefix = [
      PROMPT,
      update('outer', 'running', 2),
      update('inner', 'running', 3, 'outer'),
    ];
    const late = fold([
      ...prefix,
      result('cancelled'),
      update('inner', 'completed', 10, 'outer'),
      update('inner', 'completed', 11, 'outer'),
    ]);
    const during = fold([
      ...prefix,
      update('inner', 'completed', 4, 'outer'),
      result('completed'),
      update('inner', 'completed', 10, 'outer'),
    ]);

    expect(lines(late)).toHaveLength(1);
    expect(lines(late)[0]).toMatchObject({
      name: 'Find inner',
      turnId: TURN,
      end: 'done',
    });
    expect(lines(during)).toStrictEqual([]);
  });

  test('independent owners reusing the same ACP id cannot satisfy or duplicate each other', () => {
    const a = fold([
      PROMPT,
      update('shared', 'running', 2),
      result('completed'),
    ]);
    const b = fold([
      PROMPT,
      update('shared', 'running', 2),
      result('completed'),
    ]);
    const endedA = fold([update('shared', 'completed', 8)], a);
    const endedB = fold([update('shared', 'cancelled', 9)], b);

    expect(lines(a)).toStrictEqual([]);
    expect(lines(b)).toStrictEqual([]);
    expect(lines(endedA)[0]).toMatchObject({ end: 'done' });
    expect(lines(endedB)[0]).toMatchObject({ end: 'stopped' });
  });
});

describe("a task's end, once its turn has ended (CHD-482)", () => {
  const START = { name: 'Watch the build', runtime: 'fake', prompt: 'Watch' };
  const started = (id: string): TranscriptAction => ({
    type: 'update',
    turnId: TURN,
    at: 2,
    update: taskUpdate(id, 'running', START),
  });
  const ending = (
    id: string,
    state: Parameters<typeof taskUpdate>[1],
    stoppedWith?: 'x' | 'esc',
  ): TranscriptAction => ({
    type: 'update',
    turnId: '',
    at: 3002,
    update: taskUpdate(id, state, undefined, undefined, stoppedWith),
  });
  const ENDED: TranscriptAction = {
    type: 'result',
    turnId: TURN,
    result: { status: 'completed', stopReason: 'end_turn' },
  };
  const ends = (transcript: Transcript) =>
    transcript.entries.filter((entry) => entry.kind === 'item_ended');
  const stop = (
    more: Partial<Extract<Entry, { kind: 'item_ended' }>> = {},
  ): Extract<Entry, { kind: 'item_ended' }> => ({
    kind: 'item_ended',
    turnId: TURN,
    item: 'task',
    name: 'Watch the build',
    end: 'stopped',
    ...more,
    startedAt: 2,
    endedAt: 3002,
  });

  test("a stop gets chord's line, saying the person's key where it was theirs", () => {
    expect(
      ends(
        fold([
          PROMPT,
          started('a'),
          started('b'),
          started('c'),
          ENDED,
          ending('a', 'cancelled', 'x'),
          ending('b', 'cancelled', 'esc'),
          ending('c', 'cancelled'),
        ]),
      ),
    ).toStrictEqual([stop({ byPerson: true }), stop({ byEsc: true }), stop()]);
  });

  test('a report or a failure is its own message, so it gets none', () => {
    expect(
      ends(
        fold([
          PROMPT,
          started('a'),
          started('b'),
          started('c'),
          ENDED,
          ending('a', 'completed'),
          ending('b', 'failed'),
          ending('c', 'disconnected'),
        ]),
      ),
    ).toStrictEqual([]);
  });

  test("esc on a later turn: its line says so though that turn's cancelled answer comes before the task's end", () => {
    const later = 't2';

    expect(
      ends(
        fold([
          PROMPT,
          started('a'),
          ENDED,
          { type: 'prompt', turnId: later, text: 'slow', at: 2000 },
          { type: 'cancel', turnId: later, at: 2500 },
          {
            type: 'result',
            turnId: later,
            result: { status: 'cancelled', stopReason: 'cancelled' },
          },
          ending('a', 'cancelled', 'esc'),
        ]),
      ),
    ).toStrictEqual([stop({ byEsc: true })]);
  });

  test('one stopped while its turn runs is said by its own block', () => {
    expect(
      ends(fold([PROMPT, started('a'), ending('a', 'cancelled', 'esc')])),
    ).toStrictEqual([]);
  });

  test('who stopped it is kept on the task, as a record replays its update', () => {
    const subagent = fold([
      PROMPT,
      started('a'),
      ending('a', 'cancelled', 'x'),
    ]).entries.find((entry) => entry.kind === 'subagent');

    assert(subagent?.kind === 'subagent');
    expect(subagent.subagent.task?.stoppedWith).toBe('x');
  });
});

describe('CHD-482 U3 tester: late and nested task stops stay singular', () => {
  const started: TranscriptAction = {
    type: 'update',
    turnId: TURN,
    at: 3,
    update: taskUpdate('task', 'running', {
      name: 'Watch the build',
      runtime: 'fake',
      prompt: 'Watch',
    }),
  };
  const ended: TranscriptAction = {
    type: 'result',
    turnId: TURN,
    result: { status: 'completed', stopReason: 'end_turn' },
  };
  const stopped: TranscriptAction = {
    type: 'update',
    turnId: TURN,
    at: 20,
    update: taskUpdate('task', 'cancelled', undefined, undefined, 'x'),
  };
  const ends = (value: Transcript) =>
    value.entries.filter((entry) => entry.kind === 'item_ended');

  test('a nested task repeats its stop update without duplicating the root end line', () => {
    const value = fold([
      PROMPT,
      spawned('outer', 'Outer'),
      { ...started, subagentId: 'outer' },
      ended,
      { ...stopped, subagentId: 'outer' },
      { ...stopped, subagentId: 'outer' },
    ]);

    expect(ends(value)).toMatchObject([
      {
        turnId: TURN,
        item: 'task',
        name: 'Watch the build',
        byPerson: true,
        startedAt: 3,
        endedAt: 20,
      },
    ]);
    expect(ends(value)).toHaveLength(1);
  });

  test('a late repeated stop belongs to its announcing turn while a newer turn keeps working', () => {
    const value = fold([
      PROMPT,
      started,
      ended,
      { type: 'prompt', turnId: 'later', text: 'slow', at: 10 },
      stopped,
      stopped,
    ]);

    expect(ends(value)).toMatchObject([{ turnId: TURN, byPerson: true }]);
    expect(ends(value)).toHaveLength(1);
    expect(value.turn.status).toBe('working');
  });
});
