import { describe, expect, test } from 'bun:test';
import type { InitializeResponse } from '@agentclientprotocol/sdk/unstable';
import {
  initialEntries,
  initialValuesOf,
} from '../../src/session/initial_options.ts';

const CLAUDE = '@agentclientprotocol/claude-agent-acp';

function init(name: string, options: boolean): InitializeResponse {
  return {
    protocolVersion: 1,
    agentInfo: { name, version: '0.107.0' },
    agentCapabilities: {
      sessionCapabilities: options ? { options: {} } : {},
    },
  };
}

const ALL = { mode: 'plan', effort: 'high', model: 'opus' };

test('entries go model, effort, mode, one per id, by the ids the table gives the adapter', () => {
  expect(initialEntries(init(CLAUDE, true), ALL)).toStrictEqual([
    { configId: 'model', value: 'opus' },
    { configId: 'effort', value: 'high' },
    { configId: 'mode', value: 'plan' },
  ]);
});

test('only the values named go: chord adds none of its own', () => {
  expect(initialEntries(init(CLAUDE, true), { mode: 'plan' })).toStrictEqual([
    { configId: 'mode', value: 'plan' },
  ]);
  expect(initialEntries(init(CLAUDE, true), {})).toStrictEqual([]);
});

test('none without sessionCapabilities.options, or for an adapter the table does not have', () => {
  expect(initialEntries(init(CLAUDE, false), ALL)).toStrictEqual([]);
  expect(initialEntries(init('codex-acp', true), ALL)).toStrictEqual([]);
  expect(
    initialEntries({ protocolVersion: 1, agentCapabilities: {} }, ALL),
  ).toStrictEqual([]);
});

test('the values are the ids chord holds, where they were set left behind', () => {
  expect(
    initialValuesOf({
      model: { id: 'opus' },
      mode: { id: 'plan' },
      effort: undefined,
    }),
  ).toStrictEqual({ model: 'opus', mode: 'plan' });
});

describe('CHD-629 tester: initial option table boundaries', () => {
  test('all partial selections preserve order and opaque value ids', () => {
    const values = {
      model: 'model:opaque',
      effort: 'effort:opaque',
      mode: 'mode:opaque',
    };
    const keys = ['model', 'effort', 'mode'] as const;

    for (let mask = 0; mask < 8; mask++) {
      const selected = Object.fromEntries(
        keys
          .filter((_, index) => (mask & (1 << index)) !== 0)
          .map((key) => [key, values[key]]),
      );

      expect(initialEntries(init(CLAUDE, true), selected)).toStrictEqual(
        keys.flatMap((key, index) =>
          (mask & (1 << index)) !== 0
            ? [{ configId: key, value: values[key] }]
            : [],
        ),
      );
    }
  });

  test('adapter names are exact and an omitted session capability declares nothing', () => {
    for (const name of [
      'claude',
      'claude-acp',
      `${CLAUDE} `,
      CLAUDE.toUpperCase(),
    ]) {
      expect(initialEntries(init(name, true), ALL)).toStrictEqual([]);
    }

    expect(
      initialEntries(
        { protocolVersion: 1, agentInfo: { name: CLAUDE, version: '0.107.0' } },
        ALL,
      ),
    ).toStrictEqual([]);
  });
});

test("a client's entries go after chord's, as sent, and take the place of chord's for the same id (the owner's Q4 b)", () => {
  const entries = [
    { configId: 'effort', value: 'max' },
    { configId: 'nope', value: 'x' },
  ];

  expect(initialEntries(init(CLAUDE, true), { ...ALL, entries })).toStrictEqual(
    [
      { configId: 'model', value: 'opus' },
      { configId: 'mode', value: 'plan' },
      ...entries,
    ],
  );
  expect(
    initialEntries(init('codex-acp', true), { ...ALL, entries }),
  ).toStrictEqual(entries);
  expect(initialEntries(init(CLAUDE, false), { entries })).toStrictEqual([]);
});
