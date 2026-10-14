import { expect, test } from 'bun:test';
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

test("a child's permission names the way down to it, cut from the left", () => {
  const child = agent({ id: 'a1', title: 'Find the session layer' });
  const grandchild = agent({ id: 'a3', title: 'Read the transport tests' });
  const text = (pieces: ReturnType<typeof askerRow>) =>
    pieces.map((piece) => piece.text).join('');

  expect(askerRow([], 80)).toStrictEqual([]);
  expect(askerRow([child], 80)).toStrictEqual([
    { text: 'Agent', bold: true },
    { text: '(Find the session layer)', bold: false },
    { text: ' asks', bold: false },
  ]);
  expect(text(askerRow([child, grandchild], 80))).toStrictEqual(
    'Agent(Find the session layer) › Agent(Read the transport tests) asks',
  );

  const cut = askerRow([child, grandchild], 40);

  expect(text(cut)).toStrictEqual('… › Agent(Read the transport tests) asks');
  expect(cut.find((piece) => piece.bold)?.text).toStrictEqual('Agent');
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
