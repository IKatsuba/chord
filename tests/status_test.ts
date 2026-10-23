import { describe, expect, test } from 'bun:test';
import type { ConversationEvent } from '../src/session/conversation.ts';
import {
  hear,
  keyed,
  noAgents,
  openChild,
  openMain,
  pick,
  type WindowAgents,
} from '../src/session/window_agents.ts';
import { openSessionLabel } from '../src/session/sessions.ts';
import { shellContext, withContext } from '../src/session/context.ts';
import { wrapMessage } from '../src/session/tasks.ts';
import {
  MESSAGE_BYTES,
  messageLine,
  programStatus,
  sameStatus,
  TITLE_BYTES,
} from '../src/status.ts';

/**
 * The window for `agents`: main on the first, a child on each other, by
 * that name, the last opened picked.
 */
function opened(...agents: string[]): WindowAgents<string> {
  const [first, ...rest] = agents;
  const all = rest.reduce(
    (window, name) =>
      openChild(window, { id: name, name, runtime: name, openedAt: 0 }, name)!
        .agents,
    openMain(noAgents<string>(), first!, first!),
  );

  return pick(all, all.nextKey - 1);
}

/** Plays events into agent `key`, each a second after the last from `at`. */
function heard(
  tabs: WindowAgents<string>,
  key: number,
  events: readonly ConversationEvent[],
  at = 0,
): WindowAgents<string> {
  return events.reduce(
    (tabs, event, index) => hear(tabs, key, event, at + index * 1000).agents,
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
      { id: 'child', name: 'tester', runtime: 'fake', openedAt: 0 },
      'tester',
    )!;
    const done = heard(child.agents, child.key, [up, prompt('c'), ended('c')]);

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

  test('a failed child turn clears on a key, leaving main working', () => {
    const running = heard(opened('first', 'second'), 1, [up, prompt('a')]);
    const failure = heard(running, 2, [up, prompt('b'), failed('b')]);

    expect(programStatus(failure).state).toBe('error');
    expect(programStatus(keyed(failure))).toStrictEqual({
      state: 'working',
      app: 'chord',
    });
  });

  test('equal-age requests choose main first, then its child', () => {
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
      message: 'first needs your permission: Write notes.txt',
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
      message: 'second asks for input: Sign in',
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
  expect(programStatus(noAgents())).toStrictEqual({
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
    message: 'fake is waiting for your input',
  });
  expect(programStatus(pick(behind, 1)).state).toStrictEqual('idle');
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
    message: "c's turn failed",
  });
  expect(
    programStatus(heard(failing, 2, [permission('t2', 'p1')], 9000)),
  ).toStrictEqual({
    state: 'blocked',
    app: 'chord',
    kind: 'permission',
    message: 'b needs your permission: Write notes.txt',
  });

  // With nothing working, the reply behind shows.
  expect(programStatus(heard(base, 2, [ended('t2')], 9000))).toStrictEqual({
    state: 'done',
    app: 'chord',
    message: 'a is waiting for your input',
  });
});

test('of several agents in one state, the record names the one waiting longest, a child as its notification does', () => {
  const tabs = openChild(
    heard(opened('fake'), 1, [up, prompt('t1')]),
    { id: 'c1', name: 'tester', runtime: 'codex', openedAt: 0 },
    'tester',
  )!;
  const both = heard(
    heard(
      tabs.agents,
      tabs.key,
      [up, prompt('c'), permission('c', 'p2')],
      1000,
    ),
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

describe("the record's title names the main session (CHD-491)", () => {
  const working = heard(opened('fake'), 1, [up, prompt('t1')]);

  test('it goes with every state while the session has a name, and is left out while it has none', () => {
    expect(programStatus(noAgents(), 'Fix the tokenizer')).toStrictEqual({
      state: 'idle',
      app: 'chord',
      title: 'Fix the tokenizer',
    });
    expect(programStatus(working, 'Fix the tokenizer')).toStrictEqual({
      state: 'working',
      app: 'chord',
      title: 'Fix the tokenizer',
    });
    expect(
      programStatus(heard(working, 1, [ended('t1')]), 'Fix the tokenizer'),
    ).toMatchObject({ state: 'done', title: 'Fix the tokenizer' });

    for (const none of [undefined, '', '  ', '\n']) {
      expect(programStatus(working, none)).toStrictEqual({
        state: 'working',
        app: 'chord',
      });
    }
  });

  test('it is one line, cut to 192 UTF-8 bytes, 256 once base64-encoded, on a character’s edge', () => {
    const bytes = (text: string) => new TextEncoder().encode(text).length;
    const title = (text: string) => {
      const status = programStatus(noAgents(), text);

      return 'title' in status ? (status.title ?? '') : '';
    };

    expect(TITLE_BYTES).toStrictEqual(192);
    expect(title('Fix\nthe\ttokenizer')).toStrictEqual('Fix the tokenizer');
    expect(title('a'.repeat(193))).toStrictEqual('a'.repeat(192));
    // Two bytes each: 96 fit, the 97th would cross the bound.
    expect(title('é'.repeat(97))).toStrictEqual('é'.repeat(96));

    // A joined emoji, 11 bytes, stays whole or goes whole.
    const coder = '👩‍💻';

    expect(title(`${'a'.repeat(181)}${coder}`)).toStrictEqual(
      `${'a'.repeat(181)}${coder}`,
    );
    expect(title(`${'a'.repeat(182)}${coder}`)).toStrictEqual('a'.repeat(182));
    // An accent on its letter: the pair stays whole.
    expect(title(`${'a'.repeat(190)}é`)).toStrictEqual('a'.repeat(190));

    for (const text of ['a'.repeat(400), 'é'.repeat(400), coder.repeat(40)]) {
      expect(bytes(title(text))).toBeLessThanOrEqual(192);
      expect(
        Buffer.from(title(text)).toString('base64').length,
      ).toBeLessThanOrEqual(256);
    }
  });

  test("it is the session's first prompt as /resume names it: typed, a message, or only a command's output; none before the first", () => {
    expect(openSessionLabel(undefined)).toStrictEqual(undefined);
    expect(openSessionLabel('')).toStrictEqual(undefined);
    expect(openSessionLabel('  Fix the\n tokenizer  ')).toStrictEqual(
      'Fix the tokenizer',
    );
    expect(
      openSessionLabel(wrapMessage({ name: 'main' }, 'Review the diff')),
    ).toStrictEqual('Review the diff');
    expect(
      openSessionLabel(
        withContext(
          shellContext([
            { command: 'ls', stdout: 'a', stderr: '', running: false, code: 0 },
          ]),
          '',
        ),
      ),
    ).toStrictEqual('!ls');
  });
});
