import { execFile } from 'node:child_process';
import { describe, expect, test } from 'bun:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { RequestError, type SessionUpdate } from '@agentclientprotocol/sdk';
import type { AgentOption } from '../../src/session/config.ts';
import {
  Conversation,
  type ConversationEvent,
  type Starting,
} from '../../src/session/conversation.ts';
import type { PendingElicitation } from '../../src/session/elicitations.ts';
import type { PendingPermission } from '../../src/session/permissions.ts';
import {
  openSession,
  type Session,
  type SteerOutcome,
} from '../../src/session/session.ts';
import { TaskAgent, type TaskSession } from '../../src/session/tasks.ts';
import { reduceTranscript } from '../../src/session/transcript/reducer.ts';
import {
  emptyTranscript,
  type TranscriptAction,
  type TurnResult,
} from '../../src/session/transcript/types.ts';
import { initialAppState, reduceApp } from '../../src/ui/app/state.ts';
import { valueToAsk } from '../../src/ui/pickers/picker.ts';
import { fakeAgentCommand } from '../fixtures/fake.ts';
import { cutNote } from '../../src/session/cut_off.ts';
import {
  CUT_MESSAGE,
  CUT_OPEN,
} from '../fixtures/fake_agent/scenarios/chord_tools.ts';

/**
 * A session with one option, `effort`, held in memory, that answers a change
 * as the agent would, with the option as it now stands.
 */
function heldSession() {
  const state = { current: 'medium' };
  const snapshot = (): AgentOption[] => [
    {
      id: 'effort',
      name: 'Effort',
      current: state.current,
      values: ['low', 'medium', 'high'].map((value) => ({
        value,
        name: value.charAt(0).toUpperCase() + value.slice(1),
      })),
    },
  ];
  const session = {
    id: 'held',
    permissions: { subscribe: () => () => {} },
    elicitations: { subscribe: () => () => {} },
    subscribe: () => () => {},
    history: () => [],
    // Its agent never goes on its own.
    exited: new Promise<void>(() => {}),
    takesImages: () => false,
    modes: () => undefined,
    commands: () => [],
    models: () => undefined,
    options: snapshot,
    setOption: (_id: string, value: string) => {
      state.current = value;

      return Promise.resolve();
    },
    close: () => Promise.resolve(),
  } as unknown as Session;

  return { session, state };
}

async function until(check: () => boolean): Promise<void> {
  while (!check()) {
    await new Promise((resolve) => setTimeout(resolve, 0));
  }
}

/**
 * Lets a prompt just sent go to the agent: until it has, its turn takes no
 * message.
 */
function went(): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, 0));
}

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

function isAlive(pid: number): Promise<boolean> {
  return new Promise((resolve) => {
    execFile('ps', ['-p', String(pid)], (error) => resolve(error === null));
  });
}

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

/** A parent up on a held session, with the events it reports. */
async function parentUp() {
  const { session } = heldSession();
  const events: ConversationEvent[] = [];
  const parent = new Conversation(
    () => Promise.resolve(session),
    (event) => events.push(event),
    () => 7,
  );

  parent.start();
  await until(() => events.some((event) => event.type === 'connected'));

  return { parent, events };
}

/** Task `id` adopted by `parent`, on a session that keeps what it was asked. */
function adoptTask(parent: Conversation, id: string) {
  const asked: string[] = [];
  const session: TaskSession = {
    start: () => {},
    send: (text) => asked.push(`send ${text}`) > 0,
    interrupt: () => asked.push('interrupt'),
    choose: (request, option) => asked.push(`choose ${request} ${option}`),
    reject: (request) => asked.push(`reject ${request}`),
    answer: (request) => asked.push(`answer ${request}`),
    close: () => {
      asked.push('close');

      return Promise.resolve();
    },
  };
  const task = new TaskAgent(
    { id, name: id, runtime: 'fake', prompt: 'job' },
    parent.taskParent(id),
    () => 7,
  );

  parent.adopt(task, session);

  return { task, asked };
}

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
async function onFake(
  flags: string[],
  body: (
    conversation: Conversation,
    events: ConversationEvent[],
  ) => Promise<void>,
  watch: (session: Session) => Session = (session) => session,
) {
  const dir = await mkdtemp(join(tmpdir(), 'chord-conversation-'));
  const events: ConversationEvent[] = [];
  const conversation = new Conversation(
    async () =>
      watch(
        await openSession({
          agent: 'fake',
          cwd: dir,
          agentCommand: fakeAgentCommand(undefined, ...flags),
        }),
      ),
    (event) => events.push(event),
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

/** The text of every agent message chunk among `events`, joined. */
function saidIn(events: readonly ConversationEvent[]): string {
  return events
    .map((event) =>
      event.type === 'update' &&
      event.update.sessionUpdate === 'agent_message_chunk' &&
      event.update.content.type === 'text'
        ? event.update.content.text
        : '',
    )
    .join('');
}

const MAIN = { name: 'main', reachable: true } as const;

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
    conversation.send('permission');
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

/**
 * The order of a call's end, the messages that went into the turn and the
 * turn's end among `events`.
 */
function steerOrder(events: readonly ConversationEvent[]): string[] {
  return events.flatMap((event) =>
    event.type === 'update' &&
    event.update.sessionUpdate === 'tool_call_update' &&
    event.update.status === 'completed'
      ? ['call ended']
      : event.type === 'prompt' && event.into !== undefined
        ? [`into: ${event.text}`]
        : event.type === 'result'
          ? ['ended']
          : [],
  );
}

/** Until the turn on the fake has its call open. */
async function callOpen(events: readonly ConversationEvent[]): Promise<void> {
  await until(() =>
    events.some(
      (event) =>
        event.type === 'update' &&
        event.update.sessionUpdate === 'tool_call_update' &&
        event.update.status === 'in_progress',
    ),
  );
}

test("on Claude's adapter, a message told while the turn's call is open waits in the queue until the call ends, then goes into the same turn", () =>
  onFake(['--steering', 'claude'], async (conversation, events) => {
    conversation.send('bash');
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
    conversation.send('bash');
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

test("on Codex's adapter, whose steer cuts nothing, a message told while the turn's call is open goes into it at once", () =>
  onFake(['--steering', 'codex'], async (conversation, events) => {
    conversation.send('bash');
    await callOpen(events);
    conversation.tell(MAIN, 'Then the docs.');
    await until(() => events.some((event) => event.type === 'result'));

    expect(steerOrder(events)).toStrictEqual([
      'into: Then the docs.',
      'call ended',
      'ended',
    ]);
  }));

/** Each prompt's text among `events`, with the turn it went into. */
function promptsIn(
  events: readonly ConversationEvent[],
): [string, string | undefined][] {
  return events.flatMap((event) =>
    event.type === 'prompt' ? [[event.text, event.into]] : [],
  );
}

test("a steer that meets the turn's end on Claude's adapter is refused, and goes as the next turn", () =>
  onFake(
    ['--steering', 'claude', '--steer-late'],
    async (conversation, events) => {
      conversation.send('text');
      await went();

      let queued = 0;

      expect(
        conversation.tell(MAIN, 'Stop.', () => (queued += 1)),
      ).toStrictEqual('sent');
      await until(
        () => events.filter((event) => event.type === 'result').length === 2,
      );

      expect(promptsIn(events)).toStrictEqual([
        ['text', undefined],
        ['Stop.', undefined],
      ]);
      // It waited after all, which the sender's row is told.
      expect(queued).toStrictEqual(1);
    },
  ));

test("a turn Codex's adapter starts with a steer that missed the turn is cancelled at once, and the message goes as chord's next turn, alone", async () => {
  let cancels = 0;

  await onFake(
    ['--steering', 'codex', '--steer-late'],
    async (conversation, events) => {
      conversation.send('text');
      await went();

      let queued = 0;

      // A scenario's name, so the agent's own turn with it works on long
      // after the cancel, were there none.
      expect(
        conversation.tell(MAIN, 'slow', () => (queued += 1)),
      ).toStrictEqual('sent');
      // The turn ends with the steer still out; the person's prompt, sent
      // now, waits for it, as Codex's adapter is starting a turn of its own.
      await until(() => events.some((event) => event.type === 'result'));
      conversation.send('hi');

      expect(events.at(-1)).toMatchObject({ type: 'queued', text: 'hi' });
      await until(
        () =>
          promptsIn(events).length === 3 && saidIn(events).includes('Working'),
      );

      expect(cancels).toStrictEqual(1);
      expect(queued).toStrictEqual(1);
      expect(promptsIn(events)).toStrictEqual([
        ['text', undefined],
        ['hi', undefined],
        ['slow', undefined],
      ]);
      expect(
        events.some(
          (event) => event.type === 'queued' && event.text === 'slow',
        ),
      ).toBeTruthy();

      // Were the agent's own turn left to run, its thousand steps would
      // outlast chord's wait for quiet, and chord's next prompt would start
      // alongside it.
      expect(saidIn(events)).not.toContain('Started alongside');
      conversation.interrupt();
    },
    (session) => {
      const cancel = session.cancel.bind(session);

      return Object.assign(session, {
        cancel: () => {
          cancels += 1;

          return cancel();
        },
      });
    },
  );
});

test("what a turn Codex's adapter started on its own sends is that turn's, closed by chord's line, never the reply before it", () =>
  onFake(
    ['--steering', 'codex', '--steer-late'],
    async (conversation, events) => {
      conversation.send('text');
      await went();
      conversation.tell(MAIN, 'Then the docs.');
      await until(
        () => events.filter((event) => event.type === 'result').length === 2,
      );

      const line = events.find((event) => event.type === 'self_started');

      assert(line?.type === 'self_started');
      expect(line.from).toStrictEqual(MAIN);

      const first = events.find((event) => event.type === 'prompt');

      assert(first?.type === 'prompt');

      const next = events.findLast((event) => event.type === 'prompt');

      assert(next?.type === 'prompt');

      // Whatever the agent's own turn said before the cancel landed is its
      // own, and chord's next turn says it got the message: never the turn
      // of chord's that ended before them.
      const said = events.flatMap((event) =>
        event.type === 'update' &&
        event.update.sessionUpdate === 'agent_message_chunk' &&
        event.update.content.type === 'text' &&
        event.update.content.text.startsWith('Received the message')
          ? [event.turnId]
          : [],
      );

      expect(said).toContain(next.turnId);
      expect(
        said.every((turnId) => [line.turnId, next.turnId].includes(turnId)),
      ).toBeTruthy();
      expect(said).not.toContain(first.turnId);
      // Before the message went as chord's next turn.
      expect(events.indexOf(line)).toBeLessThan(events.indexOf(next));
    },
  ));

test("a second message told while the first steer is out never goes into the turn Codex's adapter started with the first, which chord cancels", () =>
  onFake(
    ['--steering', 'codex', '--steer-late'],
    async (conversation, events) => {
      conversation.send('text');
      await went();
      conversation.tell(MAIN, 'Run the tests.');
      conversation.tell(MAIN, 'Stop.');
      await until(
        () => events.filter((event) => event.type === 'result').length === 3,
      );

      expect(promptsIn(events)).toStrictEqual([
        ['text', undefined],
        ['Run the tests.', undefined],
        ['Stop.', undefined],
      ]);
      expect(saidIn(events)).not.toContain('Read the message from main.');
    },
  ));

test("what the agent's own turn says on its way to the cancel is folded under that turn, above chord's line, not the reply before it", async () => {
  const { session } = heldSession();
  const { promise: steered, resolve: steer } =
    Promise.withResolvers<'startedNewTurn'>();
  const { promise: ended, resolve: end } = Promise.withResolvers<TurnResult>();
  const listeners: ((update: SessionUpdate) => void)[] = [];
  const said = (text: string) => {
    for (const listener of listeners) {
      listener({
        sessionUpdate: 'agent_message_chunk',
        content: { type: 'text', text },
      });
    }
  };

  let prompts = 0;
  const steering = Object.assign(session, {
    subscribe: (listener: (update: SessionUpdate) => void) => {
      listeners.push(listener);

      return () => {};
    },
    steers: () => true,
    steer: () => steered,
    prompt: () => {
      prompts += 1;

      return {
        id: String(prompts),
        sent: Promise.resolve([]),
        result:
          prompts === 1
            ? ended
            : Promise.resolve({ status: 'completed', stopReason: 'end_turn' }),
      };
    },
    // Its own turn's chunk arrives as the cancel goes out.
    cancel: () => {
      said('Received the message.');

      return Promise.resolve();
    },
  });
  const events: ConversationEvent[] = [];
  const conversation = new Conversation(
    () => Promise.resolve(steering),
    (event) => events.push(event),
  );

  conversation.start();
  await until(() => events.some((event) => event.type === 'connected'));
  conversation.send('go');
  await went();
  said('I will run the tests.');
  conversation.tell(MAIN, 'Stop.');
  end({ status: 'completed', stopReason: 'end_turn' });
  await until(() => events.some((event) => event.type === 'result'));
  steer('startedNewTurn');
  await until(() => prompts === 2);

  const entries = events
    .filter((event): event is TranscriptAction =>
      ['prompt', 'update', 'result', 'self_started'].includes(event.type),
    )
    .reduce(reduceTranscript, emptyTranscript)
    .entries.map((entry) => [
      entry.kind,
      'text' in entry ? entry.text : 'alone' in entry ? entry.alone : undefined,
    ]);

  expect(entries).toStrictEqual([
    ['user', 'go'],
    ['assistant', 'I will run the tests.'],
    ['assistant', 'Received the message.'],
    ['self_started', false],
    ['message', 'Stop.'],
  ]);
  await conversation.close();
});

test('a steer the agent refuses, as when the turn ended on the way, goes as the next turn', async () => {
  const { session } = heldSession();
  const { promise: answered, resolve: answer } =
    Promise.withResolvers<TurnResult>();
  const prompts: string[] = [];
  const steering = Object.assign(session, {
    steers: () => true,
    steer: () => Promise.resolve('refused' as const),
    prompt: (text: string) => {
      prompts.push(text);

      return {
        id: text,
        sent: Promise.resolve([]),
        result:
          prompts.length === 1
            ? answered
            : Promise.resolve({ status: 'completed', stopReason: 'end_turn' }),
        cancel: () => Promise.resolve(),
      };
    },
  });
  const events: ConversationEvent[] = [];
  const conversation = new Conversation(
    () => Promise.resolve(steering),
    (event) => events.push(event),
  );

  conversation.start();
  await until(() => events.some((event) => event.type === 'connected'));
  conversation.send('slow');
  await went();

  expect(conversation.tell(MAIN, 'Stop.')).toStrictEqual('sent');
  await until(() => events.some((event) => event.type === 'queued'));
  answer({ status: 'completed', stopReason: 'end_turn' });
  await until(() => prompts.length === 2);

  expect(prompts[1]).toContain('Stop.');
  expect(
    !events.some((event) => event.type === 'prompt' && event.into),
  ).toBeTruthy();
  await conversation.close();
});

/**
 * A session that steers, whose first turn runs until `end`, with every
 * steer's answer and its prompt's going out in the test's hands, and its
 * permissions and forms asked from the test.
 */
async function steeringStub() {
  const { session } = heldSession();
  const { promise: ended, resolve: end } = Promise.withResolvers<TurnResult>();
  const { promise: went, resolve: go } =
    Promise.withResolvers<readonly never[]>();
  const permissions: ((request: PendingPermission) => void)[] = [];
  const elicitations: ((request: PendingElicitation) => void)[] = [];
  const updates: ((update: SessionUpdate) => void)[] = [];
  const steers: {
    readonly text: string;
    readonly answer: (outcome: SteerOutcome) => void;
  }[] = [];
  const prompts: string[] = [];
  const steering = Object.assign(session, {
    permissions: {
      subscribe: (listener: (request: PendingPermission) => void) => {
        permissions.push(listener);

        return () => {};
      },
    },
    elicitations: {
      subscribe: (listener: (request: PendingElicitation) => void) => {
        elicitations.push(listener);

        return () => {};
      },
    },
    subscribe: (listener: (update: SessionUpdate) => void) => {
      updates.push(listener);

      return () => {};
    },
    steers: () => true,
    steer: (text: string) => {
      const { promise, resolve } = Promise.withResolvers<SteerOutcome>();

      steers.push({ text, answer: resolve });

      return promise;
    },
    cancel: () => Promise.resolve(),
    prompt: (text: string) => {
      prompts.push(text);

      return {
        id: text,
        sent: prompts.length === 1 ? went : Promise.resolve([]),
        result:
          prompts.length === 1
            ? ended
            : Promise.resolve({ status: 'completed', stopReason: 'end_turn' }),
        cancel: () => Promise.resolve(),
      };
    },
  });
  const events: ConversationEvent[] = [];
  const conversation = new Conversation(
    () => Promise.resolve(steering),
    (event) => events.push(event),
  );

  conversation.start();
  await until(() => events.some((event) => event.type === 'connected'));

  const ask = (id: string) => {
    for (const listener of permissions) {
      listener({
        id,
        sessionId: 'held',
        toolCall: { toolCallId: id, title: 'Write notes.txt' },
        options: [{ optionId: 'allow', name: 'Allow', kind: 'allow_once' }],
        signal: new AbortController().signal,
        resolve: () => {},
        reject: () => {},
      });
    }
  };

  const form = (id: string) => {
    for (const listener of elicitations) {
      listener({
        id,
        wait: { id } as unknown as PendingElicitation['wait'],
        signal: new AbortController().signal,
        answer: () => {},
      });
    }
  };

  const say = (text: string) => {
    for (const listener of updates) {
      listener({
        sessionUpdate: 'agent_message_chunk',
        content: { type: 'text', text },
      });
    }
  };

  const settled = () => new Promise((resolve) => setTimeout(resolve, 10));

  return {
    conversation,
    events,
    steers,
    prompts,
    go: () => go([]),
    end: () => end({ status: 'completed', stopReason: 'end_turn' }),
    ask,
    form,
    say,
    settled,
  };
}

/** The turn id of the first prompt among `events`. */
function firstTurn(events: readonly ConversationEvent[]): string | undefined {
  return events.find((event) => event.type === 'prompt')?.turnId;
}

for (const wait of ['permission', 'form'] as const) {
  test(`a message behind the steer ahead waits on a ${wait} asked meanwhile, and goes into the turn once it is answered`, async () => {
    const stub = await steeringStub();
    const { conversation, events, steers } = stub;

    conversation.send('go');
    stub.go();
    await stub.settled();
    stub.ask('first');
    conversation.tell(MAIN, 'Run the tests.');
    conversation.tell(MAIN, 'Then the docs.');
    conversation.choose('first', 'allow');
    await until(() => steers.length === 1);

    if (wait === 'permission') {
      stub.ask('second');
    } else {
      stub.form('second');
    }

    steers[0]!.answer('injected');
    await stub.settled();

    // The second waits for the answer, marked so, as one told now would.
    expect(steers).toHaveLength(1);
    expect(promptsIn(events)).toStrictEqual([
      ['go', undefined],
      ['Run the tests.', firstTurn(events)],
    ]);
    expect(events.at(-1)).toMatchObject({
      type: 'queued',
      text: 'Then the docs.',
      afterAnswer: true,
    });

    if (wait === 'permission') {
      conversation.choose('second', 'allow');
    } else {
      conversation.answer('second', { action: 'decline' });
    }

    await until(() => steers.length === 2);
    steers[1]!.answer('injected');
    await until(() => promptsIn(events).length === 3);

    expect(steers[1]!.text).toContain('Then the docs.');
    expect(promptsIn(events).at(-1)).toStrictEqual([
      'Then the docs.',
      firstTurn(events),
    ]);
    stub.end();
    await conversation.close();
  });
}

test('a message waiting on a question asked while the steer ahead was out goes as the next turn when the turn ends first', async () => {
  const stub = await steeringStub();
  const { conversation, events, steers, prompts } = stub;

  conversation.send('go');
  stub.go();
  await stub.settled();
  conversation.tell(MAIN, 'Run the tests.');
  conversation.tell(MAIN, 'Then the docs.');
  await until(() => steers.length === 1);
  stub.ask('first');
  steers[0]!.answer('injected');
  await stub.settled();
  stub.end();
  await until(() => prompts.length === 2);

  expect(steers).toHaveLength(1);
  expect(prompts[1]).toContain('Then the docs.');
  expect(promptsIn(events)).toStrictEqual([
    ['go', undefined],
    ['Run the tests.', firstTurn(events)],
    ['Then the docs.', undefined],
  ]);
  await conversation.close();
});

test('a message told while the prompt waits to go, as one with mentions does, is queued behind the turn and never steered', async () => {
  const stub = await steeringStub();
  const { conversation, events, steers, prompts } = stub;

  conversation.send('go');

  expect(conversation.tell(MAIN, 'Stop.')).toStrictEqual('queued');
  stub.go();
  await stub.settled();
  stub.say('Done.');
  stub.end();
  await until(() => prompts.length === 2);

  expect(steers).toHaveLength(0);
  expect(promptsIn(events)).toStrictEqual([
    ['go', undefined],
    ['Stop.', undefined],
  ]);
  // The reply is the turn's that asked for it, with no turn of the agent's
  // own to fold it under.
  expect(
    events.find(
      (event) =>
        event.type === 'update' &&
        event.update.sessionUpdate === 'agent_message_chunk',
    ),
  ).toMatchObject({ turnId: firstTurn(events) });
  expect(!events.some((event) => event.type === 'self_started')).toBeTruthy();
  await conversation.close();
});

/**
 * A session on the fake that names chord's server `chord`, as the window
 * gives it one, and keeps every prompt it sends the agent in `sent`.
 */
function noting(sent: string[]) {
  return (session: Session): Session => {
    const prompt = session.prompt.bind(session);

    return Object.assign(session, {
      chordServer: {
        type: 'http' as const,
        name: 'chord',
        url: 'http://127.0.0.1:1/mcp',
        headers: [],
      },
      prompt: ((text, ...rest) => {
        sent.push(text);

        return prompt(text, ...rest);
      }) as Session['prompt'],
    });
  };
}

/** Until `count` turns have ended among `events`. */
function ended(events: readonly ConversationEvent[], count: number) {
  return until(
    () => events.filter((event) => event.type === 'result').length === count,
  );
}

test("chord's calls the agent cut off before they reached chord are told to it ahead of its next turn, once, a line each", async () => {
  const sent: string[] = [];

  await onFake(
    ['--steering', 'claude'],
    async (conversation, events) => {
      conversation.send('cutcalls');
      await ended(events, 1);
      conversation.send('text');
      await ended(events, 2);
      conversation.send('text');
      await ended(events, 3);

      expect(sent[1]).toStrictEqual(
        `<message from="chord">\n${cutNote([
          { tool: 'send_message', input: { to: 'main', text: CUT_MESSAGE } },
          { tool: 'open_agent', input: CUT_OPEN },
        ])}\n</message>\n\ntext`,
      );
      expect(sent[2]).toStrictEqual('text');
      expect(saidIn(events)).toContain(
        "Received chord's note: Your send_message to @main",
      );
      // The person's prompt is drawn as they typed it.
      expect(
        events.flatMap((event) =>
          event.type === 'prompt' ? [event.text] : [],
        ),
      ).toStrictEqual(['cutcalls', 'text', 'text']);
    },
    noting(sent),
  );
});

test('a cut call chord served after all reached it, and the note names only the calls that did not', async () => {
  const sent: string[] = [];
  const input = { to: 'main', text: CUT_MESSAGE };

  await onFake(
    ['--steering', 'claude'],
    async (conversation, events) => {
      conversation.send('cutcalls');
      // The send_message\'s arguments came: chord serves it as the batch waits.
      await until(() =>
        events.some(
          (event) =>
            event.type === 'update' &&
            event.update.sessionUpdate === 'tool_call_update' &&
            JSON.stringify(event.update.rawInput) === JSON.stringify(input),
        ),
      );
      conversation.served({
        tool: 'send_message',
        input,
        answer: { delivered: 'sent', to: 'main' },
      });
      await ended(events, 1);
      conversation.send('text');
      await ended(events, 2);

      expect(sent[1]).toStrictEqual(
        `<message from="chord">\n${cutNote([
          { tool: 'open_agent', input: CUT_OPEN },
        ])}\n</message>\n\ntext`,
      );
    },
    noting(sent),
  );
});

test('cut calls are told once each, in the order they were made, whatever order they failed in', async () => {
  const sent: string[] = [];

  await onFake(
    ['--steering', 'claude'],
    async (conversation, events) => {
      conversation.send('cutcallsback');
      await ended(events, 1);
      conversation.send('text');
      await ended(events, 2);

      expect(sent[1]).toStrictEqual(
        `<message from="chord">\n${cutNote([
          { tool: 'send_message', input: { to: 'main', text: CUT_MESSAGE } },
          { tool: 'open_agent', input: CUT_OPEN },
          { tool: 'list_sessions', input: {} },
        ])}\n</message>\n\ntext`,
      );
    },
    noting(sent),
  );
});

test('a cut call is told though chord served another tool with the same arguments', async () => {
  const sent: string[] = [];

  await onFake(
    ['--steering', 'claude'],
    async (conversation, events) => {
      conversation.send('cutcallsback');
      await until(() =>
        events.some(
          (event) =>
            event.type === 'update' &&
            event.update.sessionUpdate === 'tool_call' &&
            event.update.title === 'mcp__chord__list_sessions',
        ),
      );
      // list_agents({}) served: the cut list_sessions({}) is not it.
      conversation.served({ tool: 'list_agents', input: {}, answer: {} });
      await ended(events, 1);
      conversation.send('text');
      await ended(events, 2);

      expect(sent[1]).toContain(
        'Your list_sessions call was cut off before it reached chord',
      );
    },
    noting(sent),
  );
});

test('a note a prompt never took stays with its session, never the one clear starts after it', async () => {
  const opened: {
    prompts: string[];
    update: (update: SessionUpdate) => void;
    turns: {
      went: (links: readonly never[] | undefined) => void;
      end: () => void;
    }[];
  }[] = [];
  const open = () => {
    const { session } = heldSession();
    const own: (typeof opened)[number] = {
      prompts: [],
      update: () => {},
      turns: [],
    };

    opened.push(own);

    return Promise.resolve(
      Object.assign(session, {
        chordServer: {
          type: 'http' as const,
          name: 'chord',
          url: 'http://127.0.0.1:1/mcp',
          headers: [],
        },
        steers: () => false,
        cutsCallsOnSteer: () => true,
        subscribe: (listener: (update: SessionUpdate) => void) => {
          own.update = listener;

          return () => {};
        },
        prompt: (text: string) => {
          const sent = Promise.withResolvers<readonly never[] | undefined>();
          const result = Promise.withResolvers<TurnResult>();

          own.prompts.push(text);
          own.turns.push({
            went: sent.resolve,
            end: () =>
              result.resolve({ status: 'completed', stopReason: 'end_turn' }),
          });

          return {
            id: text,
            sent: sent.promise,
            result: result.promise,
            cancel: () => Promise.resolve(),
          };
        },
      }),
    );
  };

  const events: ConversationEvent[] = [];
  const conversation = new Conversation(open, (event) => events.push(event));
  const connected = (count: number) =>
    until(
      () =>
        events.filter((event) => event.type === 'connected').length === count,
    );

  conversation.start();
  await connected(1);

  const [first] = opened;

  conversation.send('first');
  await until(() => first!.turns.length === 1);
  first!.turns[0]!.went([]);
  await went();
  first!.update({
    sessionUpdate: 'tool_call',
    toolCallId: 'cut',
    title: 'mcp__chord__send_message',
    status: 'pending',
    rawInput: { to: 'main', text: 'Hi' },
  });
  first!.update({
    sessionUpdate: 'tool_call_update',
    toolCallId: 'cut',
    status: 'failed',
    _meta: { claudeCode: { nonExecutionKind: 'interrupted' } },
  });
  first!.turns[0]!.end();
  await ended(events, 1);

  // The next prompt takes the note but has not gone when clear starts anew.
  conversation.send('second');
  await until(() => first!.turns.length === 2);
  expect(first!.prompts[1]).toContain('Your send_message to @main');
  conversation.clear();
  await connected(2);
  first!.turns[1]!.went(undefined);
  first!.turns[1]!.end();
  await new Promise((resolve) => setTimeout(resolve, 10));

  conversation.send('third');
  await until(() => opened[1]!.prompts.length === 1);
  expect(opened[1]!.prompts).toStrictEqual(['third']);
});

describe('CHD-417 tester: held steer lifecycle', () => {
  test('serialized messages keep separate snapshots when the second call opens between them', () =>
    onFake(['--steering', 'claude'], async (conversation, events) => {
      const has = (id: string) =>
        events.some(
          (event) =>
            event.type === 'update' &&
            event.update.sessionUpdate === 'tool_call' &&
            event.update.toolCallId === id,
        );

      conversation.send('overlap');
      await until(() => has('overlap-a'));
      conversation.tell(MAIN, 'First.');
      await until(() => has('overlap-b'));
      conversation.tell(MAIN, 'Second.');
      await until(() => events.some((event) => event.type === 'result'));

      const order = events.flatMap((event) =>
        event.type === 'update' &&
        event.update.sessionUpdate === 'tool_call_update' &&
        event.update.status === 'completed'
          ? [event.update.toolCallId]
          : event.type === 'prompt' && event.into !== undefined
            ? [event.text]
            : [],
      );

      expect(order).toStrictEqual([
        'overlap-a',
        'First.',
        'overlap-b',
        'Second.',
      ]);
      expect(
        promptsIn(events)
          .slice(1)
          .map(([, into]) => into),
      ).toStrictEqual([firstTurn(events), firstTurn(events)]);
    }));

  test('a failed snapshotted call releases its message before a later call ends', () =>
    onFake(['--steering', 'claude'], async (conversation, events) => {
      conversation.send('overlapfail');
      await until(() =>
        events.some(
          (event) =>
            event.type === 'update' &&
            event.update.sessionUpdate === 'tool_call' &&
            event.update.toolCallId === 'overlapfail-a',
        ),
      );
      conversation.tell(MAIN, 'After the failed call.');
      await until(() => events.some((event) => event.type === 'result'));

      const order = events.flatMap((event) =>
        event.type === 'update' &&
        event.update.sessionUpdate === 'tool_call_update'
          ? [`${event.update.toolCallId}: ${event.update.status}`]
          : event.type === 'prompt' && event.into !== undefined
            ? [event.text]
            : [],
      );

      expect(order).toStrictEqual([
        'overlapfail-a: failed',
        'After the failed call.',
        'overlapfail-b: completed',
      ]);
    }));

  for (const answer of ['allow', 'deny']) {
    test(`a permission ${answer} releases the message only after the other top-level call ends`, () =>
      onFake(['--steering', 'claude'], async (conversation, events) => {
        conversation.send('overlapask');
        await until(() =>
          events.some((event) => event.type === 'permission_requested'),
        );

        const asked = events.find(
          (event) => event.type === 'permission_requested',
        );

        assert(asked?.type === 'permission_requested');
        assert(asked.permission.toolCallId !== undefined);
        expect(conversation.tell(MAIN, 'After both calls.')).toBe('queued');
        conversation.choose(asked.permission.id, answer);
        await until(() =>
          events.some(
            (event) =>
              event.type === 'prompt' && event.text === 'After both calls.',
          ),
        );

        const sent = events.findIndex(
          (event) =>
            event.type === 'prompt' && event.text === 'After both calls.',
        );
        const ended = (id: string, status: string) =>
          events.findIndex(
            (event) =>
              event.type === 'update' &&
              event.update.sessionUpdate === 'tool_call_update' &&
              event.update.toolCallId === id &&
              event.update.status === status,
          );
        const write = ended(
          asked.permission.toolCallId,
          answer === 'allow' ? 'completed' : 'failed',
        );
        const other = ended('overlapask-a', 'completed');

        expect(write >= 0).toBe(true);
        expect(other > write).toBe(true);
        expect(sent > other).toBe(true);
      }));
  }

  test('an open subagent-only call never holds a steer into its parent', () =>
    onFake(['--steering', 'claude'], async (conversation, events) => {
      conversation.send('subagentcall');
      await until(() =>
        events.some(
          (event) =>
            event.type === 'update' &&
            event.subagentId !== undefined &&
            event.update.sessionUpdate === 'tool_call' &&
            event.update.status === 'in_progress',
        ),
      );
      conversation.tell(MAIN, 'For the parent.');
      await until(() => events.some((event) => event.type === 'result'));

      const order = events.flatMap((event) =>
        event.type === 'update' &&
        event.subagentId !== undefined &&
        event.update.sessionUpdate === 'tool_call_update' &&
        event.update.status === 'completed'
          ? ['child ended']
          : event.type === 'prompt' && event.into !== undefined
            ? [event.text]
            : [],
      );

      expect(order).toStrictEqual(['For the parent.', 'child ended']);
    }));

  for (const action of ['clear', 'close'] as const) {
    test(`${action} discards a held steer without delivering it to the old or new session`, async () => {
      const steered: string[] = [];
      const pids: number[] = [];

      await onFake(
        ['--steering', 'claude'],
        async (conversation, events) => {
          conversation.send('bash');
          await callOpen(events);
          conversation.tell(MAIN, 'Must be discarded.');
          expect(steered).toStrictEqual([]);

          if (action === 'clear') {
            conversation.clear();
            await until(
              () =>
                events.filter((event) => event.type === 'connected').length ===
                2,
            );
            conversation.send('slow');
            await until(() => saidIn(events).includes('Working'));
            conversation.tell(MAIN, 'New session only.');
            await until(() => steered.length === 1);
            await until(() =>
              saidIn(events).includes('Read the message from main.'),
            );
            expect(steered[0]).toContain('New session only.');
            conversation.interrupt();
          } else {
            await conversation.close();
          }

          expect(steered.join('\n')).not.toContain('Must be discarded.');
          expect(promptsIn(events).map(([text]) => text)).not.toContain(
            'Must be discarded.',
          );
        },
        (session) => {
          pids.push(...session.agentPids);

          const steer = session.steer.bind(session);

          session.steer = (text) => {
            steered.push(text);

            return steer(text);
          };

          return session;
        },
      );

      expect(pids.length > 0).toBeTruthy();

      for (const pid of pids) {
        expect(await isAlive(pid), `fake agent ${pid} survived ${action}`).toBe(
          false,
        );
      }
    });
  }
});

describe('CHD-417 tester: cut-call note delivery', () => {
  test('a queued teammate turn takes the ordered note once without drawing a chord message row', async () => {
    const sent: string[] = [];

    await onFake(
      ['--steering', 'claude'],
      async (conversation, events) => {
        conversation.send('cutcallsback');
        await until(() =>
          events.some(
            (event) =>
              event.type === 'update' &&
              event.update.sessionUpdate === 'tool_call',
          ),
        );
        expect(conversation.deliver(MAIN, 'Continue the review.')).toBe(
          'queued',
        );
        await ended(events, 2);
        conversation.send('text');
        await ended(events, 3);

        expect(sent[1]).toContain('<message from="chord">');
        expect(sent[1]!.indexOf('Your send_message')).toBeLessThan(
          sent[1]!.indexOf('Your open_agent'),
        );
        expect(sent[1]!.indexOf('Your open_agent')).toBeLessThan(
          sent[1]!.indexOf('Your list_sessions'),
        );
        expect(sent[1]).toEndWith(
          '<message from="main">\nContinue the review.\n</message>',
        );
        expect(sent[2]).toBe('text');
        expect(
          events.some(
            (event) => event.type === 'prompt' && event.from?.name === 'chord',
          ),
        ).toBe(false);
      },
      noting(sent),
    );
  });

  test('a prompt cancelled before it goes restores the note for this session only, once', async () => {
    const attempted: string[] = [];

    await onFake(
      ['--steering', 'claude'],
      async (conversation, events) => {
        conversation.send('cutcalls');
        await ended(events, 1);
        conversation.send('cancel-before-send');
        await ended(events, 2);
        conversation.send('text');
        await ended(events, 3);
        conversation.send('text');
        await ended(events, 4);

        expect(attempted[1]).toContain('Your send_message to @main');
        expect(attempted[2]).toContain('Your send_message to @main');
        expect(attempted[2]!.match(/Your send_message/g)).toHaveLength(1);
        expect(attempted[3]).toBe('text');
      },
      (session) => {
        const observed = noting(attempted)(session);
        const prompt = observed.prompt.bind(observed);

        observed.prompt = (text, ...rest) => {
          if (text.endsWith('cancel-before-send')) {
            attempted.push(text);

            return {
              id: 'unsent',
              sent: Promise.resolve(undefined),
              result: Promise.resolve({
                status: 'cancelled',
                stopReason: 'cancelled',
              }),
              cancel: () => Promise.resolve(),
            };
          }

          return prompt(text, ...rest);
        };

        return observed;
      },
    );
  });

  test('replayed cut-call updates still mark their rows but schedule no new note', async () => {
    let history: TranscriptAction[] = [];

    await onFake(
      ['--steering', 'claude'],
      async (conversation, events) => {
        conversation.send('cutcalls');
        await ended(events, 1);

        history = [
          { type: 'prompt', turnId: 'history-1', text: 'cutcalls', at: 0 },
          ...events.flatMap((event): TranscriptAction[] =>
            event.type === 'update'
              ? [{ type: 'update', turnId: 'history-1', update: event.update }]
              : [],
          ),
        ];
      },
      noting([]),
    );

    const sent: string[] = [];

    await onFake(
      ['--steering', 'claude'],
      async (conversation, events) => {
        const replayed = history.reduce(reduceTranscript, emptyTranscript);

        expect(
          replayed.entries.filter(
            (entry) => entry.kind === 'tool' && entry.call.cut,
          ),
        ).toHaveLength(2);
        conversation.send('text');
        await ended(events, 1);
        expect(sent).toStrictEqual(['text']);
      },
      (session) =>
        Object.assign(noting(sent)(session), { history: () => history }),
    );
  });

  test('an interrupted call on a different server schedules no chord retry note', async () => {
    const sent: string[] = [];

    await onFake(
      ['--steering', 'claude'],
      async (conversation, events) => {
        conversation.send('cutcalls');
        await ended(events, 1);
        conversation.send('text');
        await ended(events, 2);
        expect(sent[1]).toBe('text');
      },
      (session) =>
        Object.assign(noting(sent)(session), {
          chordServer: {
            type: 'http' as const,
            name: 'chord-2',
            url: 'http://127.0.0.1:1/mcp',
            headers: [],
          },
        }),
    );
  });
});

describe('CHD-423 tester: mixed queue holds', () => {
  test('answer-to-call reason replacement preserves the earlier call-held message and delivery order', () =>
    onFake(['--steering', 'claude'], async (conversation, events) => {
      conversation.send('overlapask');
      await until(() =>
        events.some(
          (event) =>
            event.type === 'update' &&
            event.update.sessionUpdate === 'tool_call' &&
            event.update.toolCallId === 'overlapask-a',
        ),
      );
      conversation.tell(MAIN, 'First, while the call runs.');
      await until(() =>
        events.some((event) => event.type === 'permission_requested'),
      );
      conversation.tell(MAIN, 'Second, while the answer waits.');

      const asked = events.find(
        (event) => event.type === 'permission_requested',
      );

      assert(asked?.type === 'permission_requested');
      conversation.choose(asked.permission.id, 'allow');
      await until(
        () =>
          events.filter(
            (event) => event.type === 'prompt' && event.from?.name === 'main',
          ).length === 2,
      );

      const queued = events.flatMap((event) =>
        event.type === 'queued' ? [event] : [],
      );

      expect(
        queued
          .slice(0, 3)
          .map((event) => [event.text, event.afterCalls, event.afterAnswer]),
      ).toStrictEqual([
        ['First, while the call runs.', true, undefined],
        ['Second, while the answer waits.', undefined, true],
        ['Second, while the answer waits.', true, undefined],
      ]);
      expect(queued[1]!.turnId).toBe(queued[2]!.turnId);
      expect(
        queued.filter((event) => event.text.startsWith('First,')).length,
      ).toBe(1);
      expect(
        promptsIn(events)
          .slice(1)
          .map(([text]) => text),
      ).toStrictEqual([
        'First, while the call runs.',
        'Second, while the answer waits.',
      ]);
    }));

  test('an adapter refusal starts the held message as the next turn with the same row identity', () =>
    onFake(
      ['--steering', 'claude', '--steer-late'],
      async (conversation, events) => {
        conversation.send('bash');
        await callOpen(events);
        conversation.tell(MAIN, 'After refusal.');
        await ended(events, 2);

        const queued = events.flatMap((event) =>
          event.type === 'queued' ? [event] : [],
        );

        expect(queued.filter((event) => event.afterCalls)).toHaveLength(1);

        const taken = events.find(
          (event) => event.type === 'prompt' && event.text === 'After refusal.',
        );

        assert(taken?.type === 'prompt');
        expect(taken.turnId).toBe(queued[0]!.turnId);
        expect(taken.into).toBeUndefined();
        expect(new Set(queued.map((event) => event.turnId)).size).toBe(1);
        expect(promptsIn(events)).toStrictEqual([
          ['bash', undefined],
          ['After refusal.', undefined],
        ]);
      },
    ));
});

describe('CHD-452 tester: two-steer gate boundaries', () => {
  function callEnded(events: readonly ConversationEvent[]) {
    return until(() =>
      events.some(
        (event) =>
          event.type === 'update' &&
          event.update.sessionUpdate === 'tool_call_update' &&
          event.update.status === 'completed',
      ),
    );
  }

  test('a first steer read before the call ends still counts when the second arrives later', () =>
    onFake(['--steering', 'codex'], async (conversation, events) => {
      conversation.send('callchildtwo');
      await until(() =>
        events.some(
          (event) =>
            event.type === 'update' &&
            event.update.sessionUpdate === 'tool_call',
        ),
      );
      conversation.tell(MAIN, 'First, during the call.');
      await callEnded(events);

      expect(saidIn(events)).toBe('Read the message from main.\n\n');
      expect(events.some((event) => event.type === 'result')).toBe(false);

      conversation.tell(MAIN, 'Second, after the call.');
      await ended(events, 1);

      expect(saidIn(events)).toBe(
        'Read the message from main.\n\n' +
          'Read the message from main.\n\nThe tests pass.',
      );
      expect(promptsIn(events).map(([text]) => text)).toStrictEqual([
        'callchildtwo',
        'First, during the call.',
        'Second, after the call.',
      ]);
    }));

  for (const end of ['cancel', 'close'] as const) {
    test(`${end} releases a turn waiting for its missing second steer`, async () => {
      let owner: Session | undefined;

      await onFake(
        ['--steering', 'claude'],
        async (conversation, events) => {
          conversation.send('callchildtwo');
          await until(() =>
            events.some(
              (event) =>
                event.type === 'update' &&
                event.update.sessionUpdate === 'tool_call',
            ),
          );
          conversation.tell(MAIN, 'Only the first.');
          await callEnded(events);
          await until(() =>
            events.some(
              (event) =>
                event.type === 'prompt' &&
                event.into !== undefined &&
                event.text === 'Only the first.',
            ),
          );

          expect(events.some((event) => event.type === 'result')).toBe(false);

          if (end === 'cancel') {
            conversation.interrupt();
            await ended(events, 1);

            const result = events.find((event) => event.type === 'result');

            assert(result?.type === 'result');
            expect(result.result.status).toBe('cancelled');
            conversation.send('callchild');
            await ended(events, 2);
            expect(saidIn(events)).toEndWith('The tests pass.');
          } else {
            assert(owner);

            const started = Date.now();

            await conversation.close();
            expect(Date.now() - started).toBeLessThan(1500);
            expect(owner.agentPids.size).toBe(0);
            await owner.exited;
          }
        },
        (session) => {
          owner = session;

          return session;
        },
      );
    });
  }
});

describe('a request with no turn running (CHD-158)', () => {
  test("the session's own agent asking after its answer waits on the person, and hears the answer", () =>
    onFake([], async (conversation, events) => {
      conversation.send('mainbetween');
      await until(() => events.some((event) => event.type === 'result'));
      await until(() =>
        events.some((event) => event.type === 'permission_requested'),
      );

      const asked = events.find(
        (event) => event.type === 'permission_requested',
      );

      assert(asked?.type === 'permission_requested');
      expect(asked.between).toBeTrue();
      expect(asked.at).toBeNumber();
      expect(asked.permission.title).toStrictEqual('Write notes/report.md');
      conversation.choose(asked.permission.id, 'allow');
      await until(() => saidIn(events).includes('Permission: allow.'));
      expect(
        events.some((event) => event.type === 'permission_settled'),
      ).toBeTrue();
    }));

  test('a subagent that outlived its turn asks a permission and a form, and hears both answers', () =>
    onFake([], async (conversation, events) => {
      conversation.send('claudebetween');
      await until(() => events.some((event) => event.type === 'result'));
      await until(() =>
        events.some((event) => event.type === 'permission_requested'),
      );

      const asked = events.find(
        (event) => event.type === 'permission_requested',
      );

      assert(asked?.type === 'permission_requested');
      expect(asked.between).toBeTrue();
      expect(asked.permission.subagentId).toBeString();
      conversation.choose(asked.permission.id, 'allow');
      await until(() =>
        events.some((event) => event.type === 'elicitation_requested'),
      );

      const form = events.find(
        (event) => event.type === 'elicitation_requested',
      );

      assert(form?.type === 'elicitation_requested');
      expect(form.elicitation.between).toBeTrue();
      // Asked by the subagent, which the box names.
      expect(form.elicitation.asker).toStrictEqual(asked.permission.subagentId);
      conversation.answer(form.elicitation.id, { action: 'decline' });
      await until(() =>
        saidIn(events).includes('Write allowed; form decline.'),
      );
    }));
});

describe('CHD-158 tester: requests outside a turn', () => {
  test('before the first prompt, permissions, forms and links wait independently until answered or withdrawn', async () => {
    let owner: Session | undefined;

    await onFake(
      [],
      async (conversation, events) => {
        assert(owner);

        const abort = new AbortController();
        const permission = owner.permissions.handler(
          {
            sessionId: owner.id,
            toolCall: {
              toolCallId: 'startup',
              title: 'Write notes/startup.md',
            },
            options: [{ optionId: 'allow', name: 'Allow', kind: 'allow_once' }],
          },
          abort.signal,
        );
        const form = owner.elicitations.handler(
          {
            sessionId: owner.id,
            mode: 'form',
            message: 'Choose a target',
            requestedSchema: { type: 'object', properties: {} },
          },
          new AbortController().signal,
        );
        const link = owner.elicitations.handler(
          {
            sessionId: owner.id,
            mode: 'url',
            message: 'Approve the target',
            url: 'https://example.com/approve',
            elicitationId: 'startup-link',
          },
          new AbortController().signal,
        );
        const asked = events.find(
          (event) => event.type === 'permission_requested',
        );
        const forms = events.filter(
          (event) => event.type === 'elicitation_requested',
        );

        assert(asked?.type === 'permission_requested');
        expect(asked).toMatchObject({ turnId: 'session', between: true });
        expect(forms).toHaveLength(2);
        expect(forms.every((event) => event.elicitation.between === true)).toBe(
          true,
        );
        expect(events.some((event) => event.type === 'prompt')).toBe(false);
        abort.abort();
        expect(await permission).toStrictEqual({
          outcome: { outcome: 'cancelled' },
        });
        expect(
          events.filter((event) => event.type === 'permission_settled'),
        ).toMatchObject([
          { id: asked.permission.id, answer: { type: 'withdrawn' } },
        ]);
        conversation.answer(forms[1]!.elicitation.id, { action: 'decline' });
        expect(await link).toStrictEqual({ action: 'decline' });
        conversation.answer(forms[0]!.elicitation.id, {
          action: 'accept',
          content: {},
        });
        expect(await form).toStrictEqual({ action: 'accept', content: {} });
        expect(
          events.filter((event) => event.type === 'elicitation_settled'),
        ).toHaveLength(2);
      },
      (session) => (owner = session),
    );
  });

  test('two real fake-agent sessions keep their between-turn answers separate', () =>
    Promise.all(
      ['allow', 'deny'].map((option) =>
        onFake([], async (conversation, events) => {
          conversation.send('mainbetween');
          await until(() =>
            events.some((event) => event.type === 'permission_requested'),
          );

          const asked = events.find(
            (event) => event.type === 'permission_requested',
          );

          assert(asked?.type === 'permission_requested');
          expect(asked.between).toBe(true);
          conversation.choose(asked.permission.id, option);
          await until(() => saidIn(events).includes(`Permission: ${option}.`));
          expect(
            events.filter((event) => event.type === 'permission_settled'),
          ).toHaveLength(1);
          expect(saidIn(events)).not.toContain(
            `Permission: ${option === 'allow' ? 'deny' : 'allow'}.`,
          );
        }),
      ),
    ));

  for (const stage of ['permission', 'form'] as const) {
    test(`closing an unanswered between-turn ${stage} withdraws it and stops the fake`, async () => {
      let owner: Session | undefined;

      await onFake(
        [],
        async (conversation, events) => {
          conversation.send(
            stage === 'permission' ? 'mainbetween' : 'claudebetween',
          );
          await until(() =>
            events.some((event) => event.type === 'permission_requested'),
          );

          if (stage === 'form') {
            const permission = events.find(
              (event) => event.type === 'permission_requested',
            );

            assert(permission?.type === 'permission_requested');
            conversation.choose(permission.permission.id, 'allow');
            await until(() =>
              events.some((event) => event.type === 'elicitation_requested'),
            );
          }

          await conversation.close();
          assert(owner);
          await owner.exited;
          expect(owner.agentPids.size).toBe(0);
          expect(
            events.filter(
              (event) =>
                event.type ===
                `${stage === 'form' ? 'elicitation' : 'permission'}_settled`,
            ),
          ).toMatchObject([{ answer: { type: 'withdrawn' } }]);
        },
        (session) => (owner = session),
      );
    });
  }

  test('clear removes the old wait and a fresh session can answer a prompt', async () => {
    let original: Session | undefined;

    await onFake(
      [],
      async (conversation, events) => {
        conversation.send('mainbetween');
        await until(() =>
          events.some((event) => event.type === 'permission_requested'),
        );
        conversation.clear();
        await until(
          () =>
            events.filter((event) => event.type === 'connected').length === 2,
        );
        assert(original);
        await original.exited;
        expect(original.agentPids.size).toBe(0);
        expect(events.filter((event) => event.type === 'cleared')).toHaveLength(
          1,
        );
        conversation.send('text');
        await until(() =>
          saidIn(events).includes('Hello, world. This reply came in chunks.'),
        );
        expect(saidIn(events)).not.toContain('Permission: allow.');
      },
      (session) => {
        original ??= session;

        return session;
      },
    );
  });
});

describe('a prompt or message while a request waits between turns (CHD-158)', () => {
  test('both wait in the queue for the answer, and the request stays on screen while the agent waits', () =>
    onFake([], async (conversation, events) => {
      conversation.send('mainbetween');
      await until(() => events.some((event) => event.type === 'result'));
      await until(() =>
        events.some((event) => event.type === 'permission_requested'),
      );

      expect(conversation.send('text')).toBeTrue();
      expect(conversation.tell(MAIN, 'Then the docs.')).toStrictEqual('queued');

      const queued = events.filter((event) => event.type === 'queued');

      expect(queued).toMatchObject([
        { text: 'text', afterAnswer: true },
        { text: 'Then the docs.', afterAnswer: true },
      ]);

      // Long enough for a turn the queue let go to have started.
      await new Promise((resolve) => setTimeout(resolve, 300));

      const prompts = () =>
        events.filter((event) => event.type === 'prompt').length;

      expect(prompts()).toStrictEqual(1);

      // What the window draws from the events: the request still waits,
      // between turns, on the person.
      const shown = events.reduce(reduceApp, initialAppState);

      expect(shown.transcript.turn).toMatchObject({
        status: 'awaiting_permission',
        between: true,
      });

      const asked = events.find(
        (event) => event.type === 'permission_requested',
      );

      assert(asked?.type === 'permission_requested');
      conversation.choose(asked.permission.id, 'allow');
      await until(() => saidIn(events).includes('Permission: allow.'));
      // Then, in the order they came, each as a turn of its own.
      await until(() => prompts() === 3);
      expect(
        events.flatMap((event) =>
          event.type === 'prompt' ? [event.text] : [],
        ),
      ).toStrictEqual(['mainbetween', 'text', 'Then the docs.']);

      // What the work that asked said of the answer came before the held
      // prompt went, so it is never taken for that prompt's reply.
      const said = events.findIndex(
        (event) =>
          event.type === 'update' &&
          event.update.sessionUpdate === 'agent_message_chunk' &&
          event.update.content.type === 'text' &&
          event.update.content.text.includes('Permission: allow.'),
      );
      const went = events.findIndex(
        (event) => event.type === 'prompt' && event.text === 'text',
      );

      expect(said).toBeGreaterThan(-1);
      expect(said).toBeLessThan(went);
    }));
});
