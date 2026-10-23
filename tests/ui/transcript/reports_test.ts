import { describe, expect, test } from 'bun:test';
import {
  contextReport,
  reportFacts,
  costReport,
  formatCost,
  type ReportFacts,
  sessionTokens,
  statusReport,
} from '../../../src/ui/transcript/reports.ts';

import { initialAppState } from '../../../src/ui/app/state.ts';

const FACTS: ReportFacts = {
  agent: 'fake',
  cwd: '/work',
  sessionId: 'session-1',
  since: 0,
  now: 65_000,
  modes: [
    { id: 'default', name: 'Default' },
    { id: 'plan', name: 'Plan' },
  ],
};

const text = (rows: readonly { label?: string; text: string }[]) =>
  rows.map(({ label, text }) => `${label ?? ''}${text}`);

test("the session's tokens are each turn's added up", () => {
  expect(
    sessionTokens({
      turns: {
        a: { inputTokens: 10, outputTokens: 2, cachedReadTokens: 3 },
        b: { inputTokens: 5, outputTokens: 1 },
      },
    }),
  ).toStrictEqual({ inputTokens: 15, outputTokens: 3, cachedReadTokens: 3 });
  expect(sessionTokens({ turns: {} })).toStrictEqual(undefined);
  expect(sessionTokens(undefined)).toStrictEqual(undefined);
});

test('a cost reads as Claude Code writes one', () => {
  expect(formatCost({ amount: 0.0125, currency: 'USD' })).toStrictEqual(
    '$0.0125',
  );
  expect(formatCost({ amount: 1.234, currency: 'USD' })).toStrictEqual('$1.23');
  expect(formatCost({ amount: 3, currency: 'EUR' })).toStrictEqual('€3.00');
  expect(formatCost({ amount: 3, currency: 'credits' })).toStrictEqual(
    '3.00 credits',
  );
});

test('/cost lines up tokens, cost and time', () => {
  expect(
    text(
      costReport({
        ...FACTS,
        spent: {
          turns: {
            a: { inputTokens: 1000, outputTokens: 200, cachedReadTokens: 800 },
            b: { inputTokens: 1000, outputTokens: 200, cachedReadTokens: 800 },
          },
          // Each turn's own cost: the session's is theirs added (CHD-373).
          costs: {
            a: { cost: { amount: 0.0125, currency: 'USD' } },
            b: { cost: { amount: 0.0125, currency: 'USD' } },
          },
        },
        context: {
          used: 4000,
          size: 1_000_000,
          cost: { amount: 0.025, currency: 'USD' },
        },
      }),
    ),
  ).toStrictEqual([
    'Total cost:   $0.0250',
    'Tokens in:    2,000',
    'Tokens out:   400',
    'Cache read:   1,600',
    'Session time: 1m 5s',
  ]);
});

test('/cost says what the agent left out, and draws no zeros', () => {
  expect(text(costReport(FACTS))).toStrictEqual([
    'fake has not reported what this session has used.',
    'Session time: 1m 5s',
  ]);
  expect(
    text(costReport({ ...FACTS, spent: { turns: { a: { inputTokens: 9 } } } })),
  ).toStrictEqual([
    'Total cost:   not reported by fake',
    'Tokens in:    9',
    'Session time: 1m 5s',
  ]);
  // A turn's cost, when no turn reported tokens.
  expect(
    text(
      costReport({
        ...FACTS,
        since: undefined,
        spent: {
          turns: {},
          costs: { a: { cost: { amount: 0.5, currency: 'USD' } } },
        },
      }),
    ),
  ).toStrictEqual(['Total cost: $0.5000', 'Tokens:     not reported by fake']);
  // An agent that gives only a total still said how many.
  expect(
    text(
      costReport({
        ...FACTS,
        since: undefined,
        spent: { turns: { a: { totalTokens: 7 } } },
      }),
    ),
  ).toStrictEqual(['Total cost: not reported by fake', 'Tokens:     7']);
});

test('/context agrees with the status line on what is used', () => {
  expect(
    text(contextReport({ ...FACTS, context: { used: 4000, size: 1_000_000 } })),
  ).toStrictEqual([
    'Used: 4,000 of 1,000,000 tokens (1%)',
    'Free: 996,000 tokens (99%)',
  ]);
  expect(text(contextReport(FACTS))).toStrictEqual([
    'fake has not reported how full its context window is.',
  ]);
});

test('/status names the agent, model, mode, session and directory', () => {
  expect(
    text(
      statusReport({
        ...FACTS,
        models: { available: [{ id: 'l', name: 'Large' }], current: 'l' },
        mode: 'plan',
      }),
    ),
  ).toStrictEqual([
    'Agent:     fake',
    'Model:     Large',
    'Mode:      Plan',
    'Session:   session-1',
    'Directory: /work',
  ]);
  expect(
    text(statusReport({ ...FACTS, sessionId: undefined })).slice(1, 4),
  ).toStrictEqual([
    'Model:     not reported by fake',
    'Mode:      not reported by fake',
    'Session:   starting…',
  ]);
});

test("a cost and a context chord worked out read as chord's estimate", () => {
  expect(
    text(
      costReport({
        ...FACTS,
        since: undefined,
        spent: {
          turns: { a: { inputTokens: 1000 } },
          costs: {
            a: { cost: { amount: 0.0042, currency: 'USD' }, estimated: true },
          },
        },
        context: {
          used: 1000,
          size: 400_000,
          cost: { amount: 0.0042, currency: 'USD' },
          estimated: ['used', 'cost', 'size'],
        },
      }),
    ),
  ).toStrictEqual([
    "Total cost: $0.0042 (chord's estimate)",
    'Tokens in:  1,000',
  ]);
  expect(
    text(
      contextReport({
        ...FACTS,
        context: { used: 4000, size: 1_000_000, estimated: ['size'] },
      }),
    ),
  ).toStrictEqual([
    "Used: 4,000 of 1,000,000 tokens (1%) (chord's estimate)",
    "Free: 996,000 tokens (99%) (chord's estimate)",
  ]);
  expect(
    text(contextReport({ ...FACTS, context: { used: 4000, size: 0 } })),
  ).toStrictEqual(['fake has not reported how full its context window is.']);
});

test("/cost says the turn running is counted when it ends, until any of its spend has come (the owner's Q51, CHD-405)", () => {
  const earlier = {
    turns: {
      a: { inputTokens: 1000, outputTokens: 200, cachedReadTokens: 800 },
    },
    // The earlier turn's own cost, chord's estimate: the total is theirs
    // added (CHD-373).
    costs: {
      a: { cost: { amount: 0.025, currency: 'USD' }, estimated: true as const },
    },
  };
  const estimated = {
    used: 4000,
    size: 1_000_000,
    cost: { amount: 0.025, currency: 'USD' },
    estimated: ['cost'] as const,
  };

  // Earlier turns reported: the row goes right after the total.
  expect(
    text(
      costReport({
        ...FACTS,
        spent: earlier,
        context: estimated,
        running: 'b',
      }),
    ),
  ).toStrictEqual([
    "Total cost:   $0.0250 (chord's estimate)",
    'This turn:    counted when it ends',
    'Tokens in:    1,000',
    'Tokens out:   200',
    'Cache read:   800',
    'Session time: 1m 5s',
  ]);
  // A first turn with nothing reported: after the sentence, before the time.
  expect(text(costReport({ ...FACTS, running: 'a' }))).toStrictEqual([
    'fake has not reported what this session has used.',
    'This turn:    counted when it ends',
    'Session time: 1m 5s',
  ]);
  // Its spend in, or no turn running: no row.
  expect(
    text(costReport({ ...FACTS, spent: earlier, running: 'a' })),
  ).not.toContain('This turn:    counted when it ends');
  expect(
    text(costReport({ ...FACTS, spent: earlier, context: estimated })),
  ).not.toContain('This turn:    counted when it ends');
});

describe('CHD-405 N2 tester: running spend boundaries', () => {
  test('a held between-turn permission with no running turn adds no current-turn row', () => {
    const state = {
      ...initialAppState,
      transcript: {
        ...initialAppState.transcript,
        turn: {
          status: 'awaiting_permission' as const,
          turnId: 'ended',
          since: 100,
          permissions: [{ id: 'held', options: [] }],
          between: true as const,
        },
      },
    };
    const facts = reportFacts(state, 'codex', '/work', 500);

    expect(facts.running).toBeUndefined();
    expect(text(costReport(facts)).join('\n')).not.toContain('This turn:');
  });

  test('recorded zero spend counts as reported, and an unrelated turn does not', () => {
    const spent = { turns: { current: { inputTokens: 0, outputTokens: 0 } } };

    expect(
      text(costReport({ ...FACTS, running: 'current', spent })).join('\n'),
    ).not.toContain('This turn:');
    expect(
      text(costReport({ ...FACTS, running: 'next', spent })).join('\n'),
    ).toContain('counted when it ends');
  });
});

test("a permission held inside the agent's own cycle leaves the cycle running: /cost says it is counted when it ends (CHD-405, CHD-426)", () => {
  const held = {
    status: 'awaiting_permission' as const,
    turnId: 'cycle',
    since: 100,
    permissions: [{ id: 'held', options: [] }],
    between: true as const,
  };
  const facts = (cycle: boolean) =>
    reportFacts(
      {
        ...initialAppState,
        transcript: {
          ...initialAppState.transcript,
          turn: cycle ? { ...held, cycle: true as const } : held,
        },
      },
      'claude',
      '/work',
      500,
    );

  expect(facts(true).running).toBe('cycle');
  expect(text(costReport(facts(true))).join('\n')).toMatch(
    /This turn: +counted when it ends/,
  );
  // Held between turns with no cycle: nothing runs.
  expect(facts(false).running).toBeUndefined();
});

test("/cost's total is the whole session's, marked when part of it is chord's estimate, with an older record's sum and turns left out each a row of its own (CHD-373)", () => {
  const usd = (amount: number) => ({ amount, currency: 'USD' });

  expect(
    text(
      costReport({
        ...FACTS,
        since: undefined,
        spent: {
          turns: { a: { inputTokens: 48_200 } },
          costs: {
            'history-before': {
              cost: usd(0.04),
              before: { until: Date.UTC(2026, 9, 12, 12) },
            },
            a: { cost: usd(0.1), estimated: true },
            b: { cost: usd(0.044) },
            c: { uncounted: true },
          },
        },
      }),
    ),
  ).toStrictEqual([
    "Total cost:    $0.1840 (part chord's estimate)",
    'Before Oct 12: $0.0400 as last reported',
    'Not counted:   1 turn',
    'Tokens in:     48,200',
  ]);
});

test("/cost adds the window's table once it holds more than one session, and leaves it out for one", () => {
  const main = {
    name: 'main',
    kind: 'main' as const,
    agent: 'fake',
    figure: { cost: { amount: 0.025, currency: 'USD' } },
  };
  const one = { spend: [main], width: 114 };
  const two = {
    spend: [
      main,
      {
        name: 'parser',
        kind: 'agent' as const,
        runtime: 'fake',
        figure: { cost: { amount: 0.025, currency: 'USD' } },
      },
    ],
    width: 114,
  };
  const facts = {
    ...FACTS,
    since: undefined,
    spent: {
      turns: {},
      costs: { a: { cost: { amount: 0.025, currency: 'USD' } } },
    },
  };

  expect(text(costReport({ ...facts, window: one }))).toStrictEqual([
    'Total cost: $0.0250',
    'Tokens:     not reported by fake',
  ]);
  expect(text(costReport({ ...facts, window: two })).slice(2)).toStrictEqual([
    '',
    'This session     Cost  Tokens',
    'main          $0.0250       —',
    'parser        $0.0250       —  agent',
    'Total         $0.0500       —',
  ]);
});

describe('CHD-472: /cost on an agent that gives running totals', () => {
  const usd = (amount: number) => ({ amount, currency: 'USD' });
  const DIRAC: ReportFacts = {
    ...FACTS,
    agent: 'dirac',
    models: {
      available: [{ id: 'gpt-5.3-codex', name: 'GPT-5.3 Codex' }],
      current: 'gpt-5.3-codex',
    },
  };

  test("its own cost: the rows as for any agent, its last total's tokens, and one line on how they were read", () => {
    const rows = costReport({
      ...DIRAC,
      spent: {
        turns: {},
        total: { inputTokens: 2000, outputTokens: 400, cachedReadTokens: 1600 },
        costs: { a: { cost: usd(0.0125) }, b: { cost: usd(0.0125) } },
      },
    });

    expect(text(rows)).toStrictEqual([
      'Total cost:   $0.0250',
      'Tokens in:    2,000',
      'Tokens out:   400',
      'Cache read:   1,600',
      'Session time: 1m 5s',
      "dirac reports these as the session's running total; chord shows the last it sent.",
    ]);
  });

  test("no cost of its own, the model priced: chord's estimate, and why", () => {
    const rows = costReport({
      ...DIRAC,
      since: undefined,
      spent: {
        turns: {},
        total: { totalTokens: 6000 },
        totalModel: 'gpt-5.3-codex',
        costs: {
          a: { cost: usd(0.0094), estimated: true, model: 'gpt-5.3-codex' },
        },
      },
    });

    expect(text(rows)).toStrictEqual([
      "Total cost: $0.0094 (chord's estimate)",
      'Tokens:     6,000',
      "dirac reports these as the session's running total; chord shows the last it sent.",
      "dirac's provider reports no cost, so chord priced these tokens at GPT-5.3 Codex's price.",
    ]);
  });

  test('no cost, and no price for its model: both reasons in the cost cell, and no second line', () => {
    const rows = costReport({
      ...DIRAC,
      since: undefined,
      models: { available: [{ id: 'fake-large', name: 'Fake Large' }] },
      spent: {
        turns: {},
        total: { totalTokens: 6000 },
        totalModel: 'fake-large',
      },
    });

    expect(text(rows)).toStrictEqual([
      "Total cost: not reported: dirac's provider reports none, and chord has no price for Fake Large",
      'Tokens:     6,000',
      "dirac reports these as the session's running total; chord shows the last it sent.",
    ]);
  });

  test('an agent that adds its turns up reads as it did, with no line', () => {
    const rows = costReport({
      ...FACTS,
      since: undefined,
      spent: { turns: { a: { totalTokens: 2000 } } },
    });

    expect(text(rows)).toStrictEqual([
      'Total cost: not reported by fake',
      'Tokens:     2,000',
    ]);
  });
});

describe("CHD-472: /cost when some of dirac's answering models have no price", () => {
  const usd = (amount: number) => ({ amount, currency: 'USD' });
  const MIXED: ReportFacts = {
    ...FACTS,
    agent: 'dirac',
    since: undefined,
    models: {
      available: [
        { id: 'gpt-5.3-codex', name: 'GPT-5.3 Codex' },
        { id: 'fake-large', name: 'Fake Large' },
        { id: 'fake-small', name: 'Fake Small' },
      ],
    },
  };

  test("what was priced is chord's estimate, the turns left out are not counted, and the line names the model with no price", () => {
    expect(
      text(
        costReport({
          ...MIXED,
          spent: {
            turns: {},
            total: { totalTokens: 6000 },
            totalModel: 'fake-large',
            costs: {
              a: { cost: usd(0.0047), estimated: true, model: 'gpt-5.3-codex' },
              b: { uncounted: true, model: 'fake-large' },
              c: { uncounted: true, model: 'fake-large' },
            },
          },
        }),
      ),
    ).toStrictEqual([
      "Total cost:  $0.0047 (chord's estimate)",
      'Not counted: 2 turns',
      'Tokens:      6,000',
      "dirac reports these as the session's running total; chord shows the last it sent.",
      "dirac's provider reports no cost, so chord priced each answer's tokens at the price of the model that gave it; it has no price for Fake Large.",
    ]);
  });

  test('several models with no price are named in the order they first answered', () => {
    const [, , , , line] = text(
      costReport({
        ...MIXED,
        spent: {
          turns: {},
          total: { totalTokens: 6000 },
          costs: {
            a: { uncounted: true, model: 'fake-small' },
            b: { cost: usd(0.0047), estimated: true, model: 'gpt-5.3-codex' },
            c: { uncounted: true, model: 'fake-large' },
            d: { uncounted: true, model: 'fake-small' },
          },
        },
      }),
    );

    expect(line).toEndWith('it has no price for Fake Small and Fake Large.');
  });

  test('with no model priced at all, the cell says so and no turn is said not counted', () => {
    expect(
      text(
        costReport({
          ...MIXED,
          spent: {
            turns: {},
            total: { totalTokens: 6000 },
            totalModel: 'fake-large',
            costs: {
              a: { uncounted: true, model: 'fake-large' },
              b: { uncounted: true, model: 'fake-large' },
            },
          },
        }),
      ),
    ).toStrictEqual([
      "Total cost: not reported: dirac's provider reports none, and chord has no price for Fake Large",
      'Tokens:     6,000',
      "dirac reports these as the session's running total; chord shows the last it sent.",
    ]);
  });
});

test('with no dirac cost and several models all priced, the line says each answer was priced at the model that gave it (CHD-472)', () => {
  const usd = (amount: number) => ({ amount, currency: 'USD' });
  const [, , line] = text(
    costReport({
      ...FACTS,
      agent: 'dirac',
      since: undefined,
      spent: {
        turns: {},
        total: { totalTokens: 4000 },
        costs: {
          a: { cost: usd(0.004), estimated: true, model: 'gpt-5.3-codex' },
          b: { cost: usd(0.001), estimated: true, model: 'claude-haiku-4-5' },
        },
      },
    }),
  ).slice(1);

  expect(line).toBe(
    "dirac's provider reports no cost, so chord priced each answer's tokens at the price of the model that gave it.",
  );
});

describe('CHD-472 U2 tester: report metadata stays tied to the last total', () => {
  test('changing the selected model without a new total does not rename the model whose tokens had no price', () => {
    const rows = costReport({
      ...FACTS,
      agent: 'dirac',
      since: undefined,
      models: {
        current: 'gpt-5.3-codex',
        available: [
          { id: 'unpriced', name: 'Old unpriced model' },
          { id: 'gpt-5.3-codex', name: 'GPT-5.3 Codex' },
        ],
      },
      spent: {
        turns: {},
        total: { inputTokens: 0, outputTokens: 0, totalTokens: 0 },
        totalModel: 'unpriced',
      },
    });
    const words = text(rows).join('\n');

    expect(words).toContain('chord has no price for Old unpriced model');
    expect(words).not.toContain('no price for GPT-5.3');
    expect(words).toContain('Tokens in:  0');
    expect(words).not.toContain('Not counted');
    expect(words).not.toContain('Before');
  });

  test('a reported zero cost is not a missing provider cost or an estimate', () => {
    const words = text(
      costReport({
        ...FACTS,
        agent: 'dirac',
        since: undefined,
        spent: {
          turns: {},
          total: { totalTokens: 0 },
          costs: { a: { cost: { amount: 0, currency: 'USD' } } },
        },
      }),
    ).join('\n');

    expect(words).toContain('Total cost: $0.0000');
    expect(words).toContain('Tokens:     0');
    expect(words).toContain(
      "dirac reports these as the session's running total",
    );
    expect(words).not.toContain('provider');
    expect(words).not.toContain('estimate');
  });
});
