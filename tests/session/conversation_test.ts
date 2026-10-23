/**
 * The conversation on the fake agent: a session's config and start, its
 * close while the agent never answers, a reply's chunks, and messages held
 * behind Claude's open calls.
 */
import { expect, test } from 'bun:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { RequestError } from '@agentclientprotocol/sdk';
import {
  Conversation,
  type ConversationEvent,
  type Starting,
} from '../../src/session/conversation.ts';
import { openSession, type Session } from '../../src/session/session.ts';
import { TaskAgent } from '../../src/session/tasks.ts';
import { valueToAsk } from '../../src/ui/pickers/picker.ts';
import { fakeAgentCommand } from '../fixtures/fake.ts';
import { TRACEBACK_ERROR } from '../fixtures/fake_agent/options.ts';
import {
  heldSession,
  until,
  isAlive,
  parentUp,
  adoptTask,
  onFake,
  saidIn,
  MAIN,
  steerOrder,
  callOpen,
  promptsIn,
} from './conversation_fake.ts';

test('a config change shows what the agent answered, and a reading after it keeps it', async () => {
  const { session } = heldSession();
  const events: ConversationEvent[] = [];
  const conversation = new Conversation(
    () => Promise.resolve(session),
    (event) => events.push(event),
  );
  const options = () =>
    events.flatMap((event) =>
      event.type === 'options' ? [event.options] : [],
    );

  conversation.start();
  await until(() => events.some((event) => event.type === 'connected'));

  // `/config` opening reads the options, as they stand before the change.
  conversation.readOptions();
  conversation.setOption('effort', 'high');
  await until(() => events.some((event) => event.type === 'noted'));
  conversation.readOptions();

  const effort = options().at(-1)?.[0];

  expect(options().map((each) => each[0]?.current)).toStrictEqual([
    'medium',
    'high',
  ]);
  expect(effort?.current).toStrictEqual('high');
  expect(valueToAsk(effort!, 'medium')).toStrictEqual('medium');

  await conversation.close();
});

test("a reply's chunks after the answer stay with it, not with the prompt queued behind", async () => {
  const dir = await mkdtemp(join(tmpdir(), 'chord-conversation-'));
  const events: ConversationEvent[] = [];
  const conversation = new Conversation(
    () =>
      openSession({
        agent: 'fake',
        cwd: dir,
        agentCommand: fakeAgentCommand(),
      }),
    (event) => events.push(event),
  );
  const said = (text: string) => {
    const turnId = events.flatMap((event) =>
      event.type === 'prompt' && event.text === text ? [event.turnId] : [],
    )[0];

    return events
      .flatMap((event) =>
        event.type === 'update' &&
        event.turnId === turnId &&
        event.update.sessionUpdate === 'agent_message_chunk' &&
        event.update.content.type === 'text'
          ? [event.update.content.text]
          : [],
      )
      .join('');
  };

  try {
    conversation.start();
    await until(() => events.some((event) => event.type === 'connected'));

    conversation.send('late');
    conversation.send('text');
    await until(
      () => events.filter((event) => event.type === 'result').length === 2,
    );

    expect(said('late')).toStrictEqual('Answered. Late, after the answer.');
    expect(said('text')).toStrictEqual(
      'Hello, world. This reply came in chunks.',
    );
  } finally {
    await conversation.close();
    await rm(dir, { recursive: true });
  }
});

test('an answered turn stays on screen while a queued prompt waits, and Esc then takes the prompt back', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'chord-conversation-'));
  const events: ConversationEvent[] = [];
  const conversation = new Conversation(
    () =>
      openSession({
        agent: 'fake',
        cwd: dir,
        agentCommand: fakeAgentCommand(),
      }),
    (event) => events.push(event),
  );

  try {
    conversation.start();
    await until(() => events.some((event) => event.type === 'connected'));

    conversation.send('late');
    conversation.send('text');
    // The late chunk comes after the answer, so the wait is under way.
    await until(() =>
      events.some(
        (event) =>
          event.type === 'update' &&
          event.update.sessionUpdate === 'agent_message_chunk' &&
          event.update.content.type === 'text' &&
          event.update.content.text.includes('Late'),
      ),
    );

    expect(!events.some((event) => event.type === 'result')).toBeTruthy();

    conversation.interrupt();
    await until(() => events.some((event) => event.type === 'result'));

    expect(
      events.flatMap((event) => (event.type === 'prompt' ? [event.text] : [])),
    ).toStrictEqual(['late']);
    expect(
      events.some((event) => event.type === 'queue_withdrawn'),
    ).toBeTruthy();
    expect(!events.some((event) => event.type === 'cancel')).toBeTruthy();
  } finally {
    await conversation.close();
    await rm(dir, { recursive: true });
  }
});

test('Esc takes the queued prompt back, and the message queued with it goes as the next turn at once', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'chord-conversation-'));
  const events: ConversationEvent[] = [];
  const conversation = new Conversation(
    () =>
      openSession({
        agent: 'fake',
        cwd: dir,
        agentCommand: fakeAgentCommand(),
      }),
    (event) => events.push(event),
  );
  const prompts = () =>
    events.flatMap((event) => (event.type === 'prompt' ? [event] : []));

  try {
    conversation.start();
    await until(() => events.some((event) => event.type === 'connected'));

    conversation.send('slow');
    await until(() => prompts().length === 1);
    conversation.send('text');
    expect(
      conversation.deliver({ name: 'tester', reachable: true }, 'All green.'),
    ).toStrictEqual('queued');

    conversation.interrupt();
    await until(
      () => events.filter((event) => event.type === 'result').length === 2,
    );

    expect(
      events.some((event) => event.type === 'queue_withdrawn'),
    ).toBeTruthy();
    expect(prompts().map(({ text, from }) => [text, from?.name])).toStrictEqual(
      [
        ['slow', undefined],
        ['All green.', 'tester'],
      ],
    );
    expect(
      events.flatMap((event) =>
        event.type === 'update' &&
        event.update.sessionUpdate === 'agent_message_chunk' &&
        event.update.content.type === 'text'
          ? [event.update.content.text]
          : [],
      ),
    ).toContain('Received the message from tester.');
  } finally {
    await conversation.close();
    await rm(dir, { recursive: true });
  }
});

/** The events a conversation on the fake agent reports until it is up. */
async function startOnFake(starting: Starting, ...flags: string[]) {
  const dir = await mkdtemp(join(tmpdir(), 'chord-conversation-'));
  const events: ConversationEvent[] = [];
  const conversation = new Conversation(
    () =>
      openSession({
        agent: 'fake',
        cwd: dir,
        agentCommand: fakeAgentCommand(undefined, ...flags),
      }),
    (event) => events.push(event),
    Date.now,
    starting,
  );

  try {
    conversation.start();
    await until(
      () =>
        events.some((event) => event.type === 'model') &&
        events.some((event) => event.type === 'connected'),
    );
  } finally {
    await conversation.close();
    await rm(dir, { recursive: true });
  }

  return events;
}

/** The failed start of a conversation on the fake started with `flags`. */
function failOnFake(...flags: string[]) {
  return failedStartOf(fakeAgentCommand(undefined, ...flags));
}

/** The failed start of a conversation on the agent `command` starts. */
async function failedStartOf(command: string[]) {
  const dir = await mkdtemp(join(tmpdir(), 'chord-conversation-'));
  const events: ConversationEvent[] = [];
  const conversation = new Conversation(
    () =>
      openSession({
        agent: 'fake',
        cwd: dir,
        agentCommand: command,
      }),
    (event) => events.push(event),
  );

  try {
    conversation.start();
    await until(() => events.some((event) => event.type === 'connect_failed'));
  } finally {
    await conversation.close();
    await rm(dir, { recursive: true });
  }

  return events.find((event) => event.type === 'connect_failed');
}

test("a start the agent refuses for want of a login says so, in the agent's words, with the ways in it offers (CHD-435)", async () => {
  expect(await failOnFake('--auth-required', 'methods')).toStrictEqual({
    type: 'connect_failed',
    message:
      'Authentication required: run `fake login` from your terminal, or set FAKE_API_KEY',
    signIn: {
      message:
        'Authentication required: run `fake login` from your terminal, or set FAKE_API_KEY',
      ways: [
        {
          name: 'Log in with the fake',
          description: 'Run `fake login` in the terminal',
        },
        { name: 'Log in with SSO' },
      ],
    },
    failure: {
      step: 'session/new',
      code: -32000,
      said: 'Authentication required: run `fake login` from your terminal, or set FAKE_API_KEY',
    },
  });
  expect(await failOnFake('--auth-required', 'bare')).toStrictEqual({
    type: 'connect_failed',
    message: 'Authentication required',
    signIn: { message: 'Authentication required', ways: [] },
    failure: {
      step: 'session/new',
      code: -32000,
      said: 'Authentication required',
    },
  });
});

// chord answers droid's sign-in link `cancel`, as it comes before anyone
// listens, and droid then fails the start `authRequired`.
test("droid's start, its sign-in link cancelled, needs a login by its code (CHD-435)", async () => {
  const message =
    'Authentication required: Sign-in was cancelled. Retry to sign in.';

  expect(await failOnFake('--auth-required', 'link')).toStrictEqual({
    type: 'connect_failed',
    message,
    signIn: { message, ways: [] },
    failure: { step: 'session/new', code: -32000, said: message },
  });
});

test('a link nobody answered, then a start that failed for another reason, needs no login (CHD-435)', async () => {
  expect(await failOnFake('--auth-required', 'linkother')).toStrictEqual({
    type: 'connect_failed',
    message: 'The fake could not open its session.',
    failure: {
      step: 'session/new',
      code: -32603,
      said: 'The fake could not open its session.',
    },
  });
});

test('a start that failed for another reason says only why (CHD-435)', async () => {
  expect(
    await failedStartOf(['sh', '-c', 'echo "no credentials" >&2; exit 1']),
  ).toStrictEqual({
    type: 'connect_failed',
    message: 'The agent exited: no credentials',
    failure: {
      step: 'initialize',
      exit: { code: 1 },
      stderr: { lines: ['no credentials'], cut: 0 },
    },
  });
});

test('an agent that exits before initialize says with what code, and the last lines of its stderr (CHD-454)', async () => {
  const failed = await failOnFake('--start-fails', 'traceback');

  expect(failed?.type === 'connect_failed' && failed.failure).toMatchObject({
    step: 'initialize',
    exit: { code: 1 },
    // The traceback's 122 lines, though chord keeps only their end.
    stderr: { cut: 116 },
  });
  expect(
    failed?.type === 'connect_failed' && failed.failure?.stderr?.lines.at(-1),
  ).toStrictEqual(TRACEBACK_ERROR);
  expect(
    failed?.type === 'connect_failed' && failed.failure?.stderr?.lines.length,
  ).toStrictEqual(6);
  // What it said on stdout never reaches chord (Q176).
  expect(await failOnFake('--start-fails', 'stdout')).toStrictEqual({
    type: 'connect_failed',
    message: 'The agent exited.',
    failure: { step: 'initialize', exit: { code: 0 } },
  });
});

test('an agent that refuses its session says which request and with what code (CHD-454)', async () => {
  expect(await failOnFake('--start-fails', 'notacp')).toStrictEqual({
    type: 'connect_failed',
    message: 'Method not found: session/new',
    failure: {
      step: 'session/new',
      code: -32601,
      said: 'Method not found: session/new',
    },
  });
  expect(await failOnFake('--start-fails', 'alias')).toStrictEqual({
    type: 'connect_failed',
    message:
      'session/new requires `agentAlias` (alias of a configured [agents.<alias>] entry)',
    failure: {
      step: 'session/new',
      code: -32602,
      said: 'session/new requires `agentAlias` (alias of a configured [agents.<alias>] entry)',
    },
  });
});

test('each session starts on the model and in the mode it was given', async () => {
  const events = await startOnFake({
    model: { id: 'fake-small' },
    mode: { id: 'plan' },
  });
  const modes = events.flatMap((event) =>
    event.type === 'modes' ? [event.modes?.current] : [],
  );
  const models = events.flatMap((event) =>
    event.type === 'model' ? [event.models?.current] : [],
  );

  // Shown from the first reading on, never the agent's default first.
  expect(modes).toStrictEqual(['plan']);
  expect(models).toStrictEqual(['fake-small']);
  expect(events.some((event) => event.type === 'failed')).toStrictEqual(false);
});

/** The effort each `options` event reports the fake agent on. */
function effortsShown(events: readonly ConversationEvent[]) {
  return events.flatMap((event) =>
    event.type === 'options'
      ? event.options.flatMap((option) =>
          option.id === 'effort' ? [option.current] : [],
        )
      : [],
  );
}

function failures(events: readonly ConversationEvent[]) {
  return events.flatMap((event) =>
    event.type === 'failed' ? [event.message] : [],
  );
}

test('a session starts on the effort it was given, after its model', async () => {
  const events = await startOnFake({
    model: { id: 'fake-small' },
    effort: { id: 'high' },
  });

  expect(effortsShown(events)).toStrictEqual(['high']);
  expect(failures(events)).toStrictEqual([]);
});

// Owner's answer: never a refused start, even for an effort asked as required.
for (const [refusal, flags, effort, said] of [
  [
    'the agent refuses',
    ['--refuse-config'],
    'high',
    'The fake agent holds its effort.',
  ],
  ['the agent does not offer', [], 'max', 'the agent offers low, medium, high'],
  [
    'an agent with no effort',
    ['--no-config'],
    'high',
    'the agent offers no efforts',
  ],
] as const) {
  test(`a starting effort ${refusal} is said, and the session starts on its own`, async () => {
    const events = await startOnFake(
      { effort: { id: effort, from: 'asked by spawn_task', required: true } },
      ...flags,
    );

    expect(failures(events)).toStrictEqual([
      `Could not start on ${effort} effort, asked by spawn_task: ${said}`,
    ]);
    expect(events.some((event) => event.type === 'connected')).toStrictEqual(
      true,
    );
    expect(
      events.some((event) => event.type === 'connect_failed'),
    ).toStrictEqual(false);
    expect(effortsShown(events)).toStrictEqual(
      (flags as readonly string[]).includes('--no-config') ? [] : ['medium'],
    );
  });
}

test("a starting mode is shown before a prompt on an agent that answers set_mode with nothing, as Codex's does", async () => {
  const events = await startOnFake(
    { mode: { id: 'plan', from: 'set by --permission-mode' } },
    '--silent-set-mode',
  );

  expect(
    events.flatMap((event) =>
      event.type === 'modes' ? [event.modes?.current] : [],
    ),
  ).toStrictEqual(['plan']);
  expect(events.some((event) => event.type === 'failed')).toStrictEqual(false);
});

test('a starting mode the agent does not offer is said with where it was set and what it offers', async () => {
  const events = await startOnFake({
    mode: { id: 'yolo', from: 'set in .chord/settings.json' },
  });
  const failed = events.findIndex((event) => event.type === 'failed');

  expect(events[failed]).toStrictEqual({
    type: 'failed',
    turnId: 'starting-1',
    message:
      'Could not start in yolo mode, set in .chord/settings.json: the agent offers default, acceptEdits, plan',
  });
  expect(
    failed < events.findIndex((event) => event.type === 'connected'),
  ).toStrictEqual(true);
  expect(
    events.flatMap((event) =>
      event.type === 'modes' ? [event.modes?.current] : [],
    ),
  ).toStrictEqual(['default']);
});

test("a starting model the agent lists and refuses is said in the agent's words", async () => {
  const { session } = heldSession();
  const refused = new RequestError(-32602, 'Invalid params: no such model');
  const events: ConversationEvent[] = [];
  const conversation = new Conversation(
    () =>
      Promise.resolve({
        ...session,
        models: () => ({ available: [{ id: 'big', name: 'Big' }] }),
        setModel: () => Promise.reject(refused),
      } as Session),
    (event) => events.push(event),
    Date.now,
    { model: { id: 'big', from: 'set by --model' } },
  );

  conversation.start();
  await until(() => events.some((event) => event.type === 'connected'));
  await conversation.close();

  expect(
    events.flatMap((event) => (event.type === 'failed' ? [event.message] : [])),
  ).toStrictEqual([
    'Could not start on big, set by --model: Invalid params: no such model',
  ]);
});

test("a starting model the agent refuses without listing any is said in the agent's words", async () => {
  const { session } = heldSession();
  const refused = new RequestError(-32602, 'Invalid params: no such model');
  const events: ConversationEvent[] = [];
  const conversation = new Conversation(
    () =>
      Promise.resolve({
        ...session,
        setModel: () => Promise.reject(refused),
      } as Session),
    (event) => events.push(event),
    Date.now,
    { model: { id: 'big', from: 'set by --model' } },
  );

  conversation.start();
  await until(() => events.some((event) => event.type === 'connected'));
  await conversation.close();

  expect(
    events.flatMap((event) => (event.type === 'failed' ? [event.message] : [])),
  ).toStrictEqual([
    'Could not start on big, set by --model: Invalid params: no such model',
  ]);
});

test('closing while the agent never answers its start gives the start up, and a cleared one too', async () => {
  const events: ConversationEvent[] = [];
  const given: AbortSignal[] = [];
  const conversation = new Conversation(
    (signal) => {
      given.push(signal);

      return new Promise<Session>((_, reject) =>
        signal.addEventListener('abort', () => reject(signal.reason)),
      );
    },
    (event) => events.push(event),
  );

  conversation.start();
  conversation.clear();
  await conversation.close();

  expect(given.length).toStrictEqual(2);
  expect(given.map((signal) => signal.aborted)).toStrictEqual([true, true]);
  // A start given up on quit is no failure to report.
  expect(events.some((event) => event.type === 'connect_failed')).toStrictEqual(
    false,
  );
});

/**
 * Starts a conversation on a fake agent that never answers a model or mode
 * change, on `starting`, waits until the change is asked for, does `then`,
 * and proves the close comes back in time with every agent it started gone.
 */
async function quitsWhileStarting(
  starting: Starting,
  then: (conversation: Conversation) => void = () => {},
) {
  const dir = await mkdtemp(join(tmpdir(), 'chord-conversation-'));
  const sessions: Session[] = [];
  let asked = 0;
  const conversation = new Conversation(
    async (signal) => {
      const session = await openSession({
        agent: 'fake',
        cwd: dir,
        agentCommand: fakeAgentCommand(undefined, '--hang', 'config'),
        signal,
      });
      const { setModel, setMode } = session;

      session.setModel = (id) => (asked++, setModel.call(session, id));
      session.setMode = (id) => (asked++, setMode.call(session, id));

      sessions.push(session);

      return session;
    },
    () => {},
    Date.now,
    starting,
  );

  try {
    conversation.start();

    while (asked === 0) {
      await new Promise((resolve) => setTimeout(resolve, 20));
    }

    // Long enough for the change to be out to the agent.
    await new Promise((resolve) => setTimeout(resolve, 200));
    then(conversation);

    const pids = sessions.flatMap((session) => [...session.agentPids]);
    const started = Date.now();

    await conversation.close();
    expect(
      Date.now() - started < 10_000,
      'the close was not bounded',
    ).toBeTruthy();

    for (const pid of pids) {
      expect(!(await isAlive(pid)), `agent ${pid} still running`).toBeTruthy();
    }

    for (const session of sessions) {
      expect(session.agentPids.size).toStrictEqual(0);
    }
  } finally {
    await rm(dir, { recursive: true });
  }
}

test('closing while the agent never answers the starting model kills it in time', () =>
  quitsWhileStarting({ model: { id: 'fake-small', from: 'set by --model' } }));

test('closing while the agent never answers the starting mode kills it in time', () =>
  quitsWhileStarting({
    mode: { id: 'plan', from: 'set by --permission-mode' },
  }));

test('closing kills a cleared agent that never answered its starting model', () =>
  quitsWhileStarting(
    { model: { id: 'fake-small', from: 'set by --model' } },
    (conversation) => conversation.clear(),
  ));

test("a task's refused starting effort reaches the parent's transcript, named, and the task runs on", async () => {
  const { parent, events } = await parentUp();
  const dir = await mkdtemp(join(tmpdir(), 'chord-conversation-'));
  const task = new TaskAgent(
    { id: 'task-a', name: 'Fix it', runtime: 'fake', prompt: 'text' },
    parent.taskParent('task-a'),
    () => 7,
  );
  const child = new Conversation(
    () =>
      openSession({
        agent: 'fake',
        cwd: dir,
        agentCommand: fakeAgentCommand(undefined, '--refuse-config'),
      }),
    (event) => task.heard(event),
    Date.now,
    { effort: { id: 'high', from: 'asked by spawn_task' } },
  );

  try {
    parent.adopt(task, child);
    await until(() => !task.running);
  } finally {
    await child.close();
    await parent.close();
    await rm(dir, { recursive: true });
  }

  expect(
    events.flatMap((event) => (event.type === 'failed' ? [event.message] : [])),
  ).toStrictEqual([
    'Fix it: Could not start on high effort, asked by spawn_task: The fake agent holds its effort.',
  ]);
  // It ran its job and reported, on the agent's own effort.
  expect(
    events.some(
      (event) =>
        event.type === 'update' &&
        event.subagentId === 'task-a' &&
        event.update.sessionUpdate === 'agent_message_chunk',
    ),
  ).toStrictEqual(true);
});

test("a nested subagent's permission in a task is answered by that task, not the first one running", async () => {
  const { parent } = await parentUp();
  const a = adoptTask(parent, 'task-a');
  const b = adoptTask(parent, 'task-b');

  b.task.heard({ type: 'connected', sessionId: 'b' });
  b.task.heard({
    type: 'permission_requested',
    turnId: 'child-turn',
    permission: {
      id: 'nested-request',
      subagentId: 'nested-of-b',
      options: [],
    },
  });
  parent.choose('nested-request', 'allow');

  expect(a.asked).toStrictEqual([]);
  expect(b.asked).toStrictEqual(['send job', 'choose nested-request allow']);
  await parent.close();
});

test('/clear closes the running task agents, and nothing they say after reaches the new session', async () => {
  const { parent, events } = await parentUp();
  const a = adoptTask(parent, 'task-a');
  const b = adoptTask(parent, 'task-b');

  a.task.heard({ type: 'connected', sessionId: 'a' });
  a.task.heard({ type: 'prompt', turnId: 'r1', text: 'job', at: 1 });
  parent.clear();
  await until(
    () => events.filter((event) => event.type === 'connected').length === 2,
  );

  const cleared = events.length;

  expect(parent.runningTasks).toStrictEqual(0);
  expect(a.asked.includes('close')).toStrictEqual(true);
  expect(b.asked.includes('close')).toStrictEqual(true);

  // A late update and a late report from the old task go nowhere.
  a.task.heard({
    type: 'update',
    turnId: 'r1',
    update: {
      sessionUpdate: 'agent_message_chunk',
      content: { type: 'text', text: 'late' },
    },
  });
  a.task.heard({
    type: 'result',
    turnId: 'r1',
    result: { status: 'completed', stopReason: 'end_turn' },
  });
  parent.taskParent('task-a').deliver({ name: 'task-a' }, 'late report');
  parent.taskParent('task-b').ahead({ name: 'task-b' }, 'stopped');

  expect(events.slice(cleared)).toStrictEqual([]);
  expect(parent.send('hello')).toStrictEqual(true);
  await until(() => events.some((event) => event.type === 'prompt'));
  expect(
    events.flatMap((event) => (event.type === 'prompt' ? [event.text] : [])),
  ).toStrictEqual(['hello']);
  await parent.close();
});

test("a task stopped by the parent's Esc while it starts never sends its job", async () => {
  const { parent } = await parentUp();
  const { task, asked } = adoptTask(parent, 'task-a');

  parent.interrupt();
  task.heard({ type: 'connected', sessionId: 'a' });

  expect(asked).toStrictEqual(['close']);
  expect(task.running).toStrictEqual(false);
  expect(parent.runningTasks).toStrictEqual(0);
  await parent.close();
});

for (const [what, models, setModel, reason] of [
  [
    'lists and refuses',
    {
      available: [
        { id: 'wanted', name: 'W' },
        { id: 'base', name: 'B' },
      ],
    },
    () => Promise.reject(new Error('runtime refuses switch')),
    'runtime refuses switch',
  ],
  [
    'does not list',
    { available: [{ id: 'base', name: 'B' }] },
    () => Promise.resolve(),
    'the agent offers base',
  ],
  [
    'refuses listing none',
    undefined,
    () => Promise.reject(new Error('runtime refuses switch')),
    'runtime refuses switch',
  ],
] as const) {
  test(`a task's model the runtime ${what} fails the task, and its job never runs`, async () => {
    const { parent } = await parentUp();
    const { session } = heldSession();
    const prompted: string[] = [];
    const childEvents: ConversationEvent[] = [];
    const task = new TaskAgent(
      { id: 'task-a', name: 'task-a', runtime: 'fake', prompt: 'job' },
      parent.taskParent('task-a'),
      () => 7,
    );
    const child = new Conversation(
      () =>
        Promise.resolve({
          ...session,
          models: () => models,
          setModel,
          prompt: (text: string) => {
            prompted.push(text);

            return new Promise(() => {});
          },
        } as unknown as Session),
      (event) => {
        childEvents.push(event);
        task.heard(event);
      },
      () => 7,
      {
        model: { id: 'wanted', from: 'asked by spawn_task', required: true },
      },
    );

    parent.adopt(task, child);
    await until(() => !task.running);

    expect(prompted).toStrictEqual([]);
    expect(
      childEvents.some((event) => event.type === 'connected'),
    ).toStrictEqual(false);
    expect(
      childEvents.find((event) => event.type === 'connect_failed'),
    ).toStrictEqual({
      type: 'connect_failed',
      message: `Could not start on wanted, asked by spawn_task: ${reason}`,
    });
    await parent.close();
  });
}

for (const delayed of ['its open', 'its starting model'] as const) {
  test(`a task stopped while ${delayed} is pending is closed, and its job never runs`, async () => {
    const { parent } = await parentUp();
    const { session } = heldSession();
    const prompted: string[] = [];
    let closed = false;
    const { promise: held, resolve: release } = Promise.withResolvers<void>();
    const task = new TaskAgent(
      { id: 'task-a', name: 'task-a', runtime: 'fake', prompt: 'job' },
      parent.taskParent('task-a'),
      () => 7,
    );
    const child = new Conversation(
      async () => {
        if (delayed === 'its open') {
          await held;
        }

        return {
          ...session,
          setModel: () => (delayed === 'its open' ? Promise.resolve() : held),
          prompt: (text: string) => {
            prompted.push(text);

            return new Promise(() => {});
          },
          close: () => {
            closed = true;

            return Promise.resolve();
          },
        } as unknown as Session;
      },
      (event) => task.heard(event),
      () => 7,
      {
        model: { id: 'wanted', from: 'asked by spawn_task', required: true },
      },
    );

    parent.adopt(task, child);
    await new Promise((resolve) => setTimeout(resolve, 0));
    parent.interrupt();
    release();
    await until(() => closed);
    await new Promise((resolve) => setTimeout(resolve, 0));

    expect(task.running).toStrictEqual(false);
    expect(prompted).toStrictEqual([]);
    await parent.close();
  });
}

test("chord's own question waits in the turn, is answered by the option picked or Esc, and an interrupt withdraws it", async () => {
  const dir = await mkdtemp(join(tmpdir(), 'chord-conversation-'));
  const events: ConversationEvent[] = [];
  const conversation = new Conversation(
    () =>
      openSession({
        agent: 'fake',
        cwd: dir,
        agentCommand: fakeAgentCommand(),
      }),
    (event) => events.push(event),
  );
  const wait = {
    options: [
      { optionId: 'yes', name: 'Yes', kind: 'allow_once' as const },
      { optionId: 'no', name: 'No', kind: 'reject_once' as const },
    ],
    save: { question: 'Save team bugfix?', files: {}, escape: 'no' },
  };
  const asked = () =>
    events.flatMap((event) =>
      event.type === 'permission_requested' ? [event.permission.id] : [],
    );

  try {
    // No turn: nobody to ask.
    expect(
      await conversation.ask(wait, new AbortController().signal),
    ).toStrictEqual(undefined);

    conversation.start();
    await until(() => events.some((event) => event.type === 'connected'));
    conversation.send('slow');
    await until(() => events.some((event) => event.type === 'prompt'));

    const picked = conversation.ask(wait, new AbortController().signal);

    await until(() => asked().length === 1);
    conversation.choose(asked()[0]!, 'yes');
    expect(await picked).toStrictEqual('yes');

    const escaped = conversation.ask(wait, new AbortController().signal);

    await until(() => asked().length === 2);
    conversation.reject(asked()[1]!);
    expect(await escaped).toStrictEqual('no');

    const withdrawn = conversation.ask(wait, new AbortController().signal);

    await until(() => asked().length === 3);
    conversation.interrupt();
    expect(await withdrawn).toStrictEqual(undefined);
    expect(
      events.some(
        (event) =>
          event.type === 'permission_settled' &&
          event.id === asked()[2] &&
          event.answer.type === 'withdrawn',
      ),
    ).toBeTruthy();
  } finally {
    await conversation.close();
    await rm(dir, { recursive: true });
  }
});

test("a message set aside starts no turn and goes ahead of the person's next prompt, not of a message's", async () => {
  const { session } = heldSession();
  const prompted: string[] = [];
  const events: ConversationEvent[] = [];
  const conversation = new Conversation(
    () =>
      Promise.resolve({
        ...session,
        prompt: (text: string) => {
          prompted.push(text);

          return {
            sent: Promise.resolve([]),
            result: Promise.resolve({
              status: 'completed',
              stopReason: 'end_turn',
            }),
          };
        },
      } as unknown as Session),
    (event) => events.push(event),
    () => 7,
  );

  conversation.start();
  await until(() => events.some((event) => event.type === 'connected'));
  conversation.aside({ name: 'chord' }, 'The person handed team bugfix a job.');

  expect(prompted).toStrictEqual([]);

  conversation.deliver({ name: 'bugfix', reachable: true }, 'On it.');
  await until(() => prompted.length === 1);
  conversation.send('how is it going?');
  await until(() => prompted.length === 2);

  expect(prompted).toStrictEqual([
    '<message from="bugfix">\nOn it.\n</message>',
    '<message from="chord">\nThe person handed team bugfix a job.\n' +
      '</message>\n\nhow is it going?',
  ]);
  await conversation.close();
});

/**
 * A conversation on the fake agent started with `flags`, once it is up,
 * handed to `body`, then closed.
 */
test('a session whose agent was not given a server says so as a warning before it is up (CHD-441)', () =>
  onFake(
    ['--mcp-transports', 'none'],
    (_, events) => {
      const warned = events.filter((event) => event.type === 'warned');
      const connected = events.findIndex((event) => event.type === 'connected');

      expect(warned.map((event) => event.message)).toStrictEqual([
        '1 MCP server was not passed to fake, which takes them over stdio ' +
          'only: search (http). /mcp lists it.',
      ]);
      expect(events.indexOf(warned[0]!)).toBeLessThan(connected);

      return Promise.resolve();
    },
    undefined,
    [
      {
        type: 'http',
        name: 'search',
        url: 'https://search.example/mcp',
        headers: [],
      },
    ],
  ));

test('a session whose agent was given every server says nothing of them (CHD-441)', () =>
  onFake([], (_, events) => {
    expect(events.some((event) => event.type === 'warned')).toBe(false);

    return Promise.resolve();
  }));

for (const adapter of ['claude', 'codex']) {
  test(`a message told while a turn runs goes into it at once, as ${adapter}'s adapter takes it, drawn in that turn and never queued`, () =>
    onFake(['--steering', adapter], async (conversation, events) => {
      conversation.send('slow');
      await until(() => saidIn(events).startsWith('Working'));

      let queued = 0;

      expect(
        conversation.tell(MAIN, 'Stop.', () => (queued += 1)),
      ).toStrictEqual('sent');
      await until(() => saidIn(events).includes('Read the message from main.'));

      // It went in: the sender's row stays as it was served.
      expect(queued).toStrictEqual(0);

      const prompts = events.flatMap((event) =>
        event.type === 'prompt' ? [event] : [],
      );

      expect(prompts.map(({ text, into }) => [text, into])).toStrictEqual([
        ['slow', undefined],
        ['Stop.', prompts[0]!.turnId],
      ]);
      expect(!events.some((event) => event.type === 'queued')).toBeTruthy();
      expect(!events.some((event) => event.type === 'result')).toBeTruthy();
      conversation.interrupt();
      await until(() => events.some((event) => event.type === 'result'));
    }));
}

test("on an agent that does not steer, a message told during a turn waits for the turn's end, as a monitor's event and the person's prompt do on one that does", async () => {
  await onFake([], async (conversation, events) => {
    conversation.send('slow');
    await until(() => saidIn(events).startsWith('Working'));

    expect(conversation.tell(MAIN, 'Stop.')).toStrictEqual('queued');
    conversation.interrupt();
  });

  await onFake(['--steering', 'claude'], async (conversation, events) => {
    conversation.send('slow');
    await until(() => saidIn(events).startsWith('Working'));

    expect(
      conversation.deliver({ name: 'chord' }, 'parser exited.'),
    ).toStrictEqual('queued');
    expect(conversation.send('text')).toStrictEqual(true);
    expect(
      events.filter((event) => event.type === 'queued').length,
    ).toStrictEqual(2);
    expect(
      !events.some((event) => event.type === 'prompt' && event.into),
    ).toBeTruthy();
    conversation.interrupt();
  });
});

test('a message told while the turn waits on a permission is held, marked so, and goes into the turn once the person answers', () =>
  onFake(['--steering', 'claude'], async (conversation, events) => {
    // Its next step after the write waits for the message, as the model's
    // comes only after the tool's result: chord sends it once the person
    // answers, which under load could otherwise meet the turn's end
    // (CHD-467).
    conversation.send('permissionsteer');
    await until(() =>
      events.some((event) => event.type === 'permission_requested'),
    );

    expect(conversation.tell(MAIN, 'Then the docs.')).toStrictEqual('queued');

    const queued = events.find((event) => event.type === 'queued');

    expect(queued).toMatchObject({ text: 'Then the docs.', afterAnswer: true });
    expect(
      !events.some((event) => event.type === 'prompt' && event.into),
    ).toBeTruthy();

    const asked = events.find((event) => event.type === 'permission_requested');

    assert(asked?.type === 'permission_requested');
    conversation.choose(asked.permission.id, 'allow');
    await until(() => events.some((event) => event.type === 'result'));

    const order = events.flatMap((event) =>
      event.type === 'permission_settled'
        ? ['answered']
        : event.type === 'prompt' && event.into !== undefined
          ? [`into: ${event.text}`]
          : event.type === 'result'
            ? ['ended']
            : [],
    );

    expect(order).toStrictEqual(['answered', 'into: Then the docs.', 'ended']);
    expect(saidIn(events)).toContain('Read the message from main.');
  }));

test('a message held for an answer goes as the next turn when Esc interrupts the turn instead', () =>
  onFake(['--steering', 'claude'], async (conversation, events) => {
    conversation.send('permission');
    await until(() =>
      events.some((event) => event.type === 'permission_requested'),
    );
    conversation.tell(MAIN, 'Then the docs.');
    conversation.interrupt();
    await until(
      () => events.filter((event) => event.type === 'result').length === 2,
    );

    const prompts = events.flatMap((event) =>
      event.type === 'prompt' ? [[event.text, event.into]] : [],
    );

    expect(prompts).toStrictEqual([
      ['permission', undefined],
      ['Then the docs.', undefined],
    ]);
    // Unmarked before it went: it waited for the turn's end, not an answer.
    expect(
      events.filter((event) => event.type === 'queued').at(-1),
    ).not.toHaveProperty('afterAnswer');
  }));

test('a message held for a plan goes as the next turn when Esc interrupts the turn, never into it (CHD-437)', () =>
  onFake(['--steering', 'claude'], async (conversation, events) => {
    conversation.send('grokplan');
    await until(() => events.some((event) => event.type === 'plan_requested'));
    conversation.tell(MAIN, 'Then the docs.');
    conversation.interrupt();
    await until(
      () => events.filter((event) => event.type === 'result').length === 2,
    );

    expect(
      events.flatMap((event) =>
        event.type === 'prompt' ? [[event.text, event.into]] : [],
      ),
    ).toStrictEqual([
      ['grokplan', undefined],
      ['Then the docs.', undefined],
    ]);
  }));

test("on Claude's adapter, a message told while the turn's call is open waits in the queue until the call ends, then goes into the same turn", () =>
  onFake(['--steering', 'claude'], async (conversation, events) => {
    // Its next step after the command waits for the message, as the model's
    // comes only after the tool's result: chord steers it in once the
    // command ends, which could otherwise meet the turn's end (CHD-399).
    conversation.send('bashone');
    await callOpen(events);

    let queued = 0;

    expect(
      conversation.tell(MAIN, 'Then the docs.', () => (queued += 1)),
    ).toStrictEqual('sent');
    expect(
      !events.some((event) => event.type === 'prompt' && event.into),
    ).toBeTruthy();
    await until(() => events.some((event) => event.type === 'result'));

    expect(steerOrder(events)).toStrictEqual([
      'call ended',
      'into: Then the docs.',
      'ended',
    ]);
    expect(saidIn(events)).toContain('Read the message from main.');
    // Held for the call, it waits in the queue as such, never as one held
    // for an answer, until it goes in (CHD-423); the sender's row stays.
    expect(
      events.flatMap((event) =>
        event.type === 'queued'
          ? [[event.text, event.afterCalls, event.afterAnswer]]
          : [],
      ),
    ).toStrictEqual([['Then the docs.', true, undefined]]);
    expect(
      events.findIndex((event) => event.type === 'queued') <
        events.findIndex(
          (event) => event.type === 'prompt' && event.into !== undefined,
        ),
    ).toBeTruthy();
    expect(queued).toStrictEqual(0);
  }));

test("on Claude's adapter, a message waits only for the calls open when it was told, not for one opened after", () =>
  onFake(['--steering', 'claude'], async (conversation, events) => {
    conversation.send('overlap');
    await until(() =>
      events.some(
        (event) =>
          event.type === 'update' &&
          event.update.sessionUpdate === 'tool_call' &&
          event.update.toolCallId === 'overlap-a',
      ),
    );
    conversation.tell(MAIN, 'Then the docs.');
    await until(() => events.some((event) => event.type === 'result'));

    const order = events.flatMap((event) =>
      event.type === 'update' &&
      (event.update.sessionUpdate === 'tool_call' ||
        event.update.sessionUpdate === 'tool_call_update')
        ? [`${event.update.toolCallId.slice(-1)} ${event.update.status}`]
        : event.type === 'prompt' && event.into !== undefined
          ? [`into: ${event.text}`]
          : [],
    );

    // `b` is still running when it goes in, as the owner's answer has it.
    expect(order).toStrictEqual([
      'a in_progress',
      'b in_progress',
      'a completed',
      'into: Then the docs.',
      'b completed',
    ]);
  }));

test("a message held behind an open call that the turn's end refuses waits in the queue as any queued message does, and goes as the next turn", () =>
  onFake(['--steering', 'claude'], async (conversation, events) => {
    conversation.send('bash');
    await callOpen(events);
    conversation.tell(MAIN, 'Then the docs.');
    await until(() => events.some((event) => event.type === 'queued'));
    conversation.interrupt();
    await until(
      () => events.filter((event) => event.type === 'result').length === 2,
    );

    const queued = events.flatMap((event) =>
      event.type === 'queued' ? [event] : [],
    );

    // Held for the call, then, the turn over, queued as today, the same row.
    expect(queued.map((event) => event.afterCalls)).toStrictEqual([
      true,
      undefined,
    ]);
    expect(new Set(queued.map((event) => event.turnId)).size).toStrictEqual(1);
    expect(promptsIn(events)).toStrictEqual([
      ['bash', undefined],
      ['Then the docs.', undefined],
    ]);
  }));

test("on Claude's adapter, every message held behind an open call waits in the queue at once, in the order told, before the call ends", () =>
  onFake(['--steering', 'claude'], async (conversation, events) => {
    // A call open for seconds, so both are told while it is; its next step
    // after it waits for both, as the model's comes only after its result.
    conversation.send('callchildtwo');
    await until(() =>
      events.some(
        (event) =>
          event.type === 'update' && event.update.sessionUpdate === 'tool_call',
      ),
    );
    conversation.tell(MAIN, 'Run the tests.');
    conversation.tell(MAIN, 'Then the docs.');

    // Both shown before anything moved: the second behind the first too.
    expect(
      events.flatMap((event) =>
        event.type === 'queued' ? [[event.text, event.afterCalls]] : [],
      ),
    ).toStrictEqual([
      ['Run the tests.', true],
      ['Then the docs.', true],
    ]);
    await until(() => events.some((event) => event.type === 'result'));

    expect(
      events.flatMap((event) =>
        event.type === 'queued'
          ? [`queued: ${event.text}`]
          : event.type === 'update' &&
              event.update.sessionUpdate === 'tool_call_update' &&
              event.update.status === 'completed'
            ? ['call ended']
            : event.type === 'prompt' && event.into !== undefined
              ? [`into: ${event.text}`]
              : [],
      ),
    ).toStrictEqual([
      'queued: Run the tests.',
      'queued: Then the docs.',
      'call ended',
      'into: Run the tests.',
      'into: Then the docs.',
    ]);
  }));

test("on Claude's adapter, two messages held behind an open call go into the turn in the order they were told", () =>
  onFake(['--steering', 'claude'], async (conversation, events) => {
    // Its next step after the command waits for both, as the model's comes
    // only after the tool's result: chord sends the second once the first is
    // answered, which under load could otherwise meet the turn's end
    // (CHD-467).
    conversation.send('bashtwo');
    await callOpen(events);
    conversation.tell(MAIN, 'Run the tests.');
    conversation.tell(MAIN, 'Then the docs.');
    await until(() => events.some((event) => event.type === 'result'));

    expect(steerOrder(events)).toStrictEqual([
      'call ended',
      'into: Run the tests.',
      'into: Then the docs.',
      'ended',
    ]);
  }));

test("on Claude's adapter, a message held behind an open call goes as the next turn when the turn ends first", () =>
  onFake(['--steering', 'claude'], async (conversation, events) => {
    conversation.send('bash');
    await callOpen(events);

    let queued = 0;

    conversation.tell(MAIN, 'Then the docs.', () => (queued += 1));
    conversation.interrupt();
    await until(
      () => events.filter((event) => event.type === 'result').length === 2,
    );

    expect(promptsIn(events)).toStrictEqual([
      ['bash', undefined],
      ['Then the docs.', undefined],
    ]);
    expect(queued).toStrictEqual(1);
  }));
