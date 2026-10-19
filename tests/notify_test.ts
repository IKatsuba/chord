import { describe, expect, test } from 'bun:test';
import {
  emptyWatch,
  type NotifChannel,
  notificationBytes,
  notify,
  resolveChannel,
  type TerminalEnv,
  terminalEnv,
  type Watch,
} from '../src/notify.ts';
import type { ConversationEvent } from '../src/session/conversation.ts';

const ITERM: TerminalEnv = { termProgram: 'iTerm.app', tmux: false };
const APPLE: TerminalEnv = { termProgram: 'Apple_Terminal', tmux: false };
const TMUX: TerminalEnv = {
  termProgram: 'tmux',
  term: 'tmux-256color',
  tmux: true,
};

const connected: ConversationEvent = { type: 'connected', sessionId: 's' };
const prompt = (turnId: string): ConversationEvent => ({
  type: 'prompt',
  turnId,
  text: 'hello',
  at: 0,
});
const ended = (
  turnId: string,
  status: 'completed' | 'cancelled' = 'completed',
): ConversationEvent => ({
  type: 'result',
  turnId,
  result: { status, stopReason: status === 'cancelled' ? status : 'end_turn' },
});
const asked = (turnId: string, id: string): ConversationEvent => ({
  type: 'permission_requested',
  turnId,
  permission: { id, title: 'Write notes.txt', options: [] },
});

/** Every event in turn, and the bytes each wrote. */
function play(
  events: readonly ConversationEvent[],
  channel: NotifChannel = 'osc9',
  env: TerminalEnv = ITERM,
): { watch: Watch; written: string[] } {
  let watch = emptyWatch;
  const written: string[] = [];

  for (const event of events) {
    const seen = notify(watch, event, { channel, env }, 'claude');

    watch = seen.watch;

    if (seen.bytes !== undefined) {
      written.push(seen.bytes);
    }
  }

  return { watch, written };
}

test('a finished turn writes the channel chosen', () => {
  const turn = [connected, prompt('t1'), ended('t1')];

  expect(play(turn, 'osc9').written).toStrictEqual([
    '\x1b]9;claude is waiting for your input\x07',
  ]);
  expect(play(turn, 'osc777').written).toStrictEqual([
    '\x1b]777;notify;chord;claude is waiting for your input\x07',
  ]);
  expect(play(turn, 'bell').written).toStrictEqual(['\x07']);
  expect(play(turn, 'off').written).toStrictEqual([]);
});

test('a failed turn waits on the person too', () => {
  expect(
    play([
      connected,
      prompt('t1'),
      {
        type: 'result',
        turnId: 't1',
        result: { status: 'failed', error: { message: 'boom' } },
      },
    ]).written.length,
  ).toStrictEqual(1);
});

test('auto is OSC 9 where the terminal shows it, OSC 777 on foot, BEL elsewhere', () => {
  for (const env of [
    ITERM,
    { termProgram: 'WezTerm', tmux: false },
    { termProgram: 'ghostty', tmux: false },
    { term: 'xterm-ghostty', tmux: false },
    { term: 'xterm-kitty', tmux: false },
  ]) {
    expect(resolveChannel('auto', env), JSON.stringify(env)).toStrictEqual(
      'osc9',
    );
  }

  expect(resolveChannel('auto', { term: 'foot', tmux: false })).toStrictEqual(
    'osc777',
  );
  expect(resolveChannel('auto', APPLE)).toStrictEqual('bell');
  expect(resolveChannel('auto', { tmux: false })).toStrictEqual('bell');
  expect(resolveChannel('bell', ITERM)).toStrictEqual('bell');
});

test('inside tmux auto rings the bell, and a chosen OSC goes through passthrough', () => {
  const turn = [connected, prompt('t1'), ended('t1')];

  expect(resolveChannel('auto', { ...ITERM, tmux: true })).toStrictEqual(
    'bell',
  );
  expect(play(turn, 'auto', TMUX).written).toStrictEqual(['\x07']);
  expect(play(turn, 'osc9', TMUX).written).toStrictEqual([
    '\x1bPtmux;\x1b\x1b]9;claude is waiting for your input\x07\x1b\\',
  ]);
  expect(play(turn, 'osc777', TMUX).written).toStrictEqual([
    '\x1bPtmux;\x1b\x1b]777;notify;chord;claude is waiting for your input\x07\x1b\\',
  ]);
  expect(play(turn, 'bell', TMUX).written).toStrictEqual(['\x07']);
});

test('the environment says the terminal and whether tmux is between', () => {
  const env = (vars: Record<string, string>) =>
    terminalEnv((name) => vars[name]);

  expect(
    env({
      TERM_PROGRAM: 'iTerm.app',
      TERM: 'xterm-256color',
    }),
  ).toStrictEqual({
    termProgram: 'iTerm.app',
    term: 'xterm-256color',
    tmux: false,
  });
  expect(env({ TMUX: '/tmp/tmux-1/default,1,0' }).tmux).toStrictEqual(true);
  expect(env({ TMUX: '' }).tmux).toStrictEqual(false);
});

test('a turn cancelled with Esc writes nothing', () => {
  expect(
    play([
      connected,
      prompt('t1'),
      { type: 'cancel', turnId: 't1', at: 1 },
      ended('t1'),
    ]).written,
  ).toStrictEqual([]);
  // The agent's own word for it is enough.
  expect(
    play([connected, prompt('t1'), ended('t1', 'cancelled')]).written,
  ).toStrictEqual([]);
  // And the turn after it notifies again.
  expect(
    play([
      connected,
      prompt('t1'),
      { type: 'cancel', turnId: 't1', at: 1 },
      ended('t1'),
      prompt('t2'),
      ended('t2'),
    ]).written.length,
  ).toStrictEqual(1);
});

test('a permission request writes its own notification, once while any is open', () => {
  const { written } = play([
    connected,
    prompt('t1'),
    asked('t1', 'p1'),
    asked('t1', 'p2'),
    {
      type: 'permission_settled',
      turnId: 't1',
      id: 'p1',
      answer: { type: 'chosen', optionId: 'allow' },
    },
    {
      type: 'permission_settled',
      turnId: 't1',
      id: 'p2',
      answer: { type: 'chosen', optionId: 'allow' },
    },
    asked('t1', 'p3'),
  ]);

  expect(written).toStrictEqual([
    '\x1b]9;claude needs your permission: Write notes.txt\x07',
    '\x1b]9;claude needs your permission: Write notes.txt\x07',
  ]);
});

test('a turn with a queued prompt behind it is no wait', () => {
  expect(
    play([
      connected,
      prompt('t1'),
      { type: 'queued', turnId: 't2', text: 'next' },
      ended('t1'),
      prompt('t2'),
      ended('t2'),
    ]).written.length,
  ).toStrictEqual(1);
});

test("a resumed session's replayed turns write nothing", () => {
  expect(play([prompt('old'), ended('old'), connected]).written).toStrictEqual(
    [],
  );
  // `/clear` and `/resume` start over: the next session's past is replayed too.
  expect(
    play([connected, { type: 'cleared' }, prompt('old'), ended('old')]).written,
  ).toStrictEqual([]);
});

test('what the agent says cannot end the escape early or add a field', () => {
  const bytes = (channel: NotifChannel) =>
    notificationBytes(
      { kind: 'permission', title: 'Run a; b\x07\x1b]9;x' },
      channel,
      ITERM,
      'claude',
    );

  expect(bytes('osc9')).toStrictEqual(
    '\x1b]9;claude needs your permission: Run a; b  ]9;x\x07',
  );
  expect(bytes('osc777')).toStrictEqual(
    '\x1b]777;notify;chord;claude needs your permission: Run a, b  ]9,x\x07',
  );
});

test('a form the agent asks for writes its message, once while it is open', () => {
  const form = (id: string): ConversationEvent => ({
    type: 'elicitation_requested',
    turnId: 't1',
    elicitation: {
      id,
      mode: 'form',
      message: 'Set up the deploy target',
      schema: {},
    },
  });
  const settled: ConversationEvent = {
    type: 'elicitation_settled',
    turnId: 't1',
    id: 'e1',
    answer: { type: 'declined' },
  };

  expect(
    play([connected, prompt('t1'), form('e1'), form('e2')]).written,
  ).toStrictEqual([
    '\x1b]9;claude asks for input: Set up the deploy target\x07',
  ]);
  expect(
    play([connected, prompt('t1'), form('e1'), settled]).watch.asking.size,
  ).toStrictEqual(0);
});

test("a turn a monitor's event started writes nothing; its end's turn and a permission inside one do", () => {
  const event = (turnId: string, end?: true): ConversationEvent => ({
    type: 'prompt',
    turnId,
    text: 'ERROR',
    at: 0,
    from: {
      name: 'dev server errors',
      monitor: { id: 'm1', ...(end ? { end: { kind: 'stopped' } } : {}) },
    },
  });

  expect(play([connected, event('e1'), ended('e1')]).written).toStrictEqual([]);
  expect(
    play([connected, event('e1'), ended('e1'), event('e2', true), ended('e2')])
      .written.length,
  ).toStrictEqual(1);
  expect(
    play([connected, event('e1'), asked('e1', 'p1'), ended('e1')]).written,
  ).toStrictEqual(['\x1b]9;claude needs your permission: Write notes.txt\x07']);
  // The person's next turn rings as ever.
  expect(
    play([connected, event('e1'), ended('e1'), prompt('t1'), ended('t1')])
      .written.length,
  ).toStrictEqual(1);
});

describe("a task's request across the turn that started it (CHD-266)", () => {
  const taskAsked = (id: string): ConversationEvent => ({
    type: 'permission_requested',
    turnId: 't1',
    permission: { id, subagentId: 'task-1', options: [] },
    // A task's request comes stamped with when it was asked.
    at: 1000,
  });

  test("stays open when the turn ends; the agent's own does not", () => {
    const { watch } = play([
      connected,
      prompt('t1'),
      taskAsked('p1'),
      asked('t1', 'p2'),
      ended('t1'),
    ]);

    expect([...watch.asking]).toStrictEqual(['p1']);
  });

  test('goes once answered or withdrawn, and a later one asks again', () => {
    const { watch, written } = play([
      connected,
      prompt('t1'),
      taskAsked('p1'),
      ended('t1'),
      {
        type: 'permission_settled',
        turnId: 't1',
        id: 'p1',
        answer: { type: 'withdrawn' },
      },
      taskAsked('p2'),
    ]);

    expect([...watch.asking]).toStrictEqual(['p2']);
    // The first request, the turn's end, and the second request, which is a
    // wait of its own once the first has gone.
    expect(written.length).toStrictEqual(3);
  });
});

describe('CHD-266 tester: lasting request identity', () => {
  test('task forms and explicit between links survive results until their individual settlements', () => {
    const events: ConversationEvent[] = [
      connected,
      prompt('t1'),
      {
        type: 'elicitation_requested',
        turnId: 't1',
        elicitation: {
          id: 'form',
          subagentId: 'task',
          mode: 'form',
          message: 'Task form',
          schema: {},
        },
      },
      {
        type: 'elicitation_requested',
        turnId: 't1',
        elicitation: {
          id: 'link',
          between: true,
          mode: 'url',
          message: 'Between link',
          url: 'https://example.com/approve',
        },
      },
      ended('t1'),
      ended('later', 'cancelled'),
    ];
    const open = play(events).watch;

    expect([...open.asking]).toStrictEqual(['form', 'link']);
    expect([...open.lasting]).toStrictEqual(['form', 'link']);

    const partly = play([
      ...events,
      {
        type: 'elicitation_settled',
        turnId: 't1',
        id: 'form',
        answer: { type: 'withdrawn' },
      },
    ]).watch;

    expect([...partly.asking]).toStrictEqual(['link']);
    expect([...partly.lasting]).toStrictEqual(['link']);
  });

  test('an adapter subagent permission without a task timestamp survives the result as a between-turns wait', () => {
    const request: ConversationEvent = {
      type: 'permission_requested',
      turnId: 't1',
      permission: { id: 'adapter', subagentId: 'adapter-child', options: [] },
    };
    const { watch } = play([connected, prompt('t1'), request, ended('t1')]);

    expect([...watch.asking]).toStrictEqual(['adapter']);
    expect(watch.asked.get('adapter')).toMatchObject({
      kind: 'permission',
      subagentId: 'adapter-child',
    });
  });

  test('withdrawal and clear remove lasting IDs so a later request can notify again', () => {
    const request: ConversationEvent = {
      type: 'permission_requested',
      turnId: 't1',
      between: true,
      permission: { id: 'lasting', options: [] },
    };
    const events: ConversationEvent[] = [
      connected,
      request,
      ended('t1'),
      {
        type: 'permission_settled',
        turnId: 't1',
        id: 'lasting',
        answer: { type: 'withdrawn' },
      },
    ];
    const withdrawn = play(events).watch;

    expect(withdrawn.asking.size).toBe(0);
    expect(withdrawn.lasting.size).toBe(0);
    expect(play([...events, request]).written.at(-1)).toContain(
      'needs your permission',
    );
    expect(play([connected, request, { type: 'cleared' }]).watch).toStrictEqual(
      emptyWatch,
    );
  });
});
