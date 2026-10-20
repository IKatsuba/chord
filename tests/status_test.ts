import { describe, expect, test } from 'bun:test';
import type { ConversationEvent } from '../src/session/conversation.ts';
import {
  hear,
  keyed,
  noTabs,
  openChild,
  openTab,
  pick,
  show,
  type Tabs,
} from '../src/session/tabs.ts';
import {
  MESSAGE_BYTES,
  messageLine,
  programStatus,
  sameStatus,
} from '../src/status.ts';

/** Tabs for `agents`, opened in order, the last in front. */
function opened(...agents: string[]): Tabs<string> {
  return agents.reduce(
    (tabs, agent) => openTab(tabs, agent, agent)!.tabs,
    noTabs<string>(),
  );
}

/** Plays events into agent `key`, each a second after the last from `at`. */
function heard(
  tabs: Tabs<string>,
  key: number,
  events: readonly ConversationEvent[],
  at = 0,
): Tabs<string> {
  return events.reduce(
    (tabs, event, index) => hear(tabs, key, event, at + index * 1000).tabs,
    tabs,
  );
}

const up: ConversationEvent = { type: 'connected', sessionId: 's' };

describe('CHD-382 U1 tester: status lifecycle and message boundaries', () => {
  test('a late completed result after cancel stays idle', () => {
    const cancelled = heard(opened('fake'), 1, [
      up,
      prompt('late'),
      { type: 'cancel', turnId: 'late', at: 1000 },
      ended('late'),
    ]);

    expect(programStatus(cancelled)).toStrictEqual({
      state: 'idle',
      app: 'chord',
    });
  });

  test('keys on the parent leave a completed child done until it is picked', () => {
    const child = openChild(
      heard(opened('fake'), 1, [up]),
      1,
      { id: 'child', name: 'tester', runtime: 'fake', openedAt: 0 },
      'tester',
    )!;
    const done = heard(child.tabs, child.key, [up, prompt('c'), ended('c')]);

    expect(programStatus(keyed(done))).toStrictEqual({
      state: 'done',
      app: 'chord',
      message: 'tester is waiting for your input',
    });
    expect(programStatus(pick(done, child.key))).toStrictEqual({
      state: 'idle',
      app: 'chord',
    });
  });

  test('a failed front turn clears on a key, leaving another tab working', () => {
    const running = heard(opened('first', 'second'), 1, [up, prompt('a')]);
    const failure = heard(running, 2, [up, prompt('b'), failed('b')]);

    expect(programStatus(failure).state).toBe('error');
    expect(programStatus(keyed(failure))).toStrictEqual({
      state: 'working',
      app: 'chord',
    });
  });

  test('equal-age requests choose the leftmost tab and expose the next after settlement', () => {
    const first = heard(opened('first', 'second'), 1, [
      up,
      prompt('a'),
      permission('a', 'pa'),
    ]);
    const both = heard(first, 2, [up, prompt('b'), link('b', 'eb')]);

    expect(programStatus(both)).toStrictEqual({
      state: 'blocked',
      app: 'chord',
      kind: 'permission',
      message: 'first (1) needs your permission: Write notes.txt',
    });

    const answered = heard(both, 1, [
      {
        type: 'permission_settled',
        turnId: 'a',
        id: 'pa',
        answer: { type: 'withdrawn' },
      },
    ]);

    expect(programStatus(answered)).toStrictEqual({
      state: 'blocked',
      app: 'chord',
      kind: 'auth',
      message: 'second (2) asks for input: Sign in',
    });
  });

  test('four-byte text fits whole and every C0, DEL and C1 control becomes a space', () => {
    const controls = Array.from({ length: 160 }, (_, code) =>
      code < 32 || code >= 127 ? String.fromCharCode(code) : '',
    ).join('');

    expect(messageLine(controls)).toBe(' '.repeat(65));
    expect(messageLine(`${'a'.repeat(2044)}😀x`)).toBe(`${'a'.repeat(2044)}😀`);
    expect(messageLine(`${'a'.repeat(2045)}😀x`)).toBe('a'.repeat(2045));
  });
});

function prompt(turnId: string): ConversationEvent {
  return { type: 'prompt', turnId, text: 'hi', at: 0 };
}

function ended(turnId: string): ConversationEvent {
  return {
    type: 'result',
    turnId,
    result: { status: 'completed', stopReason: 'end_turn' },
  };
}

function failed(turnId: string): ConversationEvent {
  return {
    type: 'result',
    turnId,
    result: { status: 'failed', error: { message: 'boom' } },
  };
}

function permission(turnId: string, id: string): ConversationEvent {
  return {
    type: 'permission_requested',
    turnId,
    permission: { id, title: 'Write notes.txt', options: [] },
  };
}

function link(turnId: string, id: string): ConversationEvent {
  return {
    type: 'elicitation_requested',
    turnId,
    elicitation: {
      id,
      mode: 'url',
      message: 'Sign in',
      url: 'https://example.com/login',
    },
  };
}

function form(turnId: string, id: string): ConversationEvent {
  return {
    type: 'elicitation_requested',
    turnId,
    elicitation: {
      id,
      mode: 'form',
      message: 'Pick a name',
      schema: { type: 'object', properties: {} },
    },
  };
}

test('no agent doing anything is idle, and every report names chord', () => {
  expect(programStatus(noTabs())).toStrictEqual({
    state: 'idle',
    app: 'chord',
  });
  expect(programStatus(heard(opened('fake'), 1, [up]))).toStrictEqual({
    state: 'idle',
    app: 'chord',
  });
});

test('a turn running is working, with no message', () => {
  expect(
    programStatus(heard(opened('fake'), 1, [up, prompt('t1')])),
  ).toStrictEqual({ state: 'working', app: 'chord' });
});

test('a permission, a form and a link block, each by its kind and worded as its notification', () => {
  const running = heard(opened('fake'), 1, [up, prompt('t1')]);

  expect(
    programStatus(heard(running, 1, [permission('t1', 'p1')], 5000)),
  ).toStrictEqual({
    state: 'blocked',
    app: 'chord',
    kind: 'permission',
    message: 'fake needs your permission: Write notes.txt',
  });
  expect(
    programStatus(heard(running, 1, [form('t1', 'e1')], 5000)),
  ).toStrictEqual({
    state: 'blocked',
    app: 'chord',
    kind: 'question',
    message: 'fake asks for input: Pick a name',
  });
  expect(
    programStatus(heard(running, 1, [link('t1', 'e1')], 5000)),
  ).toStrictEqual({
    state: 'blocked',
    app: 'chord',
    kind: 'auth',
    message: 'fake asks for input: Sign in',
  });
});

test("a turn that ended in front is done until the person's next key or the next turn", () => {
  const done = heard(opened('fake'), 1, [up, prompt('t1'), ended('t1')]);

  expect(programStatus(done)).toStrictEqual({
    state: 'done',
    app: 'chord',
    message: 'fake is waiting for your input',
  });
  expect(programStatus(keyed(done)).state).toStrictEqual('idle');
  expect(
    programStatus(heard(done, 1, [prompt('t2')], 5000)).state,
  ).toStrictEqual('working');
});

test('a tab behind stays done through keys until it is visited', () => {
  // Tab 1 is behind tab 2.
  const behind = heard(opened('fake', 'claude'), 1, [
    up,
    prompt('t1'),
    ended('t1'),
  ]);

  expect(programStatus(keyed(behind))).toStrictEqual({
    state: 'done',
    app: 'chord',
    message: 'fake (1) is waiting for your input',
  });
  expect(programStatus(show(behind, 1)).state).toStrictEqual('idle');
});

test('an Esc-cancelled turn and a monitor-started turn are idle when they end', () => {
  const cancelled = heard(opened('fake'), 1, [
    up,
    prompt('t1'),
    { type: 'cancel', turnId: 't1', at: 1 },
    {
      type: 'result',
      turnId: 't1',
      result: { status: 'cancelled', stopReason: 'cancelled' },
    },
  ]);
  const monitor = heard(opened('fake'), 1, [
    up,
    {
      type: 'prompt',
      turnId: 't1',
      text: 'log',
      at: 0,
      from: { monitor: { id: 'm1' } },
    } as ConversationEvent,
    ended('t1'),
  ]);

  expect(programStatus(cancelled).state).toStrictEqual('idle');
  expect(programStatus(monitor).state).toStrictEqual('idle');
});

test('a failed turn, an agent that never came up and one that exited are errors that name the failure', () => {
  expect(
    programStatus(heard(opened('fake'), 1, [up, prompt('t1'), failed('t1')])),
  ).toStrictEqual({
    state: 'error',
    app: 'chord',
    message: "fake's turn failed",
  });
  expect(
    programStatus(
      heard(opened('fake'), 1, [{ type: 'connect_failed', message: 'nope' }]),
    ),
  ).toStrictEqual({
    state: 'error',
    app: 'chord',
    message: 'fake failed to start',
  });

  const exited = heard(opened('fake'), 1, [
    up,
    { type: 'disconnected', turnId: '' },
  ]);

  expect(programStatus(exited)).toStrictEqual({
    state: 'error',
    app: 'chord',
    message: 'fake exited',
  });
  // An agent gone stays gone, keys or not.
  expect(programStatus(keyed(exited)).state).toStrictEqual('error');
});

test('every agent folds as blocked, then error, then working, then done, then idle', () => {
  // Tab 1 replied behind, tab 2 works, tab 3 (in front) is idle.
  const base = heard(
    heard(opened('a', 'b', 'c'), 1, [up, prompt('t1'), ended('t1')]),
    2,
    [up, prompt('t2')],
  );

  expect(programStatus(base).state).toStrictEqual('working');

  const failing = heard(base, 3, [up, prompt('t3'), failed('t3')], 5000);

  expect(programStatus(failing)).toStrictEqual({
    state: 'error',
    app: 'chord',
    message: "c (3)'s turn failed",
  });
  expect(
    programStatus(heard(failing, 2, [permission('t2', 'p1')], 9000)),
  ).toStrictEqual({
    state: 'blocked',
    app: 'chord',
    kind: 'permission',
    message: 'b (2) needs your permission: Write notes.txt',
  });

  // With nothing working, the reply behind shows.
  expect(programStatus(heard(base, 2, [ended('t2')], 9000))).toStrictEqual({
    state: 'done',
    app: 'chord',
    message: 'a (1) is waiting for your input',
  });
});

test('of several agents in one state, the record names the one waiting longest, a child as its notification does', () => {
  const tabs = openChild(
    heard(opened('fake'), 1, [up, prompt('t1')]),
    1,
    { id: 'c1', name: 'tester', runtime: 'codex', openedAt: 0 },
    'tester',
  )!;
  const both = heard(
    heard(tabs.tabs, tabs.key, [up, prompt('c'), permission('c', 'p2')], 1000),
    1,
    [permission('t1', 'p1')],
    9000,
  );

  expect(programStatus(both)).toStrictEqual({
    state: 'blocked',
    app: 'chord',
    kind: 'permission',
    message: 'tester needs your permission: Write notes.txt',
  });
});

test('a message is one line with no control characters, cut to the bytes the protocol takes', () => {
  expect(messageLine('a\nb\u001b[31mc\u0085d')).toStrictEqual('a b [31mc d');

  const long = messageLine('é'.repeat(MESSAGE_BYTES));

  expect(new TextEncoder().encode(long).length).toStrictEqual(MESSAGE_BYTES);
  expect(long).toStrictEqual('é'.repeat(MESSAGE_BYTES / 2));
  // A character that would cross the bound is left out whole.
  expect(messageLine(`a${'é'.repeat(MESSAGE_BYTES)}`).length).toStrictEqual(
    MESSAGE_BYTES / 2,
  );
});

test('two reports are the same only when every field is', () => {
  expect(
    sameStatus(
      { state: 'idle', app: 'chord' },
      { state: 'idle', app: 'chord' },
    ),
  ).toStrictEqual(true);
  expect(
    sameStatus(
      { state: 'idle', app: 'chord' },
      { state: 'working', app: 'chord' },
    ),
  ).toStrictEqual(false);
  expect(
    sameStatus(
      { state: 'blocked', app: 'chord', kind: 'permission', message: 'x' },
      { state: 'blocked', app: 'chord', kind: 'question', message: 'x' },
    ),
  ).toStrictEqual(false);
  expect(
    sameStatus(
      { state: 'done', app: 'chord', message: 'a' },
      { state: 'done', app: 'chord', message: 'b' },
    ),
  ).toStrictEqual(false);
  expect(sameStatus({ state: 'clear' }, { state: 'clear' })).toStrictEqual(
    true,
  );
});
