import { describe, expect, test } from 'bun:test';
import {
  Conversation,
  type ConversationEvent,
} from '../../src/session/conversation.ts';
import assert from 'node:assert/strict';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { openSession } from '../../src/session/session.ts';
import {
  entryOf,
  readPast,
  recordActions,
  type RecordEntry,
} from '../../src/session/record.ts';
import { reduceTranscript } from '../../src/session/transcript/reducer.ts';
import { emptyTranscript } from '../../src/session/transcript/types.ts';
import { fakeAgentCommand } from '../fixtures/fake.ts';
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

test("the servers a task's agent was not given are said in its parent's turn, named as the task (CHD-441)", () => {
  const { task, relayed } = harness();
  const message =
    '1 MCP server was not passed to fake, which takes them over stdio and ' +
    'HTTP only: tracker (sse). /mcp lists it.';

  task.heard({ type: 'warned', turnId: 'w1', message });
  expect(relayed).toContainEqual({
    type: 'warned',
    turnId: 'w1',
    message: `Fix it: ${message}`,
  });
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

describe('CHD-373 S1 tester: fake task spend reaches the parent record', () => {
  for (const mode of ['reported', 'tokens-only', 'no-usage'] as const) {
    test(`${mode}: ending spend and task identity survive the record roundtrip`, async () => {
      const dir = await mkdtemp(join(tmpdir(), 'chord-task-spend-'));
      const relayed: ConversationEvent[] = [];
      let ended = false;
      const task = new TaskAgent(
        {
          id: 'priced-task',
          name: 'Read the reply',
          runtime: 'fake',
          prompt: 'text',
        },
        {
          relay: (event) => relayed.push(event),
          deliver: () => {},
          ahead: () => {},
          ended: () => {
            ended = true;
          },
        },
        Date.now,
      );
      const conversation = new Conversation(
        () =>
          openSession({
            agent: 'fake',
            cwd: dir,
            agentCommand: fakeAgentCommand(
              undefined,
              ...(mode === 'reported' ? [] : [`--${mode}`]),
            ),
          }),
        (event) => task.heard(event),
      );

      try {
        task.begin(conversation);

        while (!ended) {
          await new Promise((resolve) => setTimeout(resolve, 1));
        }

        const updates = relayed.filter((event) => event.type === 'update');
        const ending = updates.at(-1);

        assert(ending?.type === 'update');

        const spent = ending.update._meta?.['chord/spent'];

        if (mode === 'no-usage') {
          expect(spent).toBeUndefined();
        } else {
          expect(spent).toMatchObject({
            tokens: { inputTokens: 1000, outputTokens: 200, totalTokens: 2000 },
          });

          if (mode === 'reported') {
            expect(spent).toMatchObject({
              cost: { amount: 0.0125, currency: 'USD' },
            });
          } else {
            assert(
              spent &&
                typeof spent === 'object' &&
                !Array.isArray(spent) &&
                'cost' in spent,
            );

            const cost = spent.cost;

            assert(
              cost &&
                typeof cost === 'object' &&
                !Array.isArray(cost) &&
                'amount' in cost &&
                'currency' in cost,
            );
            expect(cost.currency).toBe('USD');
            expect(cost.amount).toBeGreaterThan(0);
            expect('estimated' in spent && spent.estimated).toBe(true);
          }
        }

        const entries: RecordEntry[] = [
          {
            type: 'prompt',
            turnId: 'parent',
            prompt: 'spawn the task',
            images: 0,
            at: 0,
          },
        ];

        for (const event of updates) {
          const entry = entryOf(
            { ...event, turnId: 'parent' },
            { type: 'state', options: {} },
          );

          if (entry) {
            entries.push(entry);
          }
        }

        const path = join(dir, 'parent.jsonl');

        await writeFile(
          path,
          entries.map((entry) => JSON.stringify(entry)).join('\n') + '\n',
        );

        const replay = recordActions(await readPast(path))
          .filter((action) => action.type !== 'usage')
          .reduce(reduceTranscript, emptyTranscript);
        const block = replay.entries.find((entry) => entry.kind === 'subagent');

        assert(block?.kind === 'subagent');
        expect(block.subagent.task).toMatchObject({
          name: 'Read the reply',
          runtime: 'fake',
        });
        expect(spent).toEqual(block.subagent.task?.spent);
      } finally {
        await conversation.close();
        await rm(dir, { recursive: true, force: true });
      }
    });
  }

  test('reported zero cost and zero token counts remain present at completion', () => {
    const { task, relayed } = harness();

    task.heard({ type: 'connected', sessionId: 's' });
    task.heard({ type: 'prompt', turnId: 'r', text: 'text', at: 1 });
    task.heard({
      type: 'update',
      turnId: 'r',
      update: {
        sessionUpdate: 'usage_update',
        used: 0,
        size: 1000,
        cost: { amount: 0, currency: 'USD' },
      },
    });
    task.heard({
      type: 'result',
      turnId: 'r',
      result: {
        status: 'completed',
        stopReason: 'end_turn',
        usage: { inputTokens: 0, outputTokens: 0, totalTokens: 0 },
      },
    });
    expect(relayed.at(-1)).toMatchObject({
      update: {
        _meta: {
          'chord/spent': {
            tokens: { inputTokens: 0, outputTokens: 0, totalTokens: 0 },
            cost: { amount: 0, currency: 'USD' },
          },
        },
      },
    });
  });
});
