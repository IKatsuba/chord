import { expect, test } from 'bun:test';
import type { SpendPart } from '../../../src/ui/transcript/spend.ts';
import {
  manySessions,
  spendTable,
} from '../../../src/ui/transcript/spend_table.ts';

const USD = (amount: number) => ({ amount, currency: 'USD' });

/** The table's lines as text. */
const lines = (parts: readonly SpendPart[], width: number) =>
  spendTable(parts, width).map((row) => row.text);

/** CHD-378's C mock: a tab with a task and a team run, and one with main. */
const WINDOW: SpendPart[] = [
  {
    name: '1 fake',
    kind: 'tab',
    parts: [
      {
        name: 'main',
        kind: 'main',
        agent: 'fake',
        figure: { cost: USD(0.025), tokens: 4000 },
      },
      {
        name: 'Fix the tokenizer',
        kind: 'task',
        ended: true,
        figure: { cost: USD(0.0125), tokens: 2000 },
      },
      {
        name: 'bugfix',
        kind: 'team',
        parts: [
          {
            name: 'lead',
            kind: 'member',
            figure: { cost: USD(0.025), tokens: 4000 },
          },
          {
            name: 'tester',
            kind: 'member',
            figure: { cost: USD(0.0125), tokens: 2000 },
          },
          {
            name: 'coder',
            kind: 'member',
            figure: { cost: USD(0.0125), tokens: 2000 },
          },
        ],
      },
    ],
  },
  {
    name: '2 fake',
    kind: 'tab',
    parts: [
      {
        name: 'main',
        kind: 'main',
        agent: 'fake',
        figure: { cost: USD(0.0125), tokens: 2000 },
      },
    ],
  },
];

test("the window's table at 120 columns reads as CHD-378's mock: each tab with its subtotal, a tab of main alone one row, a team run's members named", () => {
  expect(lines(WINDOW, 114)).toStrictEqual([
    'This window             Cost  Tokens',
    '1 fake               $0.0875  14,000',
    '  main               $0.0250   4,000',
    '  Fix the tokenizer  $0.0125   2,000  task agent, ended',
    '  bugfix             $0.0500   8,000  team run: lead $0.0250 · tester $0.0125 · coder $0.0125',
    '2 fake               $0.0125   2,000',
    'Total                $0.1000  16,000',
  ]);
});

test('at 80 columns a note that would not fit takes its short form', () => {
  expect(lines(WINDOW, 74)).toContain(
    '  bugfix             $0.0500   8,000  team run of 3',
  );
  expect(lines(WINDOW, 74)).toContain(
    '  Fix the tokenizer  $0.0125   2,000  task agent, ended',
  );
});

test('an estimate says whose prices, a figure nobody reported says so, and the total gathers both', () => {
  const mixed: SpendPart[] = [
    {
      name: '1 fake',
      kind: 'tab',
      parts: [
        {
          name: 'main',
          kind: 'main',
          agent: 'fake',
          figure: { cost: USD(0.025), tokens: 4000 },
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
          agent: 'codex',
          figure: {
            cost: USD(0.412),
            estimated: 'all',
            models: ['gpt-5.3-codex'],
            tokens: 188_400,
          },
        },
      ],
    },
    {
      name: '3 gemini',
      kind: 'tab',
      parts: [{ name: 'main', kind: 'main', agent: 'gemini' }],
    },
  ];

  expect(lines(mixed, 114)).toStrictEqual([
    'This window          Cost   Tokens',
    '1 fake            $0.0250    4,000',
    "2 codex          ~$0.4120  188,400  chord's estimate from gpt-5.3-codex's price",
    '3 gemini     not reported        —',
    "Total            ~$0.4370  192,400  part chord's estimate; gemini not reported",
  ]);
  expect(lines(mixed, 50).at(-1)).toBe(
    'Total            ~$0.4370  192,400  part estimate; 1 not reported',
  );
});

test('closed agents and tabs, sessions /clear let go, a running task, an older sum and turns left out each say so', () => {
  const window: SpendPart[] = [
    {
      name: '1 fake',
      kind: 'tab',
      parts: [
        {
          name: 'main',
          kind: 'main',
          agent: 'fake',
          figure: { cost: USD(0.01) },
        },
        { name: 'Watch the build', kind: 'task', running: true },
        {
          name: 'docs',
          kind: 'agent',
          ended: true,
          figure: {
            cost: USD(0.02),
            before: { cost: USD(0.015), until: Date.UTC(2026, 9, 12, 12) },
            uncounted: 1,
          },
        },
        {
          name: 'main',
          kind: 'main',
          ended: true,
          figure: { cost: USD(0.005) },
        },
        {
          name: 'main',
          kind: 'main',
          ended: true,
          figure: { cost: USD(0.005) },
        },
      ],
    },
    {
      name: '3 fake',
      kind: 'tab',
      ended: true,
      parts: [
        {
          name: 'main',
          kind: 'main',
          ended: true,
          figure: { cost: USD(0.03) },
        },
      ],
    },
  ];

  expect(lines(window, 114)).toStrictEqual([
    'This window           Cost  Tokens',
    '1 fake             $0.0400       —',
    '  main             $0.0100       —',
    '  before /clear    $0.0100       —  2 sessions',
    '  Watch the build        —       —  task agent, running: counted when it ends',
    '  docs             $0.0200       —  agent, closed; as last reported before Oct 12; 1 turn not counted',
    '3 fake             $0.0300       —  closed',
    'Total              $0.0700       —  part as last reported; 1 turn not counted; 1 running',
  ]);
});

test('the table is for a window of more than one session, a task or a closed one counted', () => {
  const main: SpendPart = { name: 'main', kind: 'main', agent: 'fake' };

  expect(manySessions([{ name: '1 fake', kind: 'tab', parts: [main] }])).toBe(
    false,
  );
  expect(
    manySessions([
      {
        name: '1 fake',
        kind: 'tab',
        parts: [main, { name: 'Fix it', kind: 'task', running: true }],
      },
    ]),
  ).toBe(true);
  expect(
    manySessions([
      { name: '1 fake', kind: 'tab', parts: [main] },
      {
        name: '2 fake',
        kind: 'tab',
        ended: true,
        parts: [{ ...main, ended: true }],
      },
    ]),
  ).toBe(true);
});
