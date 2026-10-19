import { expect, test } from 'bun:test';
import { findAgent } from '../src/agents.ts';
import { COST_COUNTS, costCountOf } from '../src/cost_counts.ts';

test('each agent whose cost counting is kept is one chord starts by that name', () => {
  expect(
    Object.keys(COST_COUNTS).filter((name) => findAgent(name) === undefined),
  ).toStrictEqual([]);
});

test("claude's cost counts from each opening, dimcode's, kilo's and opencode's from the session's start, and any other's is not known", () => {
  expect(costCountOf('claude')).toBe('opening');
  expect(['dimcode', 'kilo', 'opencode'].map(costCountOf)).toStrictEqual([
    'session',
    'session',
    'session',
  ]);
  expect(costCountOf('codex')).toBe(undefined);
  expect(costCountOf('toString')).toBe(undefined);
});
