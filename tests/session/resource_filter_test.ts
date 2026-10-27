import { describe, expect, test } from 'bun:test';
import { BudgetSnapshot } from '../../src/session/budgets.ts';
import {
  filterResourceFacts,
  POOL_SCOPE_INCOMPLETE,
  UNAVAILABLE_SCOPE_INCOMPLETE,
  ResourceAgents,
} from '../../src/session/resource_filter.ts';

import {
  RESOURCE_CLEANUP_FAILED,
  WARNINGS_OMITTED,
} from '../../src/session/resource_warnings.ts';

const time = '2026-10-27T12:00:00.000Z';
const window = {
  windowRef: 'weekly',
  models: null,
  usedPercent: 12.345,
  windowSeconds: 604800,
  resetsAt: null,
  observedAt: null,
  receivedAt: time,
  state: 'unknown' as const,
  reason: 'Provider time unknown.',
};
const pool = {
  poolRef: 'shared-pool',
  accountRef: 'verified-account',
  provider: 'provider-not-runtime',
  billing: 'subscription' as const,
  identityObservedAt: time,
  identity: 'verified' as const,
  source: 'synthetic-authoritative-fixture',
  sourceVersion: '1',
  coverage: 'account' as const,
  externalActivity: 'unknown' as const,
  windows: [window],
};
const active = (agent: string, resourceRefs: string[] = ['shared-pool']) => ({
  processRef: 'process',
  runRef: agent,
  sessionRef: agent,
  team: null,
  member: 'main',
  agent,
  model: null,
  resourceRefs,
  state: 'idle' as const,
  lastSeenAt: time,
});
const unbound = (agent: string) => ({
  observationRef: agent,
  sourceRef: agent,
  sessionRef: agent,
  agent,
  source: 'synthetic-fixture',
  sourceVersion: '1',
  coverage: 'unknown' as const,
  externalActivity: 'unknown' as const,
  windows: [window],
  observedAt: null,
  billingKind: 'unknown' as const,
  reason: 'Identity unverified.',
});
const facts = (): BudgetSnapshot => ({
  schemaVersion: 1,
  observedAt: time,
  preferences: { intent: 'balanced' },
  pools: [pool, { ...pool, poolRef: 'unattributed', provider: 'codex' }],
  unbound: [unbound('codex'), unbound('claude')],
  unavailable: [{ agent: 'other', reason: 'Unavailable.' }],
  activeRuns: [active('codex'), active('claude'), active('other', [])],
  warnings: ['Collected coverage is incomplete.'],
});

test('omission preserves current facts and explicit empty filter exposes no runtime facts', () => {
  const before = facts();

  expect(filterResourceFacts(before, undefined)).toBe(before);
  expect(filterResourceFacts(before, [])).toEqual({
    ...before,
    pools: [],
    unbound: [],
    unavailable: [],
    activeRuns: [],
  });
});

test('shared pool stays once through explicit role references; unbound observations stay independent', () => {
  const before = facts();
  const copy = structuredClone(before);
  const filtered = filterResourceFacts(before, ['codex', 'claude', 'codex']);

  expect(filtered.pools).toEqual([pool]);
  expect(filtered.pools[0]).toBe(before.pools[0]);
  expect(filtered.unbound).toEqual([unbound('codex'), unbound('claude')]);
  expect(filtered.unbound[0]?.windows[0]).toBe(before.unbound[0]?.windows[0]);
  expect(filtered.activeRuns.map((run) => run.agent)).toEqual([
    'codex',
    'claude',
  ]);
  expect(filtered.unavailable).toEqual([]);
  expect(filtered.preferences).toEqual(before.preferences);
  expect(filtered.warnings).toEqual([
    ...before.warnings,
    POOL_SCOPE_INCOMPLETE,
  ]);
  expect(before).toEqual(copy);
  expect(BudgetSnapshot.safeParse(filtered).success).toBe(true);
});

test('runtime spelling never establishes a provider or account mapping', () => {
  const before = { ...facts(), activeRuns: [] };
  const filtered = filterResourceFacts(before, ['codex', 'missing']);

  expect(filtered.pools).toEqual([]);
  expect(filtered.unbound).toEqual([unbound('codex')]);
  expect(filtered.unavailable).toEqual([
    {
      agent: 'missing',
      reason: 'No resource observations for this runtime; capacity unknown.',
    },
  ]);
  expect(filtered.warnings).toContain(POOL_SCOPE_INCOMPLETE);
  expect(filtered.observedAt).toBe(time);
});

test('runtime filter is bounded without rewriting supplied IDs', () => {
  expect(ResourceAgents.parse(['codex', 'codex', ' name '])).toEqual([
    'codex',
    'codex',
    ' name ',
  ]);

  for (const value of [
    [''],
    ['x'.repeat(129)],
    Array<string>(129).fill('codex'),
    'codex',
  ]) {
    expect(ResourceAgents.safeParse(value).success).toBe(false);
  }
});

test('full duplicate-source unavailability plus missing requested IDs stays within the public cap', () => {
  const requested = [
    'codex',
    ...Array.from({ length: 127 }, (_, i) => `missing-${i}`),
  ];
  const before = {
    ...facts(),
    pools: [],
    unbound: [],
    activeRuns: [],
    unavailable: Array.from({ length: 128 }, () => ({
      agent: 'codex',
      reason: 'Unsupported.',
    })),
  };
  const copy = structuredClone(before);

  expect(BudgetSnapshot.safeParse(before).success).toBe(true);

  const result = filterResourceFacts(before, requested);

  expect(result.unavailable).toHaveLength(128);
  expect(new Set(result.unavailable.map((one) => one.agent)).size).toBe(128);
  expect(result.unavailable[0]).toEqual({
    agent: 'codex',
    reason: 'Unsupported.',
  });
  expect(result.warnings).not.toContain(UNAVAILABLE_SCOPE_INCOMPLETE);
  expect(BudgetSnapshot.safeParse(result).success).toBe(true);
  expect(before).toEqual(copy);

  const distinct = filterResourceFacts(
    {
      ...before,
      unavailable: Array.from({ length: 128 }, (_, i) => ({
        agent: 'codex',
        reason: `Unavailable source ${i}.`,
      })),
    },
    requested,
  );

  expect(distinct.unavailable).toHaveLength(128);
  expect(distinct.warnings).toContain(UNAVAILABLE_SCOPE_INCOMPLETE);
  expect(BudgetSnapshot.safeParse(distinct).success).toBe(true);
});

describe('CHD-533 tester: filtered evidence boundaries', () => {
  test('dangling active references never make a provider-spelled pool usable', () => {
    const before = {
      ...facts(),
      unbound: [],
      unavailable: [],
      activeRuns: [active('codex', ['missing-ref'])],
    };
    const copy = structuredClone(before);
    const result = filterResourceFacts(before, ['codex']);

    expect(result.pools).toEqual([]);
    expect(result.activeRuns).toEqual(before.activeRuns);
    expect(result.unavailable).toEqual([
      {
        agent: 'codex',
        reason: 'No resource observations for this runtime; capacity unknown.',
      },
    ]);
    expect(result.warnings).toContain(POOL_SCOPE_INCOMPLETE);
    expect(BudgetSnapshot.safeParse(result).success).toBe(true);
    expect(before).toEqual(copy);
  });

  test('maximum runtime projection preserves cleanup and both coverage warnings under saturated input', () => {
    const agents = [
      'codex',
      ...Array.from({ length: 127 }, (_, i) => `runtime-${i}`.padEnd(128, 'x')),
    ];
    const before = {
      ...facts(),
      unbound: [],
      activeRuns: [],
      unavailable: [
        { agent: 'codex', reason: 'First source unavailable.' },
        { agent: 'codex', reason: 'Second source unavailable.' },
      ],
      warnings: [
        ...Array.from({ length: 255 }, (_, i) => `Original warning ${i}.`),
        RESOURCE_CLEANUP_FAILED,
      ],
    };
    const copy = structuredClone(before);
    const result = filterResourceFacts(before, ResourceAgents.parse(agents));

    expect(result.unavailable).toHaveLength(128);
    expect(result.warnings).toHaveLength(256);
    expect(new Set(result.warnings).size).toBe(256);
    expect(result.warnings).toContain(RESOURCE_CLEANUP_FAILED);
    expect(result.warnings).toContain(POOL_SCOPE_INCOMPLETE);
    expect(result.warnings).toContain(UNAVAILABLE_SCOPE_INCOMPLETE);
    expect(result.warnings).toContain(WARNINGS_OMITTED);
    expect(result.observedAt).toBe(before.observedAt);
    expect(result.preferences).toEqual(before.preferences);
    expect(BudgetSnapshot.safeParse(result).success).toBe(true);
    expect(before).toEqual(copy);
  });
});
