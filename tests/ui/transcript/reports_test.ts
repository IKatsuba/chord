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
  // The `usage_update`'s cost, when no turn reported tokens.
  expect(
    text(
      costReport({
        ...FACTS,
        since: undefined,
        context: { used: 1, size: 2, cost: { amount: 0.5, currency: 'USD' } },
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

test('/status counts the sessions open once there are several', () => {
  const sessions = (open: number, waits: number) =>
    text(statusReport({ ...FACTS, sessions: { open, waits } })).at(-1);

  expect(sessions(1, 0)).toStrictEqual('Directory: /work');
  expect(sessions(2, 0)).toStrictEqual('Sessions:  2 open');
  expect(sessions(3, 1)).toStrictEqual('Sessions:  3 open (1 waits)');
  expect(sessions(4, 2)).toStrictEqual('Sessions:  4 open (2 wait)');
});

test("a cost and a context chord worked out read as chord's estimate", () => {
  expect(
    text(
      costReport({
        ...FACTS,
        since: undefined,
        spent: { turns: { a: { inputTokens: 1000 } } },
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
