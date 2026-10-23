import { describe, expect, test } from 'bun:test';
import stringWidth from 'string-width';
import { costReport } from '../../../src/ui/transcript/reports.ts';
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

test('at 80 columns a note that does not fit wraps in its cell after a ` · `, under its first letter, no word dropped (CHD-473)', () => {
  expect(lines(WINDOW, 72)).toStrictEqual([
    'This window             Cost  Tokens',
    '1 fake               $0.0875  14,000',
    '  main               $0.0250   4,000',
    '  Fix the tokenizer  $0.0125   2,000  task agent, ended',
    '  bugfix             $0.0500   8,000  team run: lead $0.0250 ·',
    '                                      tester $0.0125 · coder $0.0125',
    '2 fake               $0.0125   2,000',
    'Total                $0.1000  16,000',
  ]);
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
  // Narrow, a note left fewer than 20 cells beside the figures goes below
  // them, from the cost column on the row's second line (CHD-473).
  expect(lines(mixed, 50)).toStrictEqual([
    'This window          Cost   Tokens',
    '1 fake            $0.0250    4,000',
    '2 codex          ~$0.4120  188,400',
    "             chord's estimate from gpt-5.3-codex's",
    '             price',
    '3 gemini     not reported        —',
    'Total            ~$0.4370  192,400',
    "             part chord's estimate;",
    '             gemini not reported',
  ]);
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

test("the Total says chord's estimate when all of it is, and part only when some is not", () => {
  const estimated = (name: string): SpendPart => ({
    name,
    kind: 'tab',
    parts: [
      {
        name: 'main',
        kind: 'main',
        agent: 'codex',
        figure: { cost: USD(0.0047), estimated: 'all', tokens: 2000 },
      },
    ],
  });

  expect(lines([estimated('1 fake'), estimated('2 fake')], 114).at(-1)).toBe(
    "Total        ~$0.0094   4,000  chord's estimate",
  );
});

test("each task sits under the session that started it, a closed agent's too, every row its own spend and only a tab's row its subtotal", () => {
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
          parts: [
            {
              name: 'Fix it',
              kind: 'task',
              ended: true,
              figure: { cost: USD(0.005) },
            },
          ],
        },
        {
          name: 'docs',
          kind: 'agent',
          ended: true,
          figure: { cost: USD(0.02) },
          parts: [
            {
              name: 'Index',
              kind: 'task',
              ended: true,
              figure: { cost: USD(0.03) },
            },
          ],
        },
        {
          name: 'bugfix',
          kind: 'team',
          parts: [
            { name: 'lead', kind: 'member', figure: { cost: USD(0.025) } },
            {
              name: 'tester',
              kind: 'member',
              figure: { cost: USD(0.0125) },
              parts: [
                {
                  name: 'Run it',
                  kind: 'task',
                  ended: true,
                  figure: { cost: USD(0.001) },
                },
              ],
            },
          ],
        },
      ],
    },
  ];

  expect(lines(window, 112)).toStrictEqual([
    'This window     Cost  Tokens',
    '1 fake       $0.1035       —',
    '  main       $0.0100       —',
    '    Fix it   $0.0050       —  task agent, ended',
    '  docs       $0.0200       —  agent, closed',
    '    Index    $0.0300       —  task agent, ended',
    '  bugfix     $0.0375       —  team run: lead $0.0250 · tester $0.0125',
    '    Run it   $0.0010       —  task agent of tester, ended',
    'Total        $0.1035       —',
  ]);
});

test('no row is wider than the table and nothing is cut: a long name wraps in a third of it by display width, CJK never split, and notes wrap between their parts (CHD-473)', () => {
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
        {
          name: 'Rewrite the tokenizer as a single pass over the source that reads every token once',
          kind: 'task',
          ended: true,
          figure: { cost: USD(0.0125), tokens: 2000 },
        },
        {
          name: '日本語のエージェントの名前',
          kind: 'agent',
          figure: { cost: USD(0.002) },
        },
        { name: '🧪 tester', kind: 'agent' },
        {
          name: 'docs',
          kind: 'agent',
          ended: true,
          figure: {
            cost: USD(0.02),
            estimated: 'part',
            before: { cost: USD(0.015), until: Date.UTC(2026, 9, 12, 12) },
            uncounted: 2,
          },
        },
      ],
    },
    {
      name: '2 gemini',
      kind: 'tab',
      parts: [{ name: 'main', kind: 'main', agent: 'gemini' }],
    },
  ];

  for (const width of [72, 112]) {
    const drawn = lines(window, width);

    for (const line of drawn) {
      expect(stringWidth(line), line).toBeLessThanOrEqual(width);
    }

    expect(drawn.some((line) => line.includes('…'))).toBe(false);
  }

  expect(lines(window, 72)).toStrictEqual([
    'This window                       Cost  Tokens',
    '1 fake                        ~$0.0445   2,000',
    '  main                         $0.0100       —',
    // A third of 72, the indent counted: the name column is 24 cells, and
    // the name's next lines start under its first letter.
    '  Rewrite the tokenizer        $0.0125   2,000  task agent, ended',
    '  as a single pass over',
    '  the source that reads',
    '  every token once',
    // Two cells a character: whole ones on each line, never half of one.
    '  日本語のエージェントの       $0.0020       —  agent',
    '  名前',
    '  🧪 tester               not reported       —  agent',
    // Each part whole on a line, but one wider than the cell.
    '  docs                        ~$0.0200       —  agent, closed;',
    "                                                part chord's estimate;",
    '                                                as last reported before',
    '                                                Oct 12;',
    '                                                2 turns not counted',
    '2 gemini                  not reported       —',
    "Total                         ~$0.0445   2,000  part chord's estimate;",
    '                                                part as last reported;',
    '                                                2 turns not counted;',
    '                                                🧪 tester not reported;',
    '                                                gemini not reported',
  ]);
});

test('a session that reported nothing but a turn left out still says that turn', () => {
  expect(
    text(
      costReport({
        agent: 'fake',
        cwd: '/work',
        now: 1,
        modes: [],
        spent: { turns: {}, costs: { a: { uncounted: true } } },
      }),
    ),
  ).toStrictEqual([
    'Total cost:  not reported by fake',
    'Not counted: 1 turn',
    'Tokens:      not reported by fake',
  ]);
});

const text = (rows: readonly { label?: string; text: string }[]) =>
  rows.map(({ label, text }) => `${label ?? ''}${text}`);

test("a name over several lines, a task's, an agent's or a run member's, stays on its row", () => {
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
          parts: [
            {
              name: 'Read\ntests',
              kind: 'task',
              ended: true,
              figure: { cost: USD(0.001) },
            },
          ],
        },
        { name: 'docs\r\nwriter', kind: 'agent', figure: { cost: USD(0.002) } },
        {
          name: 'bug\nfix',
          kind: 'team',
          parts: [
            { name: 'lead', kind: 'member', figure: { cost: USD(0.003) } },
            {
              name: 'test\ner',
              kind: 'member',
              figure: { cost: USD(0.004) },
              parts: [{ name: 'Run\n\tit', kind: 'task', running: true }],
            },
          ],
        },
      ],
    },
  ];

  for (const width of [72, 112]) {
    const drawn = lines(window, width);

    for (const line of drawn) {
      expect(line, line).not.toMatch(/[\r\n]/);
      expect(stringWidth(line), line).toBeLessThanOrEqual(width);
    }
  }

  const at112 = lines(window, 112);

  expect(at112).toContain('    Read tests  $0.0010       —  task agent, ended');
  expect(
    at112.some((line) =>
      line.includes('team run: lead $0.0030 · test er $0.0040'),
    ),
  ).toBe(true);
  expect(
    at112.some(
      (line) =>
        line.includes('Run it') &&
        line.includes('task agent of test er, running'),
    ),
  ).toBe(true);
});

test("the window's table reads as CHD-378's mocks at 120 and 80 columns: names and notes wrap in their cells, figures on a row's first line (CHD-473)", () => {
  const window: SpendPart[] = [
    {
      name: '1 fake',
      kind: 'tab',
      parts: [
        {
          name: 'main',
          kind: 'main',
          agent: 'fake',
          figure: { cost: USD(0.025), tokens: 4000 },
          parts: [
            {
              name: 'Rewrite the tokenizer as a single pass over the source',
              kind: 'task',
              ended: true,
              figure: { cost: USD(0.0125), tokens: 2000 },
            },
          ],
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
              figure: { cost: USD(0.025), tokens: 4000 },
              parts: [
                {
                  name: 'Run the parser suite',
                  kind: 'task',
                  ended: true,
                  figure: { cost: USD(0.0125), tokens: 2000 },
                },
              ],
            },
            {
              name: 'coder',
              kind: 'member',
              figure: { cost: USD(0.025), tokens: 4000 },
            },
          ],
        },
        {
          name: 'docs',
          kind: 'agent',
          figure: {
            cost: USD(0.0375),
            tokens: 6000,
            estimated: 'all',
            models: ['gpt-6.1-sol'],
            uncounted: 1,
          },
        },
        { name: 'parser', kind: 'agent' },
      ],
    },
  ];

  expect(lines(window, 112)).toStrictEqual([
    'This window                                    Cost  Tokens',
    '1 fake                                     ~$0.1625  26,000',
    '  main                                      $0.0250   4,000',
    '    Rewrite the tokenizer as a single       $0.0125   2,000  task agent, ended',
    '    pass over the source',
    '  bugfix                                    $0.0750  12,000  team run: lead $0.0250 · tester $0.0250 ·',
    '                                                             coder $0.0250',
    '    Run the parser suite                    $0.0125   2,000  task agent of tester, ended',
    "  docs                                     ~$0.0375   6,000  agent; chord's estimate from gpt-6.1-sol's price;",
    '                                                             1 turn not counted',
    '  parser                               not reported       —  agent',
    "Total                                      ~$0.1625  26,000  part chord's estimate; 1 turn not counted;",
    '                                                             parser not reported',
  ]);
  expect(lines(window, 72)).toStrictEqual([
    'This window                       Cost  Tokens',
    '1 fake                        ~$0.1625  26,000',
    '  main                         $0.0250   4,000',
    '    Rewrite the                $0.0125   2,000  task agent, ended',
    '    tokenizer as a',
    '    single pass over the',
    '    source',
    '  bugfix                       $0.0750  12,000  team run: lead $0.0250 ·',
    '                                                tester $0.0250 ·',
    '                                                coder $0.0250',
    '    Run the parser suite       $0.0125   2,000  task agent of tester,',
    '                                                ended',
    '  docs                        ~$0.0375   6,000  agent;',
    "                                                chord's estimate from",
    "                                                gpt-6.1-sol's price;",
    '                                                1 turn not counted',
    '  parser                  not reported       —  agent',
    "Total                         ~$0.1625  26,000  part chord's estimate;",
    '                                                1 turn not counted;',
    '                                                parser not reported',
  ]);
});

test("a note left fewer than 20 cells beside the figures goes below them, from the cost column on the row's second line, beside the name's next lines (CHD-473)", () => {
  const window: SpendPart[] = [
    {
      name: '1 fake',
      kind: 'tab',
      parts: [
        {
          name: 'main',
          kind: 'main',
          agent: 'fake',
          figure: { cost: USD(0.0375), tokens: 6000 },
          parts: [
            {
              name: 'Run the whole parser suite',
              kind: 'task',
              ended: true,
              figure: { cost: USD(0.0125), tokens: 2000 },
            },
          ],
        },
        { name: 'parser', kind: 'agent' },
      ],
    },
  ];

  expect(lines(window, 42)).toStrictEqual([
    'This window             Cost  Tokens',
    '1 fake               $0.0500   8,000',
    '  main               $0.0375   6,000',
    '    Run the          $0.0125   2,000',
    '    whole       task agent, ended',
    '    parser',
    '    suite',
    '  parser        not reported       —',
    '                agent',
    'Total                $0.0500   8,000',
    '                parser not reported',
  ]);
  // With 20 cells or more it stays beside them.
  expect(lines(window, 72).at(-1)).toBe(
    'Total                          $0.0500   8,000  parser not reported',
  );
});

describe('CHD-473 tester: full cells at the note floor and nested accounting', () => {
  const name = 'Long_closed_agent_name_that_needs_several_lines';
  const parts: SpendPart[] = [
    { name: 'main', kind: 'main', figure: { cost: USD(0.01) } },
    { name, kind: 'agent', ended: true, figure: { cost: USD(0.02) } },
  ];

  test('exactly twenty note cells stay beside figures; nineteen move to the second line at the cost edge', () => {
    for (const width of [57, 58]) {
      const drawn = lines(parts, width);
      const at = drawn.findIndex((line) => line.startsWith('Long_'));
      const end = drawn.findIndex((line) => line.startsWith('Total'));
      const block = drawn.slice(at, end);
      const note = block.find((line) => line.includes('agent, closed'));

      expect(at).toBeGreaterThan(0);
      expect(note).toBeDefined();
      expect(block[0]).toContain('$0.0200');
      expect(block.join(' ').match(/\$0\.0200/g)).toHaveLength(1);
      expect(
        block.map((line) => line.match(/^(\S+)/)?.[1] ?? '').join(''),
      ).toBe(name);

      if (width === 57) {
        expect(block[0]).not.toContain('agent, closed');
        expect(block[1]).toBe(note);
        expect(note!.indexOf('agent, closed')).toBe(21);
      } else {
        expect(block[0]).toBe(note);
        expect(note!.indexOf('agent, closed')).toBe(38);
      }

      expect(drawn.every((line) => stringWidth(line) <= width)).toBe(true);
    }
  });

  test('every word of estimate, legacy and uncounted notes survives each width across the floor', () => {
    const detailed: SpendPart[] = [
      { name: 'main', kind: 'main', figure: { cost: USD(0.01) } },
      {
        name,
        kind: 'agent',
        ended: true,
        figure: {
          cost: USD(0.02),
          estimated: 'all',
          models: ['model-with-a-very-long-public-name'],
          before: { cost: USD(0.01), until: Date.UTC(2026, 9, 12, 12) },
          uncounted: 3,
        },
      },
    ];
    const expected =
      "agent, closed; chord's estimate from model-with-a-very-long-public-name's price; as last reported before Oct 12; 3 turns not counted";

    for (let width = 42; width <= 120; width++) {
      const drawn = lines(detailed, width);
      const at = drawn.findIndex((line) => line.startsWith('Long_'));
      const end = drawn.findIndex((line) => line.startsWith('Total'));
      const block = drawn.slice(at, end);
      const nameWidth = Math.floor(width / 3);
      const beside = width - nameWidth - 20 >= 20;
      const notes = block
        .slice(beside ? 0 : 1)
        .map((line) => line.slice(nameWidth + (beside ? 20 : 2)))
        .join('');

      expect(notes.replace(/\s/g, ''), `notes at ${width}`).toBe(
        expected.replace(/\s/g, ''),
      );
      expect(
        drawn.every((line) => stringWidth(line) <= width),
        `width ${width}`,
      ).toBe(true);
      expect(drawn.join('')).not.toContain('…');
      expect(block.join(' ').match(/~\$0\.0200/g)).toHaveLength(1);
    }
  });

  test('Unicode names keep their whole graphemes and nesting while each task figure contributes once', () => {
    const child = '日本語🧪解析器の非常に長い名前';
    const grandchild = '🧵入れ子の作業名を最後まで読む';
    const nested: SpendPart[] = [
      {
        name: 'main',
        kind: 'main',
        figure: { cost: USD(0.01), tokens: 100 },
        parts: [
          {
            name: child,
            kind: 'task',
            ended: true,
            figure: { cost: USD(0.002), tokens: 200 },
            parts: [
              {
                name: grandchild,
                kind: 'task',
                ended: true,
                figure: { cost: USD(0.003), tokens: 300 },
              },
            ],
          },
        ],
      },
      {
        name: 'run',
        kind: 'team',
        parts: [
          {
            name: 'lead',
            kind: 'member',
            figure: { cost: USD(0.004), tokens: 400 },
          },
          {
            name: 'tester',
            kind: 'member',
            figure: { cost: USD(0.005), tokens: 500 },
            parts: [
              {
                name: 'Owned_task',
                kind: 'task',
                ended: true,
                figure: { cost: USD(0.006), tokens: 600 },
              },
            ],
          },
        ],
      },
    ];

    for (const width of [42, 57, 58, 72, 112]) {
      const drawn = lines(nested, width);
      const text = drawn.join('\n');
      const byDepth = (depth: number) =>
        drawn
          .flatMap(
            (line) => line.match(new RegExp(`^ {${depth}}(\\S+)`))?.[1] ?? [],
          )
          .join('');
      const run = drawn.find((line) => line.startsWith('run'))!;
      const total = drawn.find((line) => line.startsWith('Total'))!;
      const main = drawn.find((line) => line.startsWith('main'))!;

      expect(byDepth(2)).toBe(child + 'Owned_task');
      expect(byDepth(4)).toBe(grandchild);
      expect(run).toContain('$0.0090');
      expect(run).toContain('900');
      expect(main).toContain('$0.0100');
      expect(total).toContain('$0.0300');
      expect(total).toContain('2,100');

      for (const amount of ['0.0020', '0.0030', '0.0060']) {
        expect(text.split('$' + amount)).toHaveLength(2);
      }

      expect(drawn.every((line) => stringWidth(line) <= width)).toBe(true);
      expect(text).not.toContain('…');
      expect(text).not.toContain('�');
    }
  });
});

test('an agent that gives running totals reads as any row; only with no cost of its own do its notes say its provider gives none (CHD-472)', () => {
  const dirac = (name: string, figure: SpendPart['figure']): SpendPart => ({
    name,
    ...(name === 'main'
      ? { kind: 'main', agent: 'dirac' }
      : { kind: 'agent', runtime: 'dirac' }),
    ...(figure === undefined ? {} : { figure }),
  });
  const table = lines(
    [
      {
        name: '1 dirac',
        kind: 'tab',
        parts: [
          dirac('main', { cost: USD(0.025), tokens: 4000, totals: {} }),
          dirac('scout', {
            cost: USD(0.0094),
            estimated: 'all',
            models: ['gpt-5.3-codex'],
            tokens: 6000,
            totals: { model: 'gpt-5.3-codex' },
          }),
          dirac('docs', { tokens: 6000, totals: { model: 'fake-large' } }),
        ],
      },
    ],
    200,
  );
  const row = (name: string) =>
    table.find((line) => line.trimStart().startsWith(name)) ?? '';

  expect(row('main').trimEnd()).toMatch(/\$0\.0250\s+4,000$/);
  expect(row('scout')).toMatch(
    /~\$0\.0094\s+6,000 {2}agent; dirac's provider reports no cost; chord's estimate from gpt-5\.3-codex's price$/,
  );
  expect(row('docs')).toMatch(
    /not reported\s+6,000 {2}agent; dirac's provider reports no cost; no price for fake-large$/,
  );
});

test("the Total says once that dirac's provider reports no cost, however many dirac rows lack one, and still names any other agent that reported nothing (CHD-472)", () => {
  const unpriced = { tokens: 2000, totals: { model: 'fake-large' } };
  const total = lines(
    [
      {
        name: '1 dirac',
        kind: 'tab',
        parts: [
          { name: 'main', kind: 'main', agent: 'dirac', figure: unpriced },
        ],
      },
      {
        name: '2 dirac',
        kind: 'tab',
        parts: [
          { name: 'main', kind: 'main', agent: 'dirac', figure: unpriced },
          { name: 'scout', kind: 'agent', runtime: 'dirac', figure: unpriced },
        ],
      },
      {
        name: '3 gemini',
        kind: 'tab',
        parts: [{ name: 'main', kind: 'main', agent: 'gemini' }],
      },
    ],
    200,
  ).find((line) => line.startsWith('Total'));

  expect(total).toMatch(
    /^Total\s+not reported\s+6,000 {2}gemini not reported; dirac's provider reports no cost$/,
  );
});

test('a dirac row with some answering models unpriced: the estimate of the rest, its note naming the models with no price (CHD-472)', () => {
  const row = lines(
    [
      {
        name: '1 dirac',
        kind: 'tab',
        parts: [
          {
            name: 'main',
            kind: 'main',
            agent: 'dirac',
            figure: {
              cost: USD(0.0047),
              estimated: 'all',
              models: ['gpt-5.3-codex'],
              tokens: 6000,
              uncounted: 2,
              totals: { model: 'fake-large', unpriced: ['fake-large'] },
            },
          },
        ],
      },
    ],
    200,
  ).find((line) => line.startsWith('1 dirac'));

  expect(row).toMatch(
    /~\$0\.0047\s+6,000 {2}dirac's provider reports no cost; chord's estimate from its models' prices; no price for fake-large$/,
  );
});

describe('CHD-472 U2 tester: provider identity in mixed window totals', () => {
  for (const width of [72, 114]) {
    test(`dirac's missing provider is named once in Total with both priced and unpriced rows at ${width} cells`, () => {
      const parts: SpendPart[] = [
        {
          name: 'main',
          kind: 'main',
          agent: 'fake',
          figure: { cost: USD(0.01), tokens: 100 },
        },
        {
          name: 'unpriced',
          kind: 'agent',
          runtime: 'dirac',
          figure: { tokens: 4000, totals: { model: 'unpriced' } },
        },
        {
          name: 'priced',
          kind: 'agent',
          runtime: 'dirac',
          figure: {
            tokens: 2000,
            totals: { model: 'gpt-5.3-codex' },
            cost: USD(0.00469),
            estimated: 'all',
            models: ['gpt-5.3-codex'],
          },
        },
        {
          name: 'missing',
          kind: 'agent',
          runtime: 'fake',
          figure: { tokens: 20 },
        },
      ];
      const output = lines(parts, width);
      const total = output
        .slice(output.findIndex((row) => row.startsWith('Total')))
        .join(' ')
        .replace(/\s+/g, ' ');

      expect(total.match(/dirac's provider reports no cost/g)).toHaveLength(1);
      expect(total).toContain('missing not reported');
      expect(total).not.toContain('dirac not reported');
      expect(total).toContain('6,120');
      expect(output.every((row) => stringWidth(row) <= width)).toBe(true);
      expect(output.join(' ').replace(/\s+/g, ' ')).toContain(
        'no price for unpriced',
      );
    });
  }
});
