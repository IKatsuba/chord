import { describe, expect, test } from 'bun:test';
import { addTurn, tokensOf } from '../../src/session/usage.ts';
import { sessionTokens } from '../../src/ui/transcript/reports.ts';

test("a turn's tokens are ACP's without its nulls", () => {
  expect(
    tokensOf({
      inputTokens: 10,
      outputTokens: 2,
      totalTokens: 12,
      thoughtTokens: null,
      _meta: { model: 'large' },
    }),
  ).toStrictEqual({ inputTokens: 10, outputTokens: 2, totalTokens: 12 });
});

test('every turn counts, however many', () => {
  let spent = addTurn(undefined, 'turn-1', { inputTokens: 10_000 });

  for (let turn = 2; turn <= 150; turn++) {
    spent = addTurn(spent, `turn-${turn}`, { inputTokens: 1, outputTokens: 1 });
  }

  expect(sessionTokens(spent)).toStrictEqual({
    inputTokens: 10_149,
    outputTokens: 149,
  });
});

test('a turn reported again reads as it last did', () => {
  const once = addTurn(undefined, 'a', { inputTokens: 5 });
  const twice = addTurn(addTurn(once, 'b', { inputTokens: 1 }), 'a', {
    inputTokens: 7,
    outputTokens: 3,
  });

  expect(sessionTokens(twice)).toStrictEqual({
    inputTokens: 8,
    outputTokens: 3,
  });
});

test("a turn's own cost is kept by its turn, replaced when said again, and a turn with no tokens, an agent's own cycle, adds none", () => {
  const usd = (amount: number) => ({ amount, currency: 'USD' });
  let spent = addTurn(undefined, 'a', { inputTokens: 5 }, { cost: usd(0.01) });

  spent = addTurn(spent, 'cycle', {}, { cost: usd(0.002), estimated: true });
  spent = addTurn(spent, 'b', { inputTokens: 1 }, { uncounted: true });
  // Said again late, with its cost.
  spent = addTurn(spent, 'a', { inputTokens: 5 }, { cost: usd(0.015) });

  expect(spent.turns).toStrictEqual({
    a: { inputTokens: 5 },
    b: { inputTokens: 1 },
  });
  expect(spent.costs).toStrictEqual({
    a: { cost: usd(0.015) },
    cycle: { cost: usd(0.002), estimated: true },
    b: { uncounted: true },
  });
  // A turn said again with no cost has none.
  expect(addTurn(spent, 'a', { inputTokens: 5 }).costs).toStrictEqual({
    cycle: { cost: usd(0.002), estimated: true },
    b: { uncounted: true },
  });
  // Nothing of cost until one comes.
  expect(addTurn(undefined, 'a', { inputTokens: 5 })).toStrictEqual({
    turns: { a: { inputTokens: 5 } },
  });
});

test("a running total replaces the session's total and keeps no turn of its own; the turn's cost is kept as any is (CHD-472)", () => {
  const usd = (amount: number) => ({ amount, currency: 'USD' });
  let spent = addTurn(
    undefined,
    't1',
    { inputTokens: 10 },
    { cost: usd(1) },
    true,
  );

  spent = addTurn(spent, 't2', { inputTokens: 25 }, { cost: usd(2) }, true);
  // An answer with no tokens leaves the total as it was.
  spent = addTurn(spent, 't3', {}, {}, true);

  expect(spent.total).toStrictEqual({ inputTokens: 25 });
  expect(spent.turns).toStrictEqual({});
  expect(Object.keys(spent.costs ?? {})).toStrictEqual(['t1', 't2']);
  expect(sessionTokens(spent)).toStrictEqual({ inputTokens: 25 });
  // Another agent's turns still add up.
  expect(
    sessionTokens(
      addTurn(addTurn(undefined, 't1', { inputTokens: 10 }), 't2', {
        inputTokens: 25,
      }),
    ),
  ).toStrictEqual({ inputTokens: 35 });
});

describe('CHD-472 U1 tester: the last total replaces every token field', () => {
  test('zero is a reported total, omitted fields are not retained, and empty usage preserves the last report', () => {
    const first = addTurn(
      undefined,
      'first',
      {
        inputTokens: 100,
        outputTokens: 20,
        cachedReadTokens: 50,
        cachedWriteTokens: 4,
        thoughtTokens: 7,
        totalTokens: 120,
      },
      {},
      true,
    );
    const zero = addTurn(
      first,
      'second',
      { inputTokens: 0, totalTokens: 0 },
      {},
      true,
    );

    expect(sessionTokens(zero)).toEqual({ inputTokens: 0, totalTokens: 0 });
    expect(sessionTokens(addTurn(zero, 'third', {}, {}, true))).toEqual({
      inputTokens: 0,
      totalTokens: 0,
    });
    expect(first.total?.outputTokens).toBe(20);
    expect(zero.turns).toEqual({});
  });

  test('a later lower total is used as sent; replacing one cost never deletes another turn cost', () => {
    const cost = (amount: number) => ({ cost: { amount, currency: 'USD' } });
    const first = addTurn(undefined, 'a', { totalTokens: 100 }, cost(1), true);
    const second = addTurn(first, 'b', { totalTokens: 200 }, cost(2), true);
    const corrected = addTurn(
      second,
      'a',
      { totalTokens: 40 },
      cost(0.5),
      true,
    );

    expect(sessionTokens(corrected)).toEqual({ totalTokens: 40 });
    expect(corrected.costs).toEqual({ a: cost(0.5), b: cost(2) });
    expect(sessionTokens(second)).toEqual({ totalTokens: 200 });
  });

  test('two sessions have independent totals and ordinary agents still sum partial token fields', () => {
    const a = addTurn(undefined, 'shared-id', { inputTokens: 50 }, {}, true);
    const b = addTurn(undefined, 'shared-id', { outputTokens: 7 }, {}, true);

    expect(sessionTokens(a)).toEqual({ inputTokens: 50 });
    expect(sessionTokens(b)).toEqual({ outputTokens: 7 });

    const own = addTurn(addTurn(undefined, 'a', { inputTokens: 2 }), 'b', {
      outputTokens: 3,
    });

    expect(sessionTokens(own)).toEqual({ inputTokens: 2, outputTokens: 3 });
  });
});
