import { describe, expect, test } from 'bun:test';
import { resourceLines } from '../../../../src/ui/transcript/tools/resource_lines.ts';
import {
  summary,
  headline,
} from '../../../../src/ui/transcript/tools/tools.ts';
import type { Budgets } from '../../../../src/session/budgets.ts';

function budgets(): Budgets {
  return {
    readAt: '2026-10-27T13:00:00.000Z',
    providers: [
      {
        agent: 'claude',
        windows: [
          {
            name: 'five_hour',
            usedPercent: 12.345,
            windowSeconds: 18000,
            resetsAt: '2026-10-27T18:05:00.000Z',
            models: null,
          },
          {
            name: 'model_scoped',
            usedPercent: 8,
            windowSeconds: 604800,
            resetsAt: '2026-11-02T09:00:00.000Z',
            models: ['opus'],
          },
          {
            name: 'codex.secondary',
            usedPercent: null,
            windowSeconds: null,
            resetsAt: null,
            models: [],
          },
        ],
      },
      { agent: 'gemini', windows: [] },
      { agent: 'codex', unavailable: 'Timed out after 10 s.' },
    ],
  };
}

describe('Resources report', () => {
  test('a line per window, then providers with no windows or not read, in the answer order', () => {
    expect(resourceLines(budgets())).toEqual([
      'Read: 13:00:00 UTC · advisory snapshot',
      'claude · 5h: 12.345% used · reset 18:05 UTC · models unknown',
      'claude · 7d: 8% used · reset 2026-11-02 09:00 UTC · models opus',
      'claude · codex.secondary: usage unknown · reset unknown · models none',
      'gemini: no windows reported',
      'codex: unavailable · Timed out after 10 s.',
    ]);
  });

  test('no providers read and an answer of an older format', () => {
    expect(
      resourceLines({ readAt: '2026-10-27T13:00:00.000Z', providers: [] }),
    ).toEqual(['Read: 13:00:00 UTC · advisory snapshot', 'No providers read.']);
    expect(
      resourceLines({
        schemaVersion: 1,
        observedAt: '2026-10-27T13:00:00Z',
        pools: [],
        unbound: [],
        unavailable: [],
        activeRuns: [],
        warnings: [],
        preferences: {},
      }),
    ).toEqual(['Recorded in an older format; not shown.']);
  });

  test('a read-kind adapter cannot fold away any Resource report lines', () => {
    const call = {
      id: 'resources',
      kind: 'read' as const,
      status: 'completed' as const,
      chord: { tool: 'get_budgets' as const, input: {}, answer: budgets() },
    };
    const drawn = summary(call, false, undefined, false, 80);

    expect(headline(call)).toEqual({ name: 'Resources' });
    expect(drawn.hidden).toBe(0);
    expect(drawn.lines.join('\n')).toContain('codex: unavailable');
  });
});
