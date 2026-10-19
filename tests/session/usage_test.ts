import { expect, test } from 'bun:test';
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
