import { expect, test } from 'bun:test';
import type { ConversationEvent } from '../../src/session/conversation.ts';
import {
  fromLine,
  senderName,
  TaskAgent,
  taskName,
  type TaskParent,
  taskUpdate,
  type TaskSession,
  unwrapMessage,
  wrapMessage,
  wrapTeamMessage,
} from '../../src/session/tasks.ts';
import type { MessageFrom } from '../../src/session/transcript/types.ts';

test("a message's wrapper names its sender as its row does, and reads back", () => {
  const from: MessageFrom = {
    name: 'Fix "the" tokenizer',
    runtime: 'codex',
    note: 'report',
  };
  const wrapped = wrapMessage(from, 'Fixed.\nTwo tests added.');

  expect(wrapped).toStrictEqual(
    '<message from="Fix &quot;the&quot; tokenizer · codex · report">\n' +
      'Fixed.\nTwo tests added.\n</message>',
  );
  expect(unwrapMessage(wrapped)).toStrictEqual({
    from,
    text: 'Fixed.\nTwo tests added.',
  });
  expect(fromLine({ name: 'chord' })).toStrictEqual('chord');
  expect(unwrapMessage('Fix the tokenizer')).toStrictEqual(undefined);
});

test("a monitor's wrapper names its description, monitor, its end, and its id", () => {
  const event: MessageFrom = {
    name: 'dev server errors',
    monitor: { id: 'm1' },
  };
  const end: MessageFrom = {
    name: 'CI run 4812',
    monitor: { id: 'm2', end: { kind: 'exit', code: 1 } },
  };

  expect(wrapMessage(event, 'ERROR boom')).toStrictEqual(
    '<message from="dev server errors · monitor" monitor="m1">\nERROR boom' +
      '\n</message>',
  );
  expect(
    wrapMessage(end, 'Exited with code 1 after 6m 3s.').split('\n')[0],
  ).toStrictEqual(
    '<message from="CI run 4812 · monitor · exit code 1" monitor="m2">',
  );
  // The record keeps the end; the wrapper read back gives who and which.
  expect(unwrapMessage(wrapMessage(end, 'x'))).toStrictEqual({
    from: { name: 'CI run 4812', monitor: { id: 'm2' } },
    text: 'x',
  });
  expect(senderName(event)).toStrictEqual('dev server errors');
});

test("a task is named as asked, or by its prompt's first line", () => {
  expect(taskName(' Fix it ', 'anything')).toStrictEqual('Fix it');
  expect(taskName(undefined, '\n  Run the tests\nand say')).toStrictEqual(
    'Run the tests',
  );
  expect(taskName('', '')).toStrictEqual('task');
});

/** A parent that keeps what a task did to it, and a session that does nothing. */
function harness() {
  const relayed: ConversationEvent[] = [];
  const delivered: [MessageFrom, string][] = [];
  const ahead: [MessageFrom, string][] = [];
  const ended: string[] = [];
  const sent: string[] = [];
  const asked: string[] = [];
  const parent: TaskParent = {
    relay: (event) => relayed.push(event),
    deliver: (from, text) => delivered.push([from, text]),
    ahead: (from, text) => ahead.push([from, text]),
    ended: () => ended.push('task-1'),
  };
  const session: TaskSession = {
    start: () => {},
    send: (text) => sent.push(text) > 0,
    interrupt: () => asked.push('interrupt'),
    choose: (id, option) => asked.push(`choose ${id} ${option}`),
    reject: (id) => asked.push(`reject ${id}`),
    answer: (id) => asked.push(`answer ${id}`),
    close: () => Promise.resolve(),
  };
  const task = new TaskAgent(
    {
      id: 'task-1',
      name: 'Fix it',
      runtime: 'fake',
      model: 'fake-small',
      prompt: 'taskchild',
    },
    parent,
    () => 42,
  );

  task.begin(session);

  return { task, relayed, delivered, ahead, ended, sent, asked };
}

const MODELS: ConversationEvent = {
  type: 'model',
  models: {
    available: [
      { id: 'fake-large', name: 'Large' },
      {
        id: 'fake-small',
        name: 'Small',
      },
    ],
    current: 'fake-small',
  },
};

test("a task's first turn is its job: its work relayed under its id, its last message the report", () => {
  const { task, relayed, delivered, ended, sent } = harness();

  expect(relayed.length).toStrictEqual(1);
  task.heard(MODELS);
  task.heard({ type: 'connected', sessionId: 's1' });
  expect(sent).toStrictEqual(['taskchild']);
  task.heard({ type: 'prompt', turnId: 'r1', text: 'taskchild', at: 1 });

  const chunk = (text: string): ConversationEvent => ({
    type: 'update',
    turnId: 'r1',
    update: {
      sessionUpdate: 'agent_message_chunk',
      content: { type: 'text', text },
    },
  });

  task.heard(chunk('Looking.'));
  task.heard({
    type: 'update',
    turnId: 'r1',
    update: { sessionUpdate: 'tool_call', toolCallId: 'c1', title: 'Read a' },
  });
  task.heard(chunk('Fixed it.'));
  task.heard({
    type: 'result',
    turnId: 'r1',
    result: { status: 'completed', stopReason: 'end_turn' },
  });

  expect(
    relayed
      .slice(1, 4)
      .map((event) => (event.type === 'update' ? event.subagentId : undefined)),
  ).toStrictEqual(['task-1', 'task-1', 'task-1']);
  expect(relayed.at(-1)).toStrictEqual({
    type: 'update',
    turnId: '',
    update: {
      sessionUpdate: 'subagent_update',
      sessionId: 'task-1',
      state: { state: 'completed' },
    },
    at: 42,
  });
  expect(delivered).toStrictEqual([
    [{ name: 'Fix it', runtime: 'fake', note: 'report' }, 'Fixed it.'],
  ]);
  expect(ended).toStrictEqual(['task-1']);
  expect(task.running).toStrictEqual(false);
});

test("a task's permission is asked in the parent's name for it, and answered through it", () => {
  const { task, relayed, asked } = harness();

  task.heard({
    type: 'permission_requested',
    turnId: 'r1',
    permission: { id: 'p1', options: [] },
  });
  task.choose('p1', 'allow');

  expect(relayed.at(-1)).toStrictEqual({
    type: 'permission_requested',
    turnId: 'r1',
    permission: { id: 'p1', subagentId: 'task-1', options: [] },
    at: 42,
  });
  expect(asked).toStrictEqual(['choose p1 allow']);
});

test('a failed turn ends the task Failed with the error as its report; a refused start fails it before', () => {
  const failed = harness();

  failed.task.heard({ type: 'prompt', turnId: 'r1', text: 'x', at: 1 });
  failed.task.heard({
    type: 'result',
    turnId: 'r1',
    result: { status: 'failed', error: { message: 'rate limited' } },
  });
  expect(failed.delivered).toStrictEqual([
    [{ name: 'Fix it', runtime: 'fake', note: 'failed' }, 'rate limited'],
  ]);

  const lacking = harness();

  lacking.task.heard({
    type: 'connect_failed',
    message: 'Could not start on fake-small, asked by spawn_task: no',
  });
  lacking.task.heard({ type: 'connected', sessionId: 's1' });
  expect(lacking.delivered).toStrictEqual([
    [
      { name: 'Fix it', runtime: 'fake', note: 'failed' },
      'Could not start on fake-small, asked by spawn_task: no',
    ],
  ]);
  expect(lacking.sent).toStrictEqual([]);
  expect(lacking.ended).toStrictEqual(['task-1']);
});

test('a task the parent stopped ends Cancelled with no report, a line held for the next prompt instead', () => {
  const { task, relayed, delivered, ahead, asked } = harness();

  task.heard({ type: 'connected', sessionId: 's1' });
  task.heard({ type: 'prompt', turnId: 'r1', text: 'x', at: 1 });
  task.cancel();
  task.heard({
    type: 'result',
    turnId: 'r1',
    result: { status: 'cancelled', stopReason: 'cancelled' },
  });

  expect(asked).toStrictEqual(['interrupt']);
  expect(delivered).toStrictEqual([]);
  expect(ahead.length).toStrictEqual(1);

  const last = relayed.at(-1);

  expect(
    last?.type === 'update' && last.update.sessionUpdate === 'subagent_update'
      ? last.update.state
      : undefined,
  ).toStrictEqual({ state: 'cancelled' });
});

test('a task stopped while it starts ends Cancelled there, and its job is never sent', () => {
  const { task, delivered, ahead, ended, sent, asked } = harness();

  task.cancel();
  task.heard({ type: 'connected', sessionId: 's1' });

  expect(sent).toStrictEqual([]);
  expect(asked).toStrictEqual([]);
  expect(delivered).toStrictEqual([]);
  expect(ahead.length).toStrictEqual(1);
  expect(ended).toStrictEqual(['task-1']);
  expect(task.running).toStrictEqual(false);
});

test("a team agent's first prompt has its team part ahead of the message, and reads back with both", () => {
  const part = {
    team: 'bugfix',
    member: 'tester',
    text: 'You are tester.\n\nHow the team works:\n1. A test.',
  };
  const prompt = wrapTeamMessage(
    part,
    { name: 'bugfix', reachable: true },
    'Write the test.',
  );

  expect(prompt).toStrictEqual(
    '<team name="bugfix" role="member" member="tester">\nYou are tester.\n\n' +
      'How the team works:\n1. A test.\n</team>\n<message from="bugfix">\n' +
      'Write the test.\n</message>',
  );
  expect(unwrapMessage(prompt)).toStrictEqual({
    from: { name: 'bugfix' },
    text: 'Write the test.',
    team: part,
  });

  const lead = wrapTeamMessage(
    { team: 'bugfix', text: 'You lead.' },
    { name: 'main', reachable: true },
    'The job.',
  );

  expect(unwrapMessage(lead)?.team).toStrictEqual({
    team: 'bugfix',
    text: 'You lead.',
  });
  expect(unwrapMessage(lead)?.text).toStrictEqual('The job.');
});

test("a task's ending update carries what it spent: its turn's tokens and its last cost, marked when chord estimated it (CHD-373)", () => {
  const ending = (
    estimated: boolean,
    tokens = { inputTokens: 1000, outputTokens: 200, totalTokens: 2000 },
  ) => {
    const { task, relayed } = harness();

    task.heard(MODELS);
    task.heard({ type: 'connected', sessionId: 's1' });
    task.heard({ type: 'prompt', turnId: 'r1', text: 'taskchild', at: 1 });
    task.heard({
      type: 'update',
      turnId: 'r1',
      update: {
        sessionUpdate: 'usage_update',
        used: 2000,
        size: 200_000,
        cost: { amount: 0.0125, currency: 'USD' },
        ...(estimated ? { _meta: { 'chord/filled': ['cost'] } } : {}),
      },
    });
    task.heard({
      type: 'result',
      turnId: 'r1',
      result: { status: 'completed', stopReason: 'end_turn', usage: tokens },
    });

    const last = relayed.at(-1);

    return last?.type === 'update' ? last.update : undefined;
  };

  expect(ending(false)).toMatchObject({
    sessionUpdate: 'subagent_update',
    state: { state: 'completed' },
    _meta: {
      'chord/spent': {
        tokens: { inputTokens: 1000, outputTokens: 200, totalTokens: 2000 },
        cost: { amount: 0.0125, currency: 'USD' },
      },
    },
  });
  // The agent's own cost is not marked as chord's.
  expect(JSON.stringify(ending(false))).not.toContain('estimated');
  // A cost chord worked out says so.
  expect(ending(true)).toMatchObject({
    _meta: {
      'chord/spent': { cost: { amount: 0.0125 }, estimated: true },
    },
  });
});

test('a task whose agent reported nothing ends with nothing said of its spend (CHD-373)', () => {
  const { task, relayed } = harness();

  task.heard(MODELS);
  task.heard({ type: 'connected', sessionId: 's1' });
  task.heard({ type: 'prompt', turnId: 'r1', text: 'taskchild', at: 1 });
  task.heard({
    type: 'result',
    turnId: 'r1',
    result: { status: 'completed', stopReason: 'end_turn' },
  });

  expect(relayed.at(-1)).toStrictEqual({
    type: 'update',
    turnId: '',
    update: {
      sessionUpdate: 'subagent_update',
      sessionId: 'task-1',
      state: { state: 'completed' },
    },
    at: 42,
  });
});

test("a task's update keeps both what the task is and what it spent when it carries both (CHD-373)", () => {
  expect(
    taskUpdate(
      'task-1',
      'completed',
      { name: 'Fix it', runtime: 'fake', prompt: 'go' },
      { cost: { amount: 0.01, currency: 'USD' } },
    ),
  ).toMatchObject({
    _meta: {
      'chord/task': { name: 'Fix it', runtime: 'fake' },
      'chord/spent': { cost: { amount: 0.01, currency: 'USD' } },
    },
  });
});
