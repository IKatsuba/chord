import { describe, expect, test } from 'bun:test';
import stringWidth from 'string-width';
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

test('a row that does not fit wraps after a ` · `, inside its title at its spaces where it must, and drops nothing (CHD-473)', () => {
  const timed = agent({
    ...DRAW,
    state: 'completed',
    startedAt: 0,
    endedAt: 28_000,
    entries: [tool('c', 'Read a.ts'), tool('d', 'Read b.ts')],
  });
  const lines = (width: number) =>
    groupRow(timed, width).map((runs) => runs.map(({ text }) => text).join(''));

  // The name bold, the title plain, what follows dim.
  expect(groupRow(timed, 120)).toStrictEqual([
    [
      { text: 'Agent', style: 'bold' },
      { text: `(${DRAW.title!})`, style: 'plain' },
      { text: ' · 2 tool uses · 28s', style: 'dim', counts: true },
    ],
  ]);
  // `Agent(…)` is 66 cells.
  // `Agent(…)` fills 66 cells: the `·` starts the next line.
  expect(lines(66)).toStrictEqual([
    `Agent(${DRAW.title!})`,
    '· 2 tool uses · 28s',
  ]);
  expect(lines(70)).toStrictEqual([
    `Agent(${DRAW.title!}) ·`,
    '2 tool uses · 28s',
  ]);
  expect(lines(30)).toStrictEqual([
    'Agent(Find where tool calls',
    'are drawn on screen and how',
    'they fold) · 2 tool uses · 28s',
  ]);
  // Where even the `·` does not fit after a part, it starts the next line.
  expect(lines(12)).toStrictEqual([
    'Agent(Find',
    'where tool',
    'calls are',
    'drawn on',
    'screen and',
    'how they',
    'fold) ·',
    '2 tool uses',
    '· 28s',
  ]);

  for (const width of [12, 30, 66, 80, 120]) {
    for (const line of lines(width)) {
      expect(line.length, line).toBeLessThanOrEqual(width);
    }
  }

  expect(
    groupRow(agent({ id: 'a' }), 20).map((runs) =>
      runs.map(({ text }) => text).join(''),
    ),
  ).toStrictEqual(['Agent · 0 tool uses']);
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

test("an ended task's group row keeps its tokens, its money and its counts at every width, wrapping where they do not fit (CHD-373, CHD-473)", () => {
  const said = (width: number) =>
    groupRow(SPENT_TASK, width)
      .map((runs) => runs.map(({ text }) => text).join(''))
      .join(' ');

  expect(said(200)).toContain(' · 2 tool uses · 2.0k tokens · $0.0125 · 13s');

  for (let width = 200; width > 10; width--) {
    for (const part of ['2 tool uses', '2.0k tokens', '$0.0125', '13s']) {
      expect(said(width), `${width}`).toContain(part);
    }
  }
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

  test('a shrinking estimated group row wraps without losing its title, model, tokens, money, tool uses or time', () => {
    const task = {
      ...SPENT_TASK,
      task: {
        ...SPENT_TASK.task!,
        model: 'A deliberately long model',
        spent: { ...SPENT_TASK.task!.spent!, estimated: true as const },
      },
    };
    const said = (width: number) =>
      groupRow(task, width)
        .map((runs) => runs.map(({ text }) => text).join(''))
        .join(' ');

    for (let width = 200; width > 10; width--) {
      const text = said(width);

      for (const part of [
        'Agent',
        'fake',
        'A deliberately long model',
        '2.0k tokens',
        '~$0.0125',
        '2 tool uses',
        '13s',
      ]) {
        expect(text.replace(/\s/g, ''), `width ${width}`).toContain(
          part.replace(/\s/g, ''),
        );
      }

      expect(text, `width ${width}`).not.toContain('…');
    }
  });
});

describe('CHD-473 a group row breaks only between whole graphemes, its title and task on lines of their own making', () => {
  const graphemes = (text: string) =>
    [
      ...new Intl.Segmenter(undefined, { granularity: 'grapheme' }).segment(
        text,
      ),
    ].map(({ segment }) => segment);
  const family = '👨‍👩‍👧‍👦';
  const accented = 'é';

  for (const [label, word] of [
    ['a ZWJ family', family.repeat(6)],
    ['combining accents', accented.repeat(12)],
  ] as const) {
    test(`a first word of ${label} wider than the line breaks between whole graphemes, its width kept`, () => {
      const rows = groupRow(agent({ id: 'g', title: word }), 8);
      const texts = rows.map((runs) => runs.map(({ text }) => text).join(''));

      for (const text of texts) {
        expect(stringWidth(text), text).toBeLessThanOrEqual(8);
      }

      // Every grapheme whole, and all of them, in order.
      expect(texts.flatMap(graphemes)).toStrictEqual(graphemes(texts.join('')));
      // Nothing lost or added but the spaces the line breaks stand for.
      expect(texts.join('').replaceAll(' ', '')).toBe(
        `Agent(${word})·0tooluses`,
      );
      // The name bold, the title plain, the counts dim and chord's.
      expect(rows[0]![0]).toStrictEqual({ text: 'Agent', style: 'bold' });
      expect(rows.flat().filter((run) => run.counts === true)).not.toHaveLength(
        0,
      );
      expect(
        rows
          .flat()
          .filter((run) => run.text.includes(word.slice(0, 2)))
          .every((run) => run.style === 'plain' && run.counts === undefined),
      ).toBe(true);
    });
  }

  test("a title's or a task's CR, LF and tabs read as spaces, no run holding a line break", () => {
    const rows = groupRow(
      agent({
        id: 't',
        title: 'Read\nfiles\r\nand\tthe tests',
        task: {
          name: 'Read files',
          runtime: 'fake',
          model: 'fake\nlarge',
        },
      }),
      200,
    );

    expect(
      rows.map((runs) => runs.map(({ text }) => text).join('')),
    ).toStrictEqual([
      'Agent(Read files and the tests) · fake · fake large · 0 tool uses',
    ]);
    expect(rows.flat().some((run) => /[\r\n\t]/.test(run.text))).toBe(false);
  });
});

describe('CHD-473 T2 tester: grapheme and selectable-run boundaries', () => {
  const graphemes = (text: string) =>
    [
      ...new Intl.Segmenter(undefined, { granularity: 'grapheme' }).segment(
        text,
      ),
    ].map(({ segment }) => segment);
  const compact = (text: string) => text.normalize('NFC').replace(/\s/g, '');
  const rich = {
    ...SPENT_TASK,
    title: 'Read\n👩🏽‍💻日本語🇯🇵é1️⃣\r\nfiles\twithout loss',
    task: {
      ...SPENT_TASK.task!,
      model: 'Public\n👨‍👩‍👧‍👦é🇺🇳1️⃣\tmodel',
      spent: { ...SPENT_TASK.task!.spent!, estimated: true as const },
    },
  };

  test('each narrow line and styled run ends at a grapheme boundary, with every visible part retained', () => {
    const canonical = groupRow(rich, 500)
      .flat()
      .map(({ text }) => text)
      .join('');

    for (let width = 2; width <= 80; width++) {
      const rows = groupRow(rich, width);
      const texts = rows.map((runs) => runs.map(({ text }) => text).join(''));

      expect(texts.flatMap(graphemes), `line boundaries at ${width}`).toEqual(
        graphemes(texts.join('')),
      );

      for (const runs of rows) {
        const text = runs.map(({ text }) => text).join('');

        expect(
          stringWidth(text),
          `width ${width}: ${text}`,
        ).toBeLessThanOrEqual(width);
        expect(runs.flatMap(({ text }) => graphemes(text))).toEqual(
          graphemes(text),
        );
        expect(text).not.toMatch(/[\r\n\t]/);
      }

      expect(compact(texts.join(''))).toBe(compact(canonical));
      expect(texts.join('')).not.toContain('…');
      expect(texts.join('')).not.toContain('�');
    }
  });

  test('wrapping never changes which runtime/model runs select or which counts stay dim and unselectable', () => {
    for (const width of [-1, 0, 1, 2, 11, 24, 73, 200]) {
      const rows = groupRow(rich, width);
      const selectable = rows.flat().filter((run) => run.counts !== true);
      const counts = rows.flat().filter((run) => run.counts === true);

      expect(compact(selectable.map(({ text }) => text).join(''))).toBe(
        compact(
          'Agent(Read👩🏽‍💻日本語🇯🇵é1️⃣fileswithoutloss)·fake·Public👨‍👩‍👧‍👦é🇺🇳1️⃣model',
        ),
      );
      expect(compact(counts.map(({ text }) => text).join(''))).toBe(
        '·2tooluses·2.0ktokens·~$0.0125·13s',
      );
      expect(counts.every((run) => run.style === 'dim')).toBe(true);
      expect(rows.flat().every((run) => !/[\r\n\t]/.test(run.text))).toBe(true);
    }
  });
});

test('Guardian reviews leave no subagent counts or approved work/headlines, while in-progress rows stay dim (CHD-521)', () => {
  const review = (guardian: string): Entry => ({
    kind: 'tool',
    turnId: T,
    call: { id: guardian, title: 'Guardian Review', guardian },
  });
  const child = agent({
    id: 'guardian-work',
    entries: [
      tool('read', 'Read file'),
      review('approved'),
      review('inProgress'),
      review('denied'),
    ],
  });

  expect(toolUses(child)).toBe(2);
  expect(
    workOf(child).flatMap((item) =>
      item.kind === 'entry' && item.entry.kind === 'tool'
        ? [item.entry.call.id]
        : [],
    ),
  ).toStrictEqual(['read', 'inProgress', 'denied']);

  const folded = blockFold(child, []);

  expect(folded.kind).toBe('work');

  if (folded.kind === 'work') {
    expect(folded.lines).toHaveLength(3);
    expect(folded.lines[1]).toMatchObject({
      reviewing: true,
      headline: { name: 'Guardian reviewing…' },
    });
  }

  const first = agent({ id: 'first' });
  const second = agent({ id: 'second' });
  const entries = [entry(first), review('approved'), entry(second)];

  expect(agentGroup(entries, 0)).toStrictEqual([first, second]);
  expect(agentGroup(entries, 2)).toStrictEqual([]);
});
