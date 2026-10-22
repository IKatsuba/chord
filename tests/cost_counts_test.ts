import { expect, test } from 'bun:test';
import { findAgent } from '../src/agents.ts';
import {
  COST_COUNTS,
  costCountOf,
  USAGE_COUNTS,
  usageCountOf,
} from '../src/cost_counts.ts';

test('each agent whose cost or usage counting is kept is one chord starts by that name', () => {
  expect(
    [...Object.keys(COST_COUNTS), ...Object.keys(USAGE_COUNTS)].filter(
      (name) => findAgent(name) === undefined,
    ),
  ).toStrictEqual([]);
});

test("claude's cost counts from each opening, dimcode's, dirac's, kilo's and opencode's from the session's start, and any other's is not known", () => {
  expect(costCountOf('claude')).toBe('opening');
  expect(
    ['dimcode', 'dirac', 'kilo', 'opencode'].map(costCountOf),
  ).toStrictEqual(['session', 'session', 'session', 'session']);
  expect(costCountOf('codex')).toBe(undefined);
  expect(costCountOf('toString')).toBe(undefined);
});

test("dirac's answer usage is the session's running total; any other agent's is the turn's own (CHD-472)", () => {
  expect(usageCountOf('dirac')).toBe('session');
  expect(usageCountOf('claude')).toBe(undefined);
  expect(usageCountOf('dimcode')).toBe(undefined);
  expect(usageCountOf('toString')).toBe(undefined);
});
