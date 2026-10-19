import { describe, expect, test } from 'bun:test';
import type {
  Entry,
  PermissionWait,
  Subagent,
  ToolCall,
} from '../../../../src/session/transcript/types.ts';
import {
  agentGroup,
  agentTone,
  askerRow,
  blockFold,
  endedLine,
  endNote,
  groupHeader,
  groupRow,
  rowLine,
  stillRunning,
  toolUses,
  workOf,
} from '../../../../src/ui/transcript/agents/subagents.ts';

const T = 't1';

function tool(id: string, title: string, status?: ToolCall['status']): Entry {
  return {
    kind: 'tool',
    turnId: T,
    call: { id, title, ...(status === undefined ? {} : { status }) },
  };
}

function agent(fields: Partial<Subagent> & { id: string }): Subagent {
  return { state: 'running', entries: [], plan: [], ...fields };
}

function entry(subagent: Subagent): Entry {
  return { kind: 'subagent', turnId: T, subagent };
}

function say(text: string): Entry {
  return { kind: 'assistant', turnId: T, text };
}

const FIND = agent({
  id: 'a1',
  title: 'Find the session layer',
  description: 'Find where chord hands each session/update to its listeners.',
  entries: [
    tool('c1', 'Search sessionUpdate in src', 'completed'),
    say('Looking.'),
    tool('c2', 'Read src/acp/connection.ts', 'completed'),
    entry(agent({ id: 'a3', title: 'Read the transport tests' })),
    tool('c3', 'Read src/session/session.ts', 'failed'),
    tool('c4', 'Write notes/routing.md', 'pending'),
  ],
});

const DRAW = agent({
  id: 'a2',
  title: 'Find where tool calls are drawn on screen and how they fold',
});

test('subagents spawned back to back are one group, drawn from the first', () => {
  const entries = [
    say('Two agents.'),
    entry(FIND),
    entry(DRAW),
    say('And one more.'),
    entry(DRAW),
  ];

  expect(agentGroup(entries, 0)).toStrictEqual(undefined);
  expect(agentGroup(entries, 1)).toStrictEqual([FIND, DRAW]);
  expect(agentGroup(entries, 2)).toStrictEqual([]);
  expect(agentGroup(entries, 4)).toStrictEqual([DRAW]);
});

test('a running block shows its latest three calls and counts the rest', () => {
  expect(blockFold(FIND, [])).toStrictEqual({
    kind: 'work',
    lines: [
      {
        headline: { name: 'Agent', arg: 'Read the transport tests' },
        failed: false,
        waiting: false,
      },
      {
        headline: { name: 'Read', arg: 'src/session/session.ts' },
        failed: true,
        waiting: false,
      },
      {
        headline: { name: 'Write', arg: 'notes/routing.md' },
        failed: false,
        waiting: false,
      },
    ],
    more: 2,
  });
  // Its words are not a tool use; its own subagent is one.
  expect(toolUses(FIND)).toStrictEqual(5);
});

test('a block with no call yet is starting, whatever it has said', () => {
  expect(
    blockFold(agent({ id: 'a', entries: [say('Thinking aloud.')] }), []),
  ).toStrictEqual({ kind: 'starting' });
  expect(rowLine(agent({ id: 'a' }), [])).toStrictEqual({ kind: 'starting' });
});

test('an ended block says how, with its tool uses and time', () => {
  const ended = (state: Subagent['state'], endedAt?: number) =>
    blockFold(
      agent({
        id: 'a',
        state,
        startedAt: 1_000,
        ...(endedAt === undefined ? {} : { endedAt }),
        entries: [tool('c', 'Read a.ts', 'completed')],
      }),
      [],
    );

  expect(ended('completed', 42_500)).toStrictEqual({
    kind: 'ended',
    text: 'Done (1 tool use · 41s)',
    failed: false,
  });
  expect(ended('failed', 126_000)).toStrictEqual({
    kind: 'ended',
    text: 'Failed (1 tool use · 2m 5s)',
    failed: true,
  });
  // A past that kept no time has none, rather than one made up.
  expect(ended('cancelled')).toStrictEqual({
    kind: 'ended',
    text: 'Cancelled (1 tool use)',
    failed: false,
  });
  expect(ended('disconnected')?.kind).toStrictEqual('ended');
  expect(endedLine(FIND)).toStrictEqual(undefined);
});

test('the marker takes a call tone: dim for cancelled, error for failed and disconnected', () => {
  expect(agentTone('running')).toStrictEqual('running');
  expect(agentTone('completed')).toStrictEqual('done');
  expect(agentTone('failed')).toStrictEqual('failed');
  expect(agentTone('disconnected')).toStrictEqual('failed');
  expect(agentTone('cancelled')).toStrictEqual('pending');
});

test("an end that claims no cause, or that the agent lost sight of, reads as such, dim, with a line in ctrl+o's view", () => {
  const of = (state: Subagent['state'], error?: string) =>
    agent({ id: 'a', state, ...(error === undefined ? {} : { error }) });

  expect(blockFold(of('ended'), [])).toStrictEqual({
    kind: 'ended',
    text: 'Ended (0 tool uses)',
    failed: false,
  });
  expect(blockFold(of('untracked'), [])).toStrictEqual({
    kind: 'ended',
    text: 'Untracked (0 tool uses)',
    failed: false,
  });
  expect(agentTone('ended')).toStrictEqual('pending');
  expect(agentTone('untracked')).toStrictEqual('pending');
  expect(endNote(of('untracked'))).toStrictEqual({
    text: 'The agent no longer reports this subagent; it may still be at work.',
    failed: false,
  });
  expect(endNote(of('ended'))).toStrictEqual({
    text: 'The agent did not say how it ended.',
    failed: false,
  });
  expect(endNote(of('failed', 'API Error: 529 Overloaded'))).toStrictEqual({
    text: 'API Error: 529 Overloaded',
    failed: true,
  });

  for (const state of ['completed', 'cancelled', 'failed'] as const) {
    expect(endNote(of(state))).toStrictEqual(undefined);
  }
});

test('the call a permission waits on is marked, and is the row line ahead of any later', () => {
  const wait: PermissionWait = {
    id: 'p',
    subagentId: 'a1',
    toolCallId: 'c2',
    options: [],
  };
  const line = rowLine(FIND, [wait]);

  expect(line).toStrictEqual({
    kind: 'call',
    line: {
      headline: { name: 'Read', arg: 'src/acp/connection.ts' },
      failed: false,
      waiting: true,
    },
  });
  // Another subagent's request for a call of the same id is not this one's.
  expect(rowLine(FIND, [{ ...wait, subagentId: 'a2' }])).toStrictEqual({
    kind: 'call',
    line: {
      headline: { name: 'Write', arg: 'notes/routing.md' },
      failed: false,
      waiting: false,
    },
  });
  expect(rowLine(agent({ ...FIND, state: 'failed' }), [wait])).toStrictEqual({
    kind: 'ended',
    ending: { word: 'Failed', failed: true },
  });
});

test('the group header runs, then finishes, or says what went wrong', () => {
  const done = agent({ id: 'x', state: 'completed' });

  expect(groupHeader([FIND, done])).toStrictEqual({
    text: 'Running 2 agents…',
    tone: 'running',
  });
  expect(groupHeader([done, done, done])).toStrictEqual({
    text: '3 agents finished',
    tone: 'done',
  });
  expect(
    groupHeader([
      agent({ id: 'x', state: 'cancelled' }),
      agent({ id: 'y', state: 'failed' }),
    ]),
  ).toStrictEqual({
    text: '2 agents ended · 1 failed, 1 cancelled',
    tone: 'failed',
  });
  expect(
    groupHeader([done, agent({ id: 'y', state: 'cancelled' })]),
  ).toStrictEqual({
    text: '2 agents ended · 1 cancelled',
    tone: 'pending',
  });
  expect(
    groupHeader([done, agent({ id: 'y', state: 'disconnected' })]).text,
  ).toStrictEqual('2 agents ended · 1 disconnected');
  // Worst first; red only for a failure or a lost agent.
  expect(
    groupHeader([
      agent({ id: 'v', state: 'cancelled' }),
      agent({ id: 'w', state: 'ended' }),
      agent({ id: 'x', state: 'untracked' }),
      agent({ id: 'y', state: 'disconnected' }),
      agent({ id: 'z', state: 'failed' }),
    ]).text,
  ).toStrictEqual(
    '5 agents ended · 1 failed, 1 disconnected, 1 untracked, 1 ended, 1 cancelled',
  );
  expect(
    groupHeader([
      done,
      agent({ id: 'x', state: 'untracked' }),
      agent({ id: 'y', state: 'ended' }),
    ]),
  ).toStrictEqual({
    text: '3 agents ended · 1 untracked, 1 ended',
    tone: 'pending',
  });
});

test('a row drops its counts before its title is cut, and keeps its brackets', () => {
  const timed = agent({
    ...DRAW,
    state: 'completed',
    startedAt: 0,
    endedAt: 28_000,
    entries: [tool('c', 'Read a.ts'), tool('d', 'Read b.ts')],
  });
  const title = { name: 'Agent', arg: DRAW.title! };

  expect(groupRow(timed, 120)).toStrictEqual({
    headline: title,
    counts: ' · 2 tool uses · 28s',
  });
  // `Agent(…)` is 66 cells; the counts need 20 more.
  expect(groupRow(timed, 80)).toStrictEqual({ headline: title });
  expect(groupRow(timed, 66)).toStrictEqual({ headline: title });
  expect(groupRow(timed, 30)).toStrictEqual({
    headline: { name: 'Agent', arg: 'Find where tool calls…' },
  });
  expect(groupRow(agent({ id: 'a' }), 20)).toStrictEqual({
    headline: { name: 'Agent' },
    counts: ' · 0 tool uses',
  });
});

test("a child's permission names the way down to it, whole, however long", () => {
  const child = agent({ id: 'a1', title: 'Find the session layer' });
  const grandchild = agent({ id: 'a3', title: 'Read the transport tests' });
  const text = (pieces: ReturnType<typeof askerRow>) =>
    pieces.map((piece) => piece.text).join('');

  expect(askerRow([])).toStrictEqual([]);
  expect(askerRow([child])).toStrictEqual([
    { text: 'Agent', bold: true },
    { text: '(Find the session layer)', bold: false },
    { text: ' asks', bold: false },
  ]);
  expect(text(askerRow([child, grandchild]))).toStrictEqual(
    'Agent(Find the session layer) › Agent(Read the transport tests) asks',
  );
});

test("a subagent's work keeps its plan where it first came, and groups its own subagents", () => {
  const plan = [
    {
      content: 'Find the transport',
      priority: 'medium',
      status: 'completed',
    },
  ] as const;
  const work = workOf(
    agent({
      id: 'a',
      entries: [
        tool('c1', 'Read a.ts'),
        entry(agent({ id: 'g1' })),
        entry(agent({ id: 'g2' })),
        tool('c2', 'Read b.ts'),
      ],
      plan,
      planAt: 3,
    }),
  );

  expect(work.map((item) => item.kind)).toStrictEqual([
    'entry',
    'agents',
    'plan',
    'entry',
  ]);
  expect(
    workOf(
      agent({ id: 'a', entries: [tool('c', 'Read')], plan, planAt: 1 }),
    ).map((item) => item.kind),
  ).toStrictEqual(['entry', 'plan']);
  expect(
    workOf(agent({ id: 'a', entries: [tool('c', 'Read')] })).length,
  ).toStrictEqual(1);
});

test('a plan that came between two spawns splits them, and shows its latest state there', () => {
  const later = [
    {
      content: 'Find the transport',
      priority: 'medium',
      status: 'completed',
    },
    { content: 'Read its tests', priority: 'medium', status: 'in_progress' },
  ] as const;
  const work = workOf(
    agent({
      id: 'a',
      entries: [entry(agent({ id: 'g1' })), entry(agent({ id: 'g2' }))],
      plan: later,
      planAt: 1,
    }),
  );

  expect(work.map((item) => item.kind)).toStrictEqual([
    'agents',
    'plan',
    'agents',
  ]);
  expect(
    work.map((item) =>
      item.kind === 'agents' ? item.agents.map(({ id }) => id) : item.kind,
    ),
  ).toStrictEqual([['g1'], 'plan', ['g2']]);
  expect(work[1]).toStrictEqual({ kind: 'plan', entries: later });
});

test('the status line counts the subagents still at work', () => {
  expect(stillRunning(0)).toStrictEqual(undefined);
  expect(stillRunning(1)).toStrictEqual('1 agent still running');
  expect(stillRunning(2)).toStrictEqual('2 agents still running');
});

const SPENT_TASK = agent({
  id: 'task-1',
  state: 'completed',
  startedAt: 0,
  endedAt: 13_000,
  entries: [
    tool('c1', 'Read a', 'completed'),
    tool('c2', 'Read b', 'completed'),
  ],
  task: {
    name: 'Fix the tokenizer',
    runtime: 'fake',
    spent: {
      tokens: { inputTokens: 1000, outputTokens: 200, totalTokens: 2000 },
      cost: { amount: 0.0125, currency: 'USD' },
    },
  },
});

test("an ended task's block says its tokens and money between its tool uses and its time, as Claude Code's does with money added (CHD-373)", () => {
  expect(blockFold(SPENT_TASK, [])).toStrictEqual({
    kind: 'ended',
    text: 'Done (2 tool uses · 2.0k tokens · $0.0125 · 13s)',
    failed: false,
  });

  const spent = SPENT_TASK.task!.spent!;
  const said = (task: NonNullable<Subagent['task']>) =>
    blockFold({ ...SPENT_TASK, task }, []).kind === 'ended'
      ? (blockFold({ ...SPENT_TASK, task }, []) as { text: string }).text
      : '';

  // chord's estimate is marked.
  expect(
    said({ ...SPENT_TASK.task!, spent: { ...spent, estimated: true } }),
  ).toBe('Done (2 tool uses · 2.0k tokens · ~$0.0125 · 13s)');
  // What was not reported is left out; tokens with no total are added up.
  expect(
    said({
      ...SPENT_TASK.task!,
      spent: { tokens: { inputTokens: 600, outputTokens: 250 } },
    }),
  ).toBe('Done (2 tool uses · 850 tokens · 13s)');
  expect(said({ name: 'Fix the tokenizer', runtime: 'fake' })).toBe(
    'Done (2 tool uses · 13s)',
  );
  expect(
    said({
      ...SPENT_TASK.task!,
      spent: { tokens: { totalTokens: 1_234_567 } },
    }),
  ).toBe('Done (2 tool uses · 1.2M tokens · 13s)');
});

test("an ended task's group row gives its tokens way first, then its money, then the rest of its counts (CHD-373)", () => {
  const counts = (width: number) => groupRow(SPENT_TASK, width).counts;

  expect(counts(200)).toBe(' · 2 tool uses · 2.0k tokens · $0.0125 · 13s');

  // Narrower and narrower: the tokens go first, then the money, then the
  // rest of the counts.
  const seen: (string | undefined)[] = [];

  for (let width = 200; width > 0; width--) {
    const now = counts(width);

    if (now !== seen.at(-1)) {
      seen.push(now);
    }
  }

  expect(seen).toStrictEqual([
    ' · 2 tool uses · 2.0k tokens · $0.0125 · 13s',
    ' · 2 tool uses · $0.0125 · 13s',
    ' · 2 tool uses · 13s',
    undefined,
  ]);
});

describe('CHD-373 S2 tester: spend boundaries and group priorities', () => {
  test('reported zero totals win over component counts, and zero estimated money remains visible', () => {
    const ended = blockFold(
      {
        ...SPENT_TASK,
        task: {
          ...SPENT_TASK.task!,
          spent: {
            tokens: { totalTokens: 0, inputTokens: 100 },
            cost: { amount: 0, currency: 'USD' },
            estimated: true,
          },
        },
      },
      [],
    );

    expect(ended).toMatchObject({
      kind: 'ended',
      text: 'Done (2 tool uses · 0 tokens · ~$0.0000 · 13s)',
    });
  });

  test('fallback token count includes every reported kind without inventing absent spend', () => {
    expect(
      blockFold(
        {
          ...SPENT_TASK,
          task: {
            ...SPENT_TASK.task!,
            spent: {
              tokens: {
                inputTokens: 10,
                outputTokens: 20,
                cachedReadTokens: 30,
                cachedWriteTokens: 40,
                thoughtTokens: 50,
              },
            },
          },
        },
        [],
      ),
    ).toMatchObject({ text: 'Done (2 tool uses · 150 tokens · 13s)' });
    expect(
      blockFold(
        { ...SPENT_TASK, task: { name: 'No usage', runtime: 'fake' } },
        [],
      ),
    ).toMatchObject({ text: 'Done (2 tool uses · 13s)' });
  });

  test('a shrinking estimated group row drops its model, tokens, money, then counts in that order', () => {
    const task = {
      ...SPENT_TASK,
      task: {
        ...SPENT_TASK.task!,
        model: 'A deliberately long model',
        spent: { ...SPENT_TASK.task!.spent!, estimated: true as const },
      },
    };
    const rows = Array.from({ length: 199 }, (_, index) =>
      groupRow(task, 200 - index),
    );
    const lostModel = rows.findIndex(
      (row) => !row.headline.note?.includes('A deliberately long model'),
    );
    const lostTokens = rows.findIndex((row) => !row.counts?.includes('tokens'));
    const lostMoney = rows.findIndex((row) => !row.counts?.includes('~$'));
    const lostCounts = rows.findIndex((row) => row.counts === undefined);

    expect(lostModel).toBeGreaterThan(0);
    expect(lostModel).toBeLessThan(lostTokens);
    expect(lostTokens).toBeLessThan(lostMoney);
    expect(lostMoney).toBeLessThan(lostCounts);
  });
});
