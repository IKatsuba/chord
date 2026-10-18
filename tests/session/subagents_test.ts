import { describe, expect, test } from 'bun:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import process from 'node:process';
import { join } from 'node:path';
import type {
  SessionNotification,
  SessionUpdate,
  StateUpdate,
  ToolCallUpdate,
} from '@agentclientprotocol/sdk';
import {
  Conversation,
  type ConversationEvent,
} from '../../src/session/conversation.ts';
import { runOneshot } from '../../src/session/oneshot.ts';
import type { PendingPermission } from '../../src/session/permissions.ts';
import { FILLED } from '../../src/session/enrich.ts';
import {
  FileRecording,
  pastBySession,
  readPast,
  type RecordEntry,
} from '../../src/session/record.ts';
import { openSession, type Session } from '../../src/session/session.ts';
import { readRecords, sessionById } from '../../src/session/sessions.ts';
import {
  routed,
  runningSubagents,
  sessionTree,
  subagentPath,
  subagentsIn,
  waitingOn,
} from '../../src/session/subagents.ts';
import { reduceTranscript } from '../../src/session/transcript/reducer.ts';
import {
  emptyTranscript,
  type Entry,
  type Subagent,
  type Transcript,
  type TranscriptAction,
} from '../../src/session/transcript/types.ts';
import { fakeAgentCommand } from '../fixtures/fake.ts';
import { play, run, said } from '../fixtures/recorder.ts';
import { recordSession } from '../fixtures/records.ts';

const TURN = 't1';

/**
 * The fake at a fifth of its pace, so the subagent scenario's few seconds,
 * made to be watched, pass in well under one.
 */
const FAKE = fakeAgentCommand(undefined, '--step-ms', '1');
const RESUMING = fakeAgentCommand(undefined, '--step-ms', '1', '--resume-only');

function fold(
  actions: readonly TranscriptAction[],
  from: Transcript = emptyTranscript,
): Transcript {
  return actions.reduce(reduceTranscript, from);
}

/** A `subagent_update` from the session, or from `from`, at `at`. */
function spawned(
  id: string,
  title: string,
  { from, at }: { from?: string; at?: number } = {},
): TranscriptAction {
  return {
    type: 'update',
    turnId: TURN,
    update: {
      sessionUpdate: 'subagent_update',
      sessionId: id,
      title,
      description: `${title}, in full.`,
    },
    ...(from === undefined ? {} : { subagentId: from }),
    ...(at === undefined ? {} : { at }),
  };
}

function ended(
  id: string,
  state: string,
  { from, at }: { from?: string; at?: number } = {},
): TranscriptAction {
  return {
    type: 'update',
    turnId: TURN,
    update: {
      sessionUpdate: 'subagent_update',
      sessionId: id,
      state: { state },
    },
    ...(from === undefined ? {} : { subagentId: from }),
    ...(at === undefined ? {} : { at }),
  };
}

/** An update of the session's own, or of the subagent `from`. */
function update(update: SessionUpdate, from?: string): TranscriptAction {
  return {
    type: 'update',
    turnId: TURN,
    update,
    ...(from === undefined ? {} : { subagentId: from }),
  };
}

function say(text: string, from?: string): TranscriptAction {
  return update(
    {
      sessionUpdate: 'agent_message_chunk',
      content: { type: 'text', text },
    },
    from,
  );
}

function call(
  toolCallId: string,
  status: 'in_progress' | 'completed' | 'failed',
  from?: string,
): TranscriptAction {
  return update(
    status === 'in_progress'
      ? {
          sessionUpdate: 'tool_call',
          toolCallId,
          title: `Read ${toolCallId}`,
          kind: 'read',
          status,
        }
      : { sessionUpdate: 'tool_call_update', toolCallId, status },
    from,
  );
}

const PROMPT: TranscriptAction = {
  type: 'prompt',
  turnId: TURN,
  text: 'look',
  at: 1,
};

/** Each entry as a short line, a subagent with what it holds under it. */
function shape(entries: readonly Entry[]): unknown[] {
  return entries.map((entry) => {
    switch (entry.kind) {
      case 'assistant':
      case 'thought':
      case 'user':
        return `${entry.kind}: ${entry.text}`;
      case 'tool':
        return `tool: ${entry.call.title} ${entry.call.status}`;
      case 'subagent':
        return {
          [`${entry.subagent.title} ${entry.subagent.state}`]: shape(
            entry.subagent.entries,
          ),
        };
      default:
        return entry.kind;
    }
  });
}

function only(transcript: Transcript, id: string): Subagent {
  const found = subagentsIn(transcript.entries).find((each) => each.id === id);

  assert(found, `no subagent ${id}`);

  return found;
}

test("a subagent stands where its spawn came, among its parent's entries, and changes there", () => {
  const transcript = fold([
    PROMPT,
    say('I will send two.'),
    spawned('a', 'Find the layer'),
    spawned('b', 'Find the drawing'),
    say('Reading', 'a'),
    call('c1', 'in_progress', 'b'),
    say('Both are out.'),
    call('c1', 'failed', 'b'),
    ended('b', 'failed'),
    say(' Done.', 'a'),
  ]);

  expect(shape(transcript.entries)).toStrictEqual([
    'user: look',
    'assistant: I will send two.',
    { 'Find the layer running': ['assistant: Reading Done.'] },
    { 'Find the drawing failed': ['tool: Read c1 failed'] },
    'assistant: Both are out.',
  ]);
  expect(only(transcript, 'b').description).toStrictEqual(
    'Find the drawing, in full.',
  );
});

test("a subagent's words, calls and plan are its own, and never its parent's", () => {
  const plan = [
    {
      content: 'Find it',
      priority: 'medium',
      status: 'in_progress',
    } as const,
  ];
  const transcript = fold([
    PROMPT,
    spawned('a', 'Find the layer'),
    call('c1', 'in_progress', 'a'),
    update({ sessionUpdate: 'plan', entries: plan }, 'a'),
    update(
      {
        sessionUpdate: 'usage_update',
        used: 5,
        size: 10,
      },
      'a',
    ),
    update(
      { sessionUpdate: 'current_mode_update', currentModeId: 'plan' },
      'a',
    ),
    say('Found it.', 'a'),
  ]);
  const child = only(transcript, 'a');

  expect(transcript.plan).toStrictEqual([]);
  expect(transcript.usage).toStrictEqual(undefined);
  expect(transcript.mode).toStrictEqual(undefined);
  expect(child.plan).toStrictEqual(plan);
  // The plan came after its first call: that is where it is drawn.
  expect(child.planAt).toStrictEqual(1);
  expect(shape(child.entries)).toStrictEqual([
    'tool: Read c1 in_progress',
    'assistant: Found it.',
  ]);
  expect(
    transcript.entries.filter((entry) => entry.kind === 'assistant'),
  ).toStrictEqual([]);
});

test('an update for a subagent the transcript does not hold is dropped, not drawn as the parent', () => {
  const transcript = fold([PROMPT, say('Hello', 'stranger')]);

  expect(shape(transcript.entries)).toStrictEqual(['user: look']);
});

test("a subagent's own subagent nests under it, and a request from it names the way down", () => {
  const transcript = fold([
    PROMPT,
    spawned('a', 'Find the layer'),
    spawned('g', 'Read the tests', { from: 'a' }),
    call('c1', 'in_progress', 'g'),
    say('Read.', 'g'),
    ended('g', 'completed', { from: 'a' }),
    say('Back.', 'a'),
  ]);

  expect(shape(transcript.entries)).toStrictEqual([
    'user: look',
    {
      'Find the layer running': [
        {
          'Read the tests completed': [
            'tool: Read c1 in_progress',
            'assistant: Read.',
          ],
        },
        'assistant: Back.',
      ],
    },
  ]);
  expect(
    subagentPath(transcript.entries, 'g').map((each) => each.title),
  ).toStrictEqual(['Find the layer', 'Read the tests']);
  expect(subagentPath(transcript.entries, 'nobody')).toStrictEqual([]);
});

test('a subagent reopened under a new id is a new one, where it came', () => {
  const transcript = fold([
    PROMPT,
    spawned('a', 'Find the layer'),
    ended('a', 'completed'),
    say('Asking again.'),
    spawned('a:generation:2', 'Find the layer'),
  ]);

  expect(shape(transcript.entries)).toStrictEqual([
    'user: look',
    { 'Find the layer completed': [] },
    'assistant: Asking again.',
    { 'Find the layer running': [] },
  ]);
});

test("a subagent's times are when its spawn and its end reached chord, and none is made up", () => {
  const timed = fold([
    PROMPT,
    spawned('a', 'Find', { at: 100 }),
    ended('a', 'completed', { at: 141 }),
    // A word that repeats the ending keeps the time it ended at.
    ended('a', 'completed', { at: 150 }),
  ]);
  const untimed = fold([PROMPT, spawned('a', 'Find'), ended('a', 'failed')]);

  expect([only(timed, 'a').startedAt, only(timed, 'a').endedAt]).toStrictEqual([
    100, 141,
  ]);
  expect([
    only(untimed, 'a').startedAt,
    only(untimed, 'a').endedAt,
  ]).toStrictEqual([undefined, undefined]);
});

test("ACP's own states read as chord's, and a patch keeps or clears what it names", () => {
  const states = (...words: string[]) =>
    words.map(
      (word) =>
        only(fold([PROMPT, spawned('a', 'Find'), ended('a', word)]), 'a').state,
    );

  expect(
    states('running', 'requires_action', 'idle', 'unknown', 'mystery'),
  ).toStrictEqual(['running', 'running', 'ended', 'untracked', 'running']);

  const patched = only(
    fold([
      PROMPT,
      spawned('a', 'Find'),
      update({
        sessionUpdate: 'subagent_update',
        sessionId: 'a',
        title: null,
      }),
      ended('a', 'idle', { at: 5 }),
      ended('a', 'running', { at: 6 }),
    ]),
    'a',
  );

  expect(patched.title).toStrictEqual(undefined);
  expect(patched.description).toStrictEqual('Find, in full.');
  expect([patched.state, patched.endedAt]).toStrictEqual([
    'running',
    undefined,
  ]);
});

/** A `subagent_update` of `id`'s that brings `state` whole, at `at`. */
function stood(id: string, state: StateUpdate, at?: number): TranscriptAction {
  return {
    type: 'update',
    turnId: TURN,
    update: { sessionUpdate: 'subagent_update', sessionId: id, state },
    ...(at === undefined ? {} : { at }),
  };
}

test('an idle reads by its stop reason, and unknown as untracked until a later state takes it back', () => {
  const states = (...each: StateUpdate[]) =>
    each.map((state) => {
      const { state: word, error } = only(
        fold([PROMPT, spawned('a', 'Find'), stood('a', state)]),
        'a',
      );

      return error === undefined ? word : [word, error];
    });

  expect(
    states(
      { state: 'idle', stopReason: 'end_turn' },
      { state: 'idle', stopReason: 'cancelled' },
      {
        state: 'idle',
        stopReason: 'error',
        error: { code: -32603, message: 'API Error: 529 Overloaded' },
      },
      { state: 'idle', stopReason: 'error' },
      { state: 'idle', stopReason: 'max_tokens' },
      { state: 'idle' },
      { state: 'unknown' },
    ),
  ).toStrictEqual([
    'completed',
    'cancelled',
    ['failed', 'API Error: 529 Overloaded'],
    'failed',
    'ended',
    'ended',
    'untracked',
  ]);

  const lost = fold([
    { ...PROMPT, at: 1 },
    { ...spawned('a', 'Find'), at: 1 } as TranscriptAction,
    stood('a', { state: 'unknown' }, 5),
  ]);

  // Its time stands at the unknown, and it is not counted as running.
  expect(only(lost, 'a').endedAt).toStrictEqual(5);
  expect(runningSubagents(lost)).toStrictEqual(0);

  const back = fold(
    [
      stood('a', { state: 'running' }, 7),
      stood('a', { state: 'idle', stopReason: 'end_turn' }, 9),
    ],
    lost,
  );

  expect([only(back, 'a').state, only(back, 'a').endedAt]).toStrictEqual([
    'completed',
    9,
  ]);
  // Straight from untracked to idle, its time runs to the idle.
  expect(
    only(
      fold([stood('a', { state: 'idle', stopReason: 'end_turn' }, 8)], lost),
      'a',
    ).endedAt,
  ).toStrictEqual(8);
  // A later state clears a failure's message.
  expect(
    only(
      fold(
        [
          stood('a', {
            state: 'idle',
            stopReason: 'error',
            error: { code: 1, message: 'x' },
          }),
          stood('a', { state: 'running' }),
        ],
        lost,
      ),
      'a',
    ).error,
  ).toStrictEqual(undefined);
});

test("Claude's subagents fold to each end they report", () =>
  withSession(async (session) => {
    const transcript = fold(await play(session, 'claudesubagents'));

    expect(
      subagentsIn(transcript.entries).map(({ title, state, error }) => ({
        title,
        state,
        ...(error === undefined ? {} : { error }),
      })),
    ).toStrictEqual([
      { title: 'explorer (Explore)', state: 'completed' },
      {
        title: 'reviewer (general-purpose)',
        state: 'failed',
        error: 'API Error: 529 Overloaded',
      },
      { title: 'tester (general-purpose)', state: 'cancelled' },
      { title: 'watcher', state: 'untracked' },
    ]);
  }));

test('a cancelled turn cancels the subagents still running, when Esc was pressed; one that ended stays as it ended', () => {
  const transcript = fold([
    PROMPT,
    spawned('a', 'Find'),
    spawned('g', 'Read', { from: 'a' }),
    spawned('b', 'Draw'),
    ended('b', 'failed', { at: 9 }),
    { type: 'cancel', turnId: TURN, at: 12 },
    // The adapter's own word, after the turn's answer, agrees.
    {
      type: 'result',
      turnId: TURN,
      result: { status: 'cancelled', stopReason: 'cancelled' },
    },
    ended('a', 'cancelled', { at: 20 }),
  ]);

  expect(
    subagentsIn(transcript.entries).map(({ id, state, endedAt }) => ({
      id,
      state,
      endedAt,
    })),
  ).toStrictEqual([
    { id: 'a', state: 'cancelled', endedAt: 12 },
    { id: 'g', state: 'cancelled', endedAt: 12 },
    { id: 'b', state: 'failed', endedAt: 9 },
  ]);
  expect(runningSubagents(transcript)).toStrictEqual(0);
});

test('a turn that ends on its own leaves its subagents running, and they go on after it', () => {
  const answered = fold([
    PROMPT,
    spawned('a', 'Run the tests'),
    spawned('b', 'Read'),
    ended('b', 'completed'),
    {
      type: 'result',
      turnId: TURN,
      result: { status: 'completed', stopReason: 'end_turn' },
    },
  ]);

  expect(answered.turn).toStrictEqual({ status: 'idle' });
  expect(runningSubagents(answered)).toStrictEqual(1);

  const later = fold(
    [say('All passed.', 'a'), ended('a', 'completed')],
    answered,
  );

  expect(runningSubagents(later)).toStrictEqual(0);
  expect(shape(only(later, 'a').entries)).toStrictEqual([
    'assistant: All passed.',
  ]);
});

test("the agent's going disconnects the subagents still running, at any depth", () => {
  const transcript = fold([
    PROMPT,
    spawned('a', 'Find'),
    spawned('g', 'Read', { from: 'a' }),
    spawned('b', 'Draw'),
    ended('b', 'completed'),
    { type: 'disconnected', turnId: TURN, at: 30 },
  ]);

  expect(
    subagentsIn(transcript.entries).map(({ state, endedAt }) => [
      state,
      endedAt,
    ]),
  ).toStrictEqual([
    ['disconnected', 30],
    ['disconnected', 30],
    ['completed', undefined],
  ]);
});

test("a subagent's permission request is the turn's, findable by its call, and its answer goes into the subagent's work", () => {
  const options = [
    { optionId: 'allow', name: 'Allow', kind: 'allow_once' as const },
  ];
  const asked = fold([
    PROMPT,
    spawned('a', 'Find'),
    call('w1', 'in_progress', 'a'),
    {
      type: 'permission_requested',
      turnId: TURN,
      permission: {
        id: 'p1',
        subagentId: 'a',
        toolCallId: 'w1',
        title: 'Write notes.md',
        options,
      },
    },
  ]);

  expect(asked.turn.status).toStrictEqual('awaiting_permission');
  expect(waitingOn(asked, 'a', 'w1')?.id).toStrictEqual('p1');
  expect(waitingOn(asked, undefined, 'w1')).toStrictEqual(undefined);

  const answered = fold(
    [
      {
        type: 'permission_settled',
        turnId: TURN,
        id: 'p1',
        answer: { type: 'chosen', optionId: 'allow' },
      },
    ],
    asked,
  );

  expect(shape(answered.entries)).toStrictEqual([
    'user: look',
    { 'Find running': ['tool: Read w1 in_progress', 'permission'] },
  ]);
  expect(waitingOn(answered, 'a', 'w1')).toStrictEqual(undefined);
});

test("the session's tree takes a subagent its own updates or a subagent's announce, and no session it never opened", () => {
  const notice = (
    sessionId: string,
    update: SessionUpdate,
  ): SessionNotification => ({ sessionId, update });
  const announce = (id: string): SessionUpdate => ({
    sessionUpdate: 'subagent_update',
    sessionId: id,
  });
  const chunk: SessionUpdate = {
    sessionUpdate: 'agent_message_chunk',
    content: { type: 'text', text: 'hi' },
  };
  let tree = sessionTree('root');
  const hear = (notification: SessionNotification) => {
    const where = routed(tree, notification);

    tree = where.tree;

    return where.heard ? (where.subagentId ?? 'root') : 'dropped';
  };

  expect(hear(notice('a', chunk))).toStrictEqual('dropped');
  expect(hear(notice('root', announce('a')))).toStrictEqual('root');
  expect(hear(notice('a', chunk))).toStrictEqual('a');
  expect(hear(notice('a', announce('g')))).toStrictEqual('a');
  expect(hear(notice('g', chunk))).toStrictEqual('g');
  // A session nobody announced announces nothing.
  expect(hear(notice('other', announce('x')))).toStrictEqual('dropped');
  expect(hear(notice('x', chunk))).toStrictEqual('dropped');
  expect([...tree.subagents]).toStrictEqual(['a', 'g']);
});

async function withSession(
  body: (session: Session) => Promise<void>,
): Promise<void> {
  const dir = await mkdtemp(join(tmpdir(), 'chord-subagents-'));
  const session = await openSession({
    agent: 'fake',
    cwd: dir,
    agentCommand: FAKE,
  });

  try {
    await body(session);
  } finally {
    await session.close();
    await rm(dir, { recursive: true });
  }
}

/** The titles of the subagents the fake's `subagent` scenario starts. */
const TITLES = {
  find: 'Find the session layer',
  draw: 'Find where tool calls are drawn on screen and how they fold',
  read: 'Read the transport tests',
  tests: 'Run the whole test suite',
} as const;

/**
 * The ids of the `subagent` scenario's subagents, by the titles they were
 * announced with in `updates`: the fake's ids are opaque, fresh in each
 * process.
 */
function idsOf(
  updates: Iterable<SessionUpdate>,
): Record<keyof typeof TITLES, string> {
  const byTitle = new Map<string, string>();

  for (const update of updates) {
    if (update.sessionUpdate === 'subagent_update' && update.title) {
      byTitle.set(update.title, update.sessionId);
    }
  }

  const id = (key: keyof typeof TITLES) => {
    const found = byTitle.get(TITLES[key]);

    assert(found, `no subagent ${TITLES[key]}`);

    return found;
  };

  // Each looked up as it is read, as a run cut short announces only some.
  return {
    get find() {
      return id('find');
    },
    get draw() {
      return id('draw');
    },
    get read() {
      return id('read');
    },
    get tests() {
      return id('tests');
    },
  };
}

/** The updates among a transcript's actions. */
function updatesIn(actions: readonly TranscriptAction[]): SessionUpdate[] {
  return actions.flatMap((action) =>
    action.type === 'update' ? [action.update] : [],
  );
}

test("a subagent's updates reach its parent's session tagged with it, and none reads as the parent's", () =>
  withSession(async (session) => {
    const asked: PendingPermission[] = [];

    session.permissions.subscribe((request) => {
      asked.push(request);
      setTimeout(() => request.resolve('allow'), 10);
    });

    const ran = await run(session, 'subagent');
    const { find, draw, read, tests } = idsOf([
      ...ran.updates,
      ...ran.subagents.map(({ update }) => update),
    ]);

    expect(said(ran.updates)).toStrictEqual([
      'I will send two agents, one for each side.',
      'Now the tests, in the background.',
      'It is running; I will say when it ends.',
    ]);
    expect(
      ran.updates.filter((update) => update.sessionUpdate === 'tool_call'),
    ).toStrictEqual([]);
    expect(
      ran.updates.flatMap((update) =>
        update.sessionUpdate === 'subagent_update' ? [update.sessionId] : [],
      ),
    ).toStrictEqual([find, draw, draw, find, tests]);
    expect(
      [...new Set(ran.subagents.map((each) => each.subagentId))].toSorted(),
    ).toStrictEqual([find, draw, read, tests].toSorted());
    // The grandchild is announced on its parent's session, not the root's.
    expect(
      ran.subagents.some(
        ({ update, subagentId }) =>
          subagentId === find &&
          update.sessionUpdate === 'subagent_update' &&
          update.sessionId === read,
      ),
    ).toBeTruthy();
    // The child's request is answered like any other, its call named.
    expect(
      asked.map(({ sessionId, toolCall }) => [sessionId, toolCall.title]),
    ).toStrictEqual([[find, 'Write notes/routing.md']]);
    expect(ran.result.status).toStrictEqual('completed');
  }));

test('the subagent scenario folds every state CHD-151 draws, apart from the parent, live', () =>
  withSession(async (session) => {
    const actions = await play(session, 'subagent');
    const transcript = fold(actions);
    const { find } = idsOf(updatesIn(actions));

    expect(shape(transcript.entries)).toStrictEqual([
      'user: subagent',
      'assistant: I will send two agents, one for each side.',
      {
        'Find the session layer completed': [
          'thought: Looking for where updates are routed.',
          'tool: Search sessionUpdate in src completed',
          'tool: Read src/acp/connection.ts completed',
          {
            'Read the transport tests completed': [
              'tool: Read tests/acp/connection_test.ts completed',
              'tool: Search cancel in tests/acp/connection_test.ts completed',
              'assistant: Nothing it did not open is promised.',
            ],
          },
          'tool: Read src/session/session.ts completed',
          'tool: Write notes/routing.md completed',
          'permission',
          'assistant: The listeners are kept per sessionId in openAgent; an id chord did not open is dropped there.',
        ],
      },
      {
        'Find where tool calls are drawn on screen and how they fold failed': [
          'tool: Search function Tool in src/ui completed',
          'tool: Read src/ui/App.tsx failed',
          'assistant: Could not read the component.',
        ],
      },
      'assistant: Now the tests, in the background.',
      {
        'Run the whole test suite running': [
          'tool: deno task test in_progress',
        ],
      },
      'assistant: It is running; I will say when it ends.',
    ]);
    expect(transcript.plan).toStrictEqual([]);
    expect(
      only(transcript, find).plan.map((step) => step.status),
    ).toStrictEqual(['completed', 'completed', 'completed']);
    expect(only(transcript, find).planAt).toStrictEqual(1);
    expect(runningSubagents(transcript)).toStrictEqual(1);
  }));

test('Esc while a subagent asks withdraws its request, and every subagent still running ends cancelled', () =>
  withSession(async (session) => {
    const actions = await play(session, 'subagent', { answer: 'cancel' });
    const transcript = fold(actions);
    const { find, draw, read } = idsOf(updatesIn(actions));

    expect(transcript.turn).toStrictEqual({ status: 'idle' });
    expect(
      actions
        .filter((action) => action.type === 'permission_settled')
        .map(
          (action) =>
            action.type === 'permission_settled' && action.answer.type,
        ),
    ).toStrictEqual(['withdrawn']);
    expect(
      subagentsIn(transcript.entries).map(({ id, state }) => [id, state]),
    ).toStrictEqual([
      [find, 'cancelled'],
      [read, 'completed'],
      [draw, 'failed'],
    ]);
    // The agent's own word for the one it cancelled came too.
    expect(
      actions.some(
        (action) =>
          action.type === 'update' &&
          action.update.sessionUpdate === 'subagent_update' &&
          action.update.sessionId === find &&
          action.update.state?.state === 'cancelled',
      ),
    ).toBeTruthy();
    expect(shape(transcript.entries).at(-1)).toStrictEqual('cancelled');
  }));

test('a subagent that outlives its turn goes on reaching the session after the answer', () =>
  withSession(async (session) => {
    session.permissions.subscribe((request) =>
      setTimeout(() => request.resolve('allow'), 10),
    );

    const { promise: over, resolve } = Promise.withResolvers<void>();
    const after: TranscriptAction[] = [];
    let answered = false;
    let tests: string | undefined;

    session.subscribe((update, subagentId) => {
      if (
        update.sessionUpdate === 'subagent_update' &&
        update.title === TITLES.tests
      ) {
        tests = update.sessionId;
      }

      if (!answered) {
        return;
      }

      after.push({
        type: 'update',
        turnId: TURN,
        update,
        ...(subagentId === undefined ? {} : { subagentId }),
      });

      if (
        update.sessionUpdate === 'subagent_update' &&
        update.sessionId === tests
      ) {
        resolve();
      }
    });

    const live = fold(await play(session, 'subagent'));

    answered = true;

    expect(runningSubagents(live)).toStrictEqual(1);
    await over;

    const later = fold(after, live);

    expect(runningSubagents(later)).toStrictEqual(0);
    assert(tests !== undefined);
    expect(shape(only(later, tests).entries)).toStrictEqual([
      'tool: deno task test completed',
      'assistant: Every test passed.',
    ]);
  }));

test("an agent that sends ACP's own subagent_update folds the same way", () =>
  withSession(async (session) => {
    const transcript = fold(await play(session, 'subagentupdate'));

    expect(shape(transcript.entries)).toStrictEqual([
      'user: subagentupdate',
      {
        'Summarise the README ended': [
          'tool: Read README.md completed',
          'assistant: chord is a terminal client for ACP agents.',
        ],
      },
      'assistant: It says chord is a terminal client for ACP agents.',
    ]);
  }));

/**
 * Each subagent's title and the states its `subagent_update`s brought, in
 * order, among `actions`; and the text of the `session_message`s heard
 * under it.
 */
function reported(actions: readonly TranscriptAction[]) {
  const byId = new Map<
    string,
    { title?: string; states: unknown[]; messages: string[] }
  >();
  const of = (id: string) => {
    const found = byId.get(id) ?? { states: [], messages: [] };

    byId.set(id, found);

    return found;
  };

  for (const action of actions) {
    if (action.type !== 'update') {
      continue;
    }

    const { update, subagentId } = action;

    if (update.sessionUpdate === 'subagent_update') {
      const found = of(update.sessionId);

      if (update.title !== undefined && update.title !== null) {
        found.title = update.title;

        expect(update.capabilities).toStrictEqual({ cancel: {} });
      }

      if (update.state !== undefined && update.state !== null) {
        found.states.push(update.state);
      }
    } else if (
      update.sessionUpdate === 'session_message' &&
      subagentId !== undefined
    ) {
      for (const block of update.content ?? []) {
        if (block.type === 'text') {
          of(subagentId).messages.push(block.text);
        }
      }
    }
  }

  return [...byId.values()];
}

test("Claude's subagents come in ACP's own form, with their whole task, ending each way it reports", () =>
  withSession(async (session) => {
    const subagents = reported(await play(session, 'claudesubagents'));

    expect(subagents.map(({ title, states }) => ({ title, states }))).toEqual([
      {
        title: 'explorer (Explore)',
        states: [
          { state: 'running' },
          { state: 'requires_action' },
          { state: 'running' },
          { state: 'idle', stopReason: 'end_turn' },
        ],
      },
      {
        title: 'reviewer (general-purpose)',
        states: [
          { state: 'running' },
          {
            state: 'idle',
            stopReason: 'error',
            error: { code: -32603, message: 'API Error: 529 Overloaded' },
          },
        ],
      },
      {
        title: 'tester (general-purpose)',
        states: [
          { state: 'running' },
          { state: 'idle', stopReason: 'cancelled' },
        ],
      },
      {
        title: 'watcher',
        states: [{ state: 'running' }, { state: 'unknown' }],
      },
    ]);
    expect(subagents[0]!.messages).toStrictEqual([
      'Find where chord hands each session/update to its listeners and ' +
        'say which file owns the routing.\n\nReport paths and line ' +
        'numbers, and write what you find to notes/routing.md.',
    ]);
    expect(subagents.every(({ messages }) => messages.length === 1)).toBe(true);
  }));

test("a cancel ends Claude's subagents still at work idle and cancelled", () =>
  withSession(async (session) => {
    const actions = await play(session, 'claudesubagents', {
      answer: 'cancel',
    });

    expect(actions.at(-1)).toMatchObject({
      type: 'result',
      result: { status: 'cancelled' },
    });
    expect(reported(actions)[0]!.states).toStrictEqual([
      { state: 'running' },
      { state: 'requires_action' },
      { state: 'idle', stopReason: 'cancelled' },
    ]);
  }));

/**
 * What `claudebackground`'s subagents reported, through the background
 * one's end, after a cancel once `cancelAfterEvents` updates had come; and
 * how the turn ended.
 */
async function background(session: Session, cancelAfterEvents: number) {
  const after: TranscriptAction[] = [];
  let answered = false;
  const over = new Promise<void>((resolve) => {
    session.subscribe((update) => {
      if (!answered) {
        return;
      }

      after.push({ type: 'update', turnId: TURN, update });

      if (
        update.sessionUpdate === 'subagent_update' &&
        update.state?.state === 'idle'
      ) {
        resolve();
      }
    });
  });

  const actions = await play(session, 'claudebackground', {
    cancelAfterEvents,
  });

  answered = true;

  await over;

  return {
    result: actions.find((action) => action.type === 'result'),
    subagents: reported([...actions, ...after]).map(({ title, states }) => ({
      title,
      states,
    })),
  };
}

test("Claude's background subagent goes on past a cancel that stops the one the turn waits on", () =>
  withSession(async (session) => {
    const { subagents } = await background(session, 6);

    expect(subagents).toStrictEqual([
      {
        title: 'tester (general-purpose)',
        states: [
          { state: 'running' },
          { state: 'idle', stopReason: 'end_turn' },
        ],
      },
      {
        title: 'explorer (Explore)',
        states: [
          { state: 'running' },
          { state: 'idle', stopReason: 'cancelled' },
        ],
      },
    ]);
  }));

test("a cancel that comes before the next announcement leaves Claude's background subagent at work, to end on its own", () =>
  withSession(async (session) => {
    const { result, subagents } = await background(session, 3);

    expect(result).toMatchObject({ result: { status: 'cancelled' } });
    expect(subagents[0]).toStrictEqual({
      title: 'tester (general-purpose)',
      states: [{ state: 'running' }, { state: 'idle', stopReason: 'end_turn' }],
    });
  }));

test("-p prints the parent's reply alone, and refuses a subagent's request like any other", async () => {
  const dir = await mkdtemp(join(tmpdir(), 'chord-subagents-'));
  const reply: string[] = [];
  const refused: ToolCallUpdate[] = [];

  try {
    const outcome = await runOneshot({
      agent: 'fake',
      cwd: dir,
      prompt: 'subagent',
      agentCommand: FAKE,
      onUpdate: (update) => {
        if (
          update.sessionUpdate === 'agent_message_chunk' &&
          update.content.type === 'text'
        ) {
          reply.push(update.content.text);
        }
      },
      onRefused: (toolCall) => void refused.push(toolCall),
    });

    expect(outcome.result.status).toStrictEqual('completed');
    expect(reply).toStrictEqual([
      'I will send two agents, one for each side.',
      'Now the tests, in the background.',
      'It is running; I will say when it ends.',
    ]);
    expect(refused.map((call) => call.title)).toStrictEqual([
      'Write notes/routing.md',
    ]);
  } finally {
    await rm(dir, { recursive: true });
  }
});

/** The reducer's actions among what a conversation reported. */
function transcriptActions(
  events: readonly ConversationEvent[],
): TranscriptAction[] {
  const kinds = new Set([
    'prompt',
    'update',
    'result',
    'cancel',
    'disconnected',
    'permission_requested',
    'permission_settled',
  ]);

  return events.filter((event): event is TranscriptAction =>
    kinds.has(event.type),
  );
}

/** What a reopened session's history draws. */
function pastOf(session: Session): Transcript {
  return fold(
    session
      .history()
      .filter((action): action is TranscriptAction => action.type !== 'usage'),
  );
}

/**
 * The subagents of `transcript` as `shape` draws them, with their times. A
 * permission's answer is left out: the record keeps none, as the call's own
 * update says what came of it.
 */
function timed(transcript: Transcript) {
  return subagentsIn(transcript.entries).map(
    ({ title, state, startedAt, endedAt, entries }) => ({
      title,
      state,
      startedAt,
      endedAt,
      entries: shape(entries.filter((entry) => entry.kind !== 'permission')),
    }),
  );
}

test('a resumed session folds its subagents as they were live, times and all, and one left running is disconnected', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'chord-subagents-'));
  const stateDir = join(dir, 'state');
  const live: ConversationEvent[] = [];

  try {
    const id = await recordSession({
      stateDir,
      cwd: dir,
      command: FAKE,
      prompts: ['subagent'],
      heard: (event) => live.push(event),
      permit: true,
    });
    const record = await readPast((await readRecords(stateDir))[0]?.path ?? '');
    const { find, tests } = idsOf(updatesIn(transcriptActions(live)));

    expect(
      record.some(
        (entry) => entry.type === 'update' && entry.subagentId === find,
      ),
      "a subagent's update is recorded with its id",
    ).toBeTruthy();
    expect(
      record.some(
        (entry) =>
          entry.type === 'update' &&
          entry.at !== undefined &&
          entry.update.sessionUpdate === 'subagent_update',
      ),
      "a subagent's spawn is recorded with its time",
    ).toBeTruthy();

    const resume = sessionById(await readRecords(stateDir), id, {
      agent: 'fake',
      cwd: dir,
    });
    const session = await openSession({
      agent: 'fake',
      cwd: dir,
      agentCommand: RESUMING,
      resume,
    });

    try {
      const shown = fold(transcriptActions(live));
      // chord closed with the last one still running; reopened in another
      // agent, it is gone.
      const expected = fold([{ type: 'disconnected', turnId: TURN }], shown);

      expect(timed(pastOf(session))).toStrictEqual(timed(expected));
      expect(only(pastOf(session), tests).state).toStrictEqual('disconnected');
      expect(only(pastOf(session), tests).endedAt).toStrictEqual(undefined);
      expect(runningSubagents(pastOf(session))).toStrictEqual(0);
    } finally {
      await session.close();
    }
  } finally {
    await rm(dir, { recursive: true });
  }
});

test('subagents started again after a resume, in a new fake process, are new ones, and the old ones stay as they were (CHD-159)', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'chord-subagents-'));
  const stateDir = join(dir, 'state');
  /** The session as a fake reopened on its record draws it. */
  const reopened = async (id: string): Promise<Transcript> => {
    const session = await openSession({
      agent: 'fake',
      cwd: dir,
      agentCommand: RESUMING,
      resume: sessionById(await readRecords(stateDir), id, {
        agent: 'fake',
        cwd: dir,
      }),
    });

    try {
      return pastOf(session);
    } finally {
      await session.close();
    }
  };

  /** Each top-level entry as a short line, a subagent by its title. */
  const outline = (entries: readonly Entry[]) =>
    entries.map((entry) =>
      entry.kind === 'subagent'
        ? `subagent: ${entry.subagent.title}`
        : shape([entry])[0],
    );

  try {
    const id = await recordSession({
      stateDir,
      cwd: dir,
      command: FAKE,
      prompts: ['subagent'],
      permit: true,
    });
    const before = await reopened(id);

    await recordSession({
      stateDir,
      cwd: dir,
      command: RESUMING,
      prompts: ['subagent'],
      resume: sessionById(await readRecords(stateDir), id, {
        agent: 'fake',
        cwd: dir,
      }),
      permit: true,
    });

    const after = await reopened(id);
    const old = subagentsIn(before.entries);
    const oldIds = new Set(old.map((subagent) => subagent.id));
    const all = subagentsIn(after.entries);
    const fresh = all.filter((subagent) => !oldIds.has(subagent.id));

    expect(old).toHaveLength(4);
    // The old ones are as they were, states, times and all.
    expect(all.filter((subagent) => oldIds.has(subagent.id))).toStrictEqual(
      old,
    );
    // The new ones are as many, each its own, started in the same order.
    expect(new Set(fresh.map((subagent) => subagent.id)).size).toStrictEqual(4);
    expect(fresh.map((subagent) => subagent.title)).toStrictEqual(
      old.map((subagent) => subagent.title),
    );
    // Each new spawn is an entry of its own, between the reply's lines.
    expect(outline(after.entries)).toStrictEqual([
      ...outline(before.entries),
      ...outline(before.entries),
    ]);
  } finally {
    await rm(dir, { recursive: true });
  }
});

test('an agent that exits disconnects its running subagents then, and a resumed record says the same', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'chord-subagents-'));
  const stateDir = join(dir, 'state');
  const events: ConversationEvent[] = [];
  let session: Session | undefined;
  const { promise: gone, resolve } = Promise.withResolvers<void>();
  const { promise: up, resolve: connected } = Promise.withResolvers<void>();
  const conversation = new Conversation(
    (signal) =>
      openSession({
        agent: 'fake',
        cwd: dir,
        agentCommand: FAKE,
        signal,
      }).then((opened) => (session = opened)),
    (event) => {
      events.push(event);

      if (event.type === 'connected') {
        connected();
      }

      // Killed once the first subagent's grandchild is out.
      if (
        event.type === 'update' &&
        event.update.sessionUpdate === 'subagent_update' &&
        event.update.title === TITLES.read
      ) {
        process.kill([...(session?.agentPids ?? [])][0] ?? 0, 'SIGKILL');
      }

      if (event.type === 'disconnected') {
        resolve();
      }
    },
    Date.now,
    {},
    new FileRecording(stateDir, () => {}),
  );

  try {
    conversation.start();
    await up;
    conversation.send('subagent');
    await gone;

    const exit = events.find((event) => event.type === 'disconnected');
    const shown = fold(transcriptActions(events));
    const { find, read } = idsOf(updatesIn(transcriptActions(events)));

    assert(exit?.type === 'disconnected' && exit.at !== undefined);
    expect(
      [find, read].map((id) => {
        const { state, endedAt } = only(shown, id);

        return [state, endedAt];
      }),
    ).toStrictEqual([
      ['disconnected', exit.at],
      ['disconnected', exit.at],
    ]);
    expect(runningSubagents(shown)).toStrictEqual(0);
    await conversation.close();

    const [record] = await readRecords(stateDir);

    assert(record !== undefined);
    expect(
      (await readPast(record.path)).some(
        (entry) => entry.type === 'disconnected' && entry.at === exit.at,
      ),
    ).toBeTruthy();

    const resumed = await openSession({
      agent: 'fake',
      cwd: dir,
      agentCommand: RESUMING,
      resume: { sessionId: record.sessionId, cwd: dir, record: record.path },
    });

    try {
      expect(timed(pastOf(resumed))).toStrictEqual(timed(shown));
    } finally {
      await resumed.close();
    }
  } finally {
    await conversation.close();
    await rm(dir, { recursive: true });
  }
});

test("a record's updates are grouped by the session that sent each", () => {
  const usage: SessionUpdate = {
    sessionUpdate: 'usage_update',
    used: 1,
    size: 10,
  };
  const call: SessionUpdate = {
    sessionUpdate: 'tool_call',
    toolCallId: 'c1',
    title: 'Read a.ts',
  };

  expect(
    pastBySession('root', [
      { type: 'update', turnId: TURN, update: usage },
      { type: 'update', turnId: TURN, update: call, subagentId: 'child' },
      { type: 'cancel', turnId: TURN, at: 1 },
      { type: 'update', turnId: TURN, update: usage, subagentId: 'child' },
    ]),
  ).toStrictEqual(
    new Map([
      ['root', [usage]],
      ['child', [call, usage]],
    ]),
  );
});

test("a resumed child's cost never counts as the parent's", async () => {
  /** The cost chord fills in for the parent's next turn, resumed from `extra`. */
  const resumedCost = async (extra: readonly RecordEntry[]) => {
    const dir = await mkdtemp(join(tmpdir(), 'chord-subagents-'));
    const path = join(dir, 'record.jsonl');
    const entries: RecordEntry[] = [
      {
        type: 'update',
        turnId: TURN,
        update: {
          sessionUpdate: 'usage_update',
          used: 100,
          size: 1000,
          cost: { amount: 0.1, currency: 'USD' },
          _meta: { [FILLED]: ['cost'] },
        },
      },
      ...extra,
    ];

    await writeFile(
      path,
      entries.map((entry) => JSON.stringify(entry)).join('\n') + '\n',
    );

    const session = await openSession({
      agent: 'fake',
      cwd: dir,
      agentCommand: fakeAgentCommand(
        undefined,
        '--resume-only',
        '--tokens-only',
      ),
      resume: { sessionId: crypto.randomUUID(), cwd: dir, record: path },
    });

    try {
      const { updates } = await run(session, 'text');

      return updates.flatMap((update) =>
        update.sessionUpdate === 'usage_update' ? [update.cost?.amount] : [],
      );
    } finally {
      await session.close();
      await rm(dir, { recursive: true });
    }
  };

  const alone = await resumedCost([]);

  expect(alone.length).toStrictEqual(1);
  expect(
    await resumedCost([
      {
        type: 'update',
        turnId: TURN,
        subagentId: 'child',
        update: {
          sessionUpdate: 'usage_update',
          used: 999,
          size: 9999,
          cost: { amount: 99, currency: 'USD' },
        },
      },
    ]),
  ).toStrictEqual(alone);
});

describe('CHD-432 tester: independent Claude fixture lifetimes', () => {
  test('a background child finishes under its own id after the parent takes another prompt', () =>
    withSession(async (session) => {
      const actions: TranscriptAction[] = [];
      const { promise: ended, resolve } = Promise.withResolvers<void>();
      let childId: string | undefined;
      const unsubscribe = session.subscribe((update, subagentId) => {
        actions.push({
          type: 'update',
          turnId: TURN,
          update,
          ...(subagentId === undefined ? {} : { subagentId }),
        });

        if (
          update.sessionUpdate === 'subagent_update' &&
          update.title === 'tester (general-purpose)'
        ) {
          childId = update.sessionId;
        }

        if (
          update.sessionUpdate === 'subagent_update' &&
          update.sessionId === childId &&
          update.state?.state === 'idle'
        ) {
          resolve();
        }
      });

      try {
        const first = await run(session, 'claudebackground');

        expect(first.result.status).toBe('completed');
        expect(reported(actions)[0]?.states).toStrictEqual([
          { state: 'running' },
        ]);

        const next = await run(session, 'text');

        expect(next.result.status).toBe('completed');
        expect(said(next.updates).join('')).toContain('Hello, world.');
        await ended;
        expect(reported(actions)[0]?.states).toStrictEqual([
          { state: 'running' },
          { state: 'idle', stopReason: 'end_turn' },
        ]);
        expect(
          actions.some(
            (action) =>
              action.type === 'update' &&
              action.subagentId === childId &&
              action.update.sessionUpdate === 'agent_message_chunk' &&
              action.update.content.type === 'text' &&
              action.update.content.text === 'Every test passed.',
          ),
        ).toBe(true);
      } finally {
        unsubscribe();
      }
    }));

  test('cancelling one session leaves another session free to reject a child permission and finish', () =>
    withSession((cancelled) =>
      withSession(async (other) => {
        const [backgroundRun, actions] = await Promise.all([
          background(cancelled, 3),
          play(other, 'claudesubagents', { answer: 'reject' }),
        ]);

        expect(backgroundRun.result).toMatchObject({
          result: { status: 'cancelled' },
        });
        expect(backgroundRun.subagents[0]?.states).toStrictEqual([
          { state: 'running' },
          { state: 'idle', stopReason: 'end_turn' },
        ]);
        expect(actions.at(-1)).toMatchObject({
          type: 'result',
          result: { status: 'completed' },
        });
        expect(reported(actions)[0]?.states).toStrictEqual([
          { state: 'running' },
          { state: 'requires_action' },
          { state: 'running' },
          { state: 'idle', stopReason: 'end_turn' },
        ]);
        expect(
          actions.some(
            (action) =>
              action.type === 'update' &&
              action.subagentId !== undefined &&
              action.update.sessionUpdate === 'tool_call_update' &&
              action.update.status === 'failed',
          ),
        ).toBe(true);
      }),
    ));
});
