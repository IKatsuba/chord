import { expect, test } from 'bun:test';
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
