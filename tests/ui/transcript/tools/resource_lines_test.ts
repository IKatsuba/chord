import { describe, expect, test } from 'bun:test';
import assert from 'node:assert/strict';
import { resourceLines } from '../../../../src/ui/transcript/tools/resource_lines.ts';
import {
  summary,
  headline,
} from '../../../../src/ui/transcript/tools/tools.ts';
import { foldBudgetCache } from '../../../../src/platform/budget_cache.ts';
import { fixtureResourceRead } from '../../../../src/platform/resource_fixture.ts';
import type {
  BudgetSnapshot,
  TeamSelection,
} from '../../../../src/session/budgets.ts';

const wall = Date.parse('2026-10-27T13:00:00Z');

async function facts(preferences: TeamSelection = {}): Promise<BudgetSnapshot> {
  const result = await fixtureResourceRead(
    'codex',
    { sourceRef: 'hidden-source-ref', sessionRef: 'hidden-session-ref' },
    'partial',
    new AbortController().signal,
  );

  assert('observation' in result.facts);

  const observation = result.facts.observation;

  observation.windows[0]!.receivedAt = new Date(wall - 12000).toISOString();
  observation.windows[0]!.resetsAt = '2026-10-28T02:00:00Z';

  return foldBudgetCache(
    [
      {
        schemaVersion: 1,
        processRef: '00000000-0000-4000-8000-000000000001',
        writtenAt: new Date(wall).toISOString(),
        pools: [],
        unbound: [observation],
        unavailable: [],
        activeRuns: [],
      },
    ],
    preferences,
    { wall, monotonic: 0 },
  );
}

describe('Resources report', () => {
  test('independent partial values retain precision, unknown times/scope and date-aware UTC reset', async () => {
    const snapshot = await facts();
    const text = resourceLines(snapshot).join('\n');

    expect(text).toContain('Preferences: fixed');
    expect(text).toContain('Read: 13:00:00 UTC · advisory snapshot');
    expect(text).toContain(
      '5h: 12.345% used · reset 2026-10-28 02:00 UTC · models unknown',
    );
    expect(text).toContain(
      'Received 12s before read · provider freshness unknown',
    );
    expect(text).toContain(
      '7d: usage unknown · reset unknown · models unknown',
    );
    expect(text).toContain('identity unverified');
    expect(text).toContain('coverage unknown');
    expect(text).toContain('Warning:');
    expect(text).not.toContain('hidden-source-ref');
    expect(text).not.toContain('hidden-session-ref');
    expect(text).toContain(
      'Active work: none reported · external work may be missing',
    );
  });

  test('soft preference appears only for prefer and empty configured allowlists explicitly deny', async () => {
    const snapshot = await facts({
      intent: 'prefer',
      prefer: { agent: 'codex', model: 'long-model' },
      constraints: {
        agents: [],
        models: { codex: [] },
        modes: { codex: ['plan'] },
      },
    });

    expect(resourceLines(snapshot).slice(0, 4)).toEqual([
      'Preferences: prefer · codex / long-model',
      'Allowed agents: none',
      'Allowed models (codex): none',
      'Allowed modes (codex): plan',
    ]);

    snapshot.preferences.intent = 'balanced';

    expect(resourceLines(snapshot)[0]).toBe('Preferences: balanced');
  });

  test('pending requires explicit evidence; unavailable and lifecycle warnings stay visible and advisory', async () => {
    const snapshot = await facts();

    snapshot.unbound = [];

    expect(resourceLines(snapshot)).toContain(
      'No usable quota observations; capacity unknown.',
    );

    snapshot.unavailable = [
      { agent: 'codex', reason: 'Quota read pending; capacity unknown.' },
      { agent: 'claude', reason: 'Unsupported fixture version.' },
    ];
    snapshot.warnings = [
      'Resource collector cleanup failed; owned process exit is unverified.',
    ];

    expect(resourceLines(snapshot)).toContain(
      'codex: pending · capacity unknown',
    );
    expect(resourceLines(snapshot)).toContain(
      'claude: unavailable · Unsupported fixture version.',
    );
    expect(resourceLines(snapshot)).toContain(
      'Warning: Resource collector cleanup failed; owned process exit is unverified.',
    );
    expect(resourceLines({ raw: 'private raw provider response' })).toEqual([
      'No usable quota observations; capacity unknown.',
    ]);
  });

  test('a read-kind adapter cannot fold away any Resource report lines', async () => {
    const call = {
      id: 'resources',
      kind: 'read' as const,
      status: 'completed' as const,
      chord: { tool: 'get_budgets' as const, input: {}, answer: await facts() },
    };
    const drawn = summary(call, false, undefined, false, 80);

    expect(headline(call)).toEqual({ name: 'Resources' });
    expect(drawn.hidden).toBe(0);
    expect(drawn.lines.join('\n')).toContain('external work may be missing');
    expect(drawn.lines.length).toBeGreaterThan(10);
  });
});
