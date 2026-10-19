import { describe, expect, test } from 'bun:test';
import { type Child, idle, type Tab } from '../../../src/session/tabs.ts';
import {
  emptyTranscript,
  type Entry,
} from '../../../src/session/transcript/types.ts';
import { addTurn, type Spent } from '../../../src/session/usage.ts';
import {
  type KeptSpend,
  sessionFigure,
  type SpendPart,
  type SpendSession,
  sum,
  taskFigure,
  tokensIn,
  windowSpend,
} from '../../../src/ui/transcript/spend.ts';

const USD = (amount: number) => ({ amount, currency: 'USD' });

/** A session's spend from `turns`, each its tokens and its own cost. */
function spentOf(
  turns: readonly [
    string,
    Parameters<typeof addTurn>[2],
    Parameters<typeof addTurn>[3]?,
  ][],
): Spent | undefined {
  return turns.reduce<Spent | undefined>(
    (spent, [id, tokens, cost]) => addTurn(spent, id, tokens, cost),
    undefined,
  );
}

test("a session's figure is its whole life: each turn's own cost once, its tokens, and how much of it chord estimated", () => {
  const spent = spentOf([
    // From its record, then this window; the first said again late.
    ['history-a', { totalTokens: 2000 }, { cost: USD(0.0125) }],
    ['b', { totalTokens: 2000 }, { cost: USD(0.02), estimated: true }],
    ['history-a', { totalTokens: 2000 }, { cost: USD(0.0125) }],
  ]);

  expect(sessionFigure(spent)).toStrictEqual({
    cost: { amount: expect.closeTo(0.0325, 9), currency: 'USD' },
    estimated: 'part',
    tokens: 4000,
  });
  expect(
    sessionFigure(spentOf([['a', {}, { cost: USD(0.4), estimated: true }]])),
  ).toStrictEqual({ cost: USD(0.4), estimated: 'all' });
  // Nothing reported: no figure, never a zero.
  expect(sessionFigure(spentOf([['a', {}]]))).toBe(undefined);
  expect(sessionFigure(undefined)).toBe(undefined);
});

test("a turn left uncounted, or in another currency, is said, not added (the owner's Q61)", () => {
  expect(
    sessionFigure(
      spentOf([
        ['a', {}, { cost: USD(0.01) }],
        ['b', {}, { uncounted: true }],
        ['c', {}, { cost: { amount: 1, currency: 'EUR' } }],
      ]),
    ),
  ).toStrictEqual({ cost: USD(0.01), uncounted: 2 });
});

test("an older record's spend before it kept each turn's is in the cost, and said apart, as last reported (the owner's Q62)", () => {
  expect(
    sessionFigure(
      spentOf([
        [
          'history-before',
          {},
          { cost: USD(0.04), before: { until: 1_760_900_000_000 } },
        ],
        ['a', { totalTokens: 10 }, { cost: USD(0.01) }],
      ]),
    ),
  ).toStrictEqual({
    cost: { amount: expect.closeTo(0.05, 9), currency: 'USD' },
    tokens: 10,
    before: { cost: USD(0.04), until: 1_760_900_000_000 },
  });
});

test("a task's figure is what its block keeps", () => {
  expect(
    taskFigure({
      tokens: { inputTokens: 600, outputTokens: 250 },
      cost: USD(0.0125),
      estimated: true,
    }),
  ).toStrictEqual({ cost: USD(0.0125), estimated: 'all', tokens: 850 });
  expect(taskFigure(undefined)).toBe(undefined);
  expect(tokensIn({ totalTokens: 7, inputTokens: 3 })).toBe(7);
});

test('a sum adds what was reported, says how much chord estimated, and names what reported nothing rather than read it as zero', () => {
  const parts: SpendPart[] = [
    {
      name: '1 fake',
      kind: 'tab',
      parts: [
        {
          name: 'main',
          kind: 'main',
          figure: { cost: USD(0.025), tokens: 4000, uncounted: 1 },
        },
        {
          name: 'Fix the tokenizer',
          kind: 'task',
          ended: true,
          figure: { cost: USD(0.0125), tokens: 2000 },
        },
        // At work: its figure comes when it ends, so it is not counted.
        { name: 'Watch the build', kind: 'task', running: true },
        {
          name: 'bugfix',
          kind: 'team',
          parts: [
            { name: 'lead', kind: 'member', figure: { cost: USD(0.025) } },
            { name: 'tester', kind: 'member', figure: { cost: USD(0.0125) } },
          ],
        },
      ],
    },
    {
      name: '2 codex',
      kind: 'tab',
      parts: [
        {
          name: 'main',
          kind: 'main',
          figure: { cost: USD(0.412), estimated: 'all', tokens: 188_400 },
        },
      ],
    },
    {
      name: '3 gemini',
      kind: 'tab',
      parts: [{ name: 'main', kind: 'main', agent: 'gemini' }],
    },
    {
      name: '4 other',
      kind: 'tab',
      parts: [
        {
          name: 'main',
          kind: 'main',
          agent: 'other',
          figure: { cost: { amount: 1, currency: 'EUR' } },
        },
      ],
    },
  ];

  expect(sum(parts)).toStrictEqual({
    cost: expect.closeTo(0.025 + 0.0125 + 0.025 + 0.0125 + 0.412, 9),
    estimated: 'part',
    tokens: 4000 + 2000 + 188_400,
    // A tab or a team run has no figure of its own beside its agents'.
    missing: ['gemini', 'other'],
    uncounted: 1,
  });
  expect(sum([parts[1]!])).toMatchObject({ estimated: 'all' });
  expect(sum([])).toStrictEqual({
    estimated: 'none',
    missing: [],
    uncounted: 0,
  });
});

const child = (
  key: number,
  id: string,
  name: string,
  more: { team?: string; lead?: string } = {},
): Child<string> => ({
  key,
  id,
  name,
  runtime: 'fake',
  colour: key,
  openedAt: 0,
  conversation: name,
  wait: idle,
  ...more,
});

const tab = (
  key: number,
  agent: string,
  children: Child<string>[],
): Tab<string> => ({
  key,
  agent,
  conversation: agent,
  wait: idle,
  children,
  picked: key,
  closed: [],
  opened: children.length,
});

const session = (
  cost: number,
  entries: readonly Entry[] = [],
  sessionId?: string,
): SpendSession => ({
  ...(sessionId === undefined ? {} : { sessionId }),
  spent: spentOf([['t', {}, { cost: USD(cost) }]]),
  transcript: { ...emptyTranscript, entries: [...entries] },
});

const task = (name: string, state: 'running' | 'completed'): Entry => ({
  kind: 'subagent',
  turnId: 't',
  subagent: {
    id: name,
    state,
    entries: [],
    plan: [],
    task: {
      name,
      runtime: 'fake',
      ...(state === 'completed' ? { spent: { cost: USD(0.0125) } } : {}),
    },
  },
});

/** Each part by its name and own cost, with what is under it. */
const shape = (parts: readonly SpendPart[]): unknown =>
  parts.map((part) => [
    part.name,
    part.figure?.cost?.amount,
    ...(part.parts === undefined ? [] : [shape(part.parts)]),
  ]);

test("the window's spend: each tab's own agent and its tasks, its long-lived agents, a team run with its lead and members, and what closed", () => {
  const spend = windowSpend(
    [
      tab(1, 'fake', [
        child(2, 'a', 'docs'),
        child(3, 'l', 'lead', { team: 'bugfix' }),
        child(4, 't', 'tester', { team: 'bugfix', lead: 'l' }),
      ]),
      tab(5, 'codex', []),
    ],
    {
      1: session(0.15, [task('Fix it', 'completed'), task('Watch', 'running')]),
      2: session(0.02),
      3: session(0.025),
      4: session(0.0125),
    },
    [
      {
        tab: 1,
        lead: 'l',
        part: {
          name: 'coder',
          kind: 'member',
          ended: true,
          figure: { cost: USD(0.01) },
        },
      },
      {
        tab: 9,
        tabName: 'gone fake',
        part: {
          name: 'main',
          kind: 'main',
          ended: true,
          figure: { cost: USD(0.03) },
        },
      },
      // A closed run whose lead closed too is one team part of its own.
      {
        tab: 1,
        lead: 'x',
        team: 'review',
        part: { name: 'lead', kind: 'member', figure: { cost: USD(0.002) } },
      },
    ],
  );

  expect(shape(spend)).toStrictEqual([
    [
      '1 fake',
      undefined,
      [
        ['main', 0.15],
        ['Fix it', 0.0125],
        ['Watch', undefined],
        ['docs', 0.02],
        [
          'bugfix',
          undefined,
          [
            ['lead', 0.025],
            ['tester', 0.0125],
            ['coder', 0.01],
          ],
        ],
        ['review', undefined, [['lead', 0.002]]],
      ],
    ],
    ['2 codex', undefined, [['main', undefined]]],
    ['gone fake', undefined, [['main', 0.03]]],
  ]);
  // The codex tab reported nothing; the running task is not yet counted.
  expect(sum(spend)).toMatchObject({
    cost: expect.closeTo(
      0.15 + 0.0125 + 0.02 + 0.025 + 0.0125 + 0.01 + 0.002 + 0.03,
      9,
    ),
    missing: ['codex'],
  });
});

test('a closed session counts once: not where it closed while it is open again, and where it closed last', () => {
  const closed = (amount: number, tabName: string): KeptSpend => ({
    sessionId: 's1',
    tab: 9,
    tabName,
    part: {
      name: 'main',
      kind: 'main',
      ended: true,
      figure: { cost: USD(amount) },
    },
  });
  const kept = [closed(0.01, 'first'), closed(0.03, 'again')];

  // Resumed in tab 1, its whole spend is there.
  expect(
    shape(
      windowSpend([tab(1, 'fake', [])], { 1: session(0.05, [], 's1') }, kept),
    ),
  ).toStrictEqual([['1 fake', undefined, [['main', 0.05]]]]);
  // Closed twice, the last close holds its whole spend.
  expect(shape(windowSpend([], {}, kept))).toStrictEqual([
    ['again', undefined, [['main', 0.03]]],
  ]);
});

test("a session's tokens are each turn's in all, added: a turn that gave only its kinds counts beside one that gave a total, an explicit zero as zero", () => {
  expect(
    sessionFigure(
      spentOf([
        ['a', { totalTokens: 2000 }],
        ['b', { inputTokens: 1000, outputTokens: 200 }],
        ['c', { totalTokens: 0, inputTokens: 50 }],
      ]),
    ),
  ).toStrictEqual({ tokens: 3200 });
  expect(sessionFigure(spentOf([['a', { totalTokens: 0 }]]))).toStrictEqual({
    tokens: 0,
  });
});

describe('CHD-373 S3b tester: retained session identity and partial figures', () => {
  test('same-named closed agents with distinct sessions both count, and a resumed session supersedes all older snapshots', () => {
    const kept: KeptSpend[] = [
      {
        sessionId: 'one',
        tab: 9,
        part: { name: 'parser', kind: 'agent', figure: { cost: USD(0.01) } },
      },
      {
        sessionId: 'two',
        tab: 9,
        part: { name: 'parser', kind: 'agent', figure: { cost: USD(0.02) } },
      },
      {
        sessionId: 'one',
        tab: 10,
        part: { name: 'parser', kind: 'agent', figure: { cost: USD(0.03) } },
      },
    ];

    expect(sum(windowSpend([], {}, kept)).cost).toBeCloseTo(0.05, 9);

    const live = windowSpend(
      [tab(1, 'fake', [])],
      { 1: session(0.04, [], 'one') },
      kept,
    );

    expect(sum(live).cost).toBeCloseTo(0.06, 9);
    expect(shape(live)).toEqual([
      ['1 fake', undefined, [['main', 0.04]]],
      ['closed tab', undefined, [['parser', 0.02]]],
    ]);
  });

  test('a zero estimate remains reported while missing and non-USD sessions remain unreported, with mixed token formats counted per turn', () => {
    const sessions = {
      1: {
        transcript: emptyTranscript,
        spent: spentOf([
          ['one', { totalTokens: 10 }, { cost: USD(0), estimated: true }],
          ['two', { inputTokens: 2, outputTokens: 3 }, { uncounted: true }],
          [
            'one',
            { totalTokens: 0, inputTokens: 99 },
            { cost: USD(0), estimated: true },
          ],
        ]),
      },
      2: {
        transcript: emptyTranscript,
        spent: spentOf([
          ['euro', {}, { cost: { amount: 2, currency: 'EUR' } }],
        ]),
      },
    };
    const parts = windowSpend(
      [tab(1, 'fake', []), tab(2, 'other', []), tab(3, 'silent', [])],
      sessions,
      [],
    );

    expect(sum(parts)).toEqual({
      cost: 0,
      estimated: 'all',
      tokens: 5,
      uncounted: 2,
      missing: ['other', 'silent'],
    });
  });
});
