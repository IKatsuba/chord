import { describe, expect, test } from 'bun:test';
import assert from 'node:assert/strict';
import {
  confirmSelectionRole,
  freezeSelection,
  selectionReceipt,
  SelectionReceipt,
} from '../../../../src/session/team_selection.ts';
import { selectionLines } from '../../../../src/ui/transcript/tools/selection_lines.ts';

function receipt() {
  const chosen = freezeSelection(
    {
      description: 'Selection report',
      lead: { agent: 'codex', model: 'saved-model', mode: 'auto' },
      members: [
        {
          name: 'reviewer',
          role: 'Review',
          agent: 'claude',
          instructions: 'Keep permissions.',
        },
      ],
      body: 'Unchanged instructions.',
    },
    {
      reason: 'Preserve permissions; capacity is unknown.',
      lead: { model: 'chosen-model' },
    },
    {},
    ['codex', 'claude'],
  );

  assert('frozen' in chosen);

  return selectionReceipt(
    'actual-run-id',
    { name: 'fixture', place: 'project' },
    chosen.frozen,
  );
}

describe('frozen selection report lines', () => {
  test('collapsed report keeps reason, all uncertainty, composition and unknown unopened state', () => {
    const shown = selectionLines(receipt()).join('\n');

    expect(shown).toContain('Selection: agent-selected · this run');
    expect(shown).toContain(
      'Reason: Preserve permissions; capacity is unknown.',
    );
    expect(shown).not.toContain('Warning:');
    expect(shown).not.toContain('Read');
    expect(shown).toContain('lead (lead): codex · model chosen-model');
    expect(shown).toContain('reviewer: claude');
    expect(shown).toContain('agent default (unconfirmed)');
    expect(shown).toContain('Actual: not opened · configuration unconfirmed');
    expect(shown).not.toContain('saved-model');
  });

  test('expanded report distinguishes saved values, exact changes and actual observed fields', () => {
    const source = receipt();
    const role = source.roles[0]!;
    const shown = selectionLines(
      {
        ...source,
        roles: [
          confirmSelectionRole(role, {
            model: 'chosen-model',
            mode: 'auto',
            effort: null,
          }),
          source.roles[1],
        ],
      },
      true,
    ).join('\n');

    expect(shown).toContain('saved definition: fixture (project)');
    expect(shown).toContain('lead saved: codex · model saved-model');
    expect(shown).toContain('Changes from saved: model');
    expect(shown).toContain(
      'Actual: confirmed · session runtime unknown · model chosen-model · effort unknown · mode auto',
    );
    expect(shown).not.toContain('effort confirmed');
  });

  test('refused mode and soft effort notes remain visible with long warning text whole', () => {
    const source = receipt();
    const warning = 'Long source uncertainty '.repeat(15).trim();
    const shown = selectionLines({
      ...source,
      warnings: [warning],
      roles: [
        confirmSelectionRole(source.roles[0]!, {
          model: 'chosen-model',
          mode: 'plan',
          effort: null,
        }),
        source.roles[1],
      ],
    }).join('\n');

    expect(shown).toContain(`Warning: ${warning}`);
    expect(shown).toContain('Actual: refused');
    expect(shown).toContain('did not confirm the requested mode auto');
  });

  test('invalid or historical absent receipt adds no invented composition', () => {
    expect(selectionLines(undefined)).toEqual([]);
    expect(selectionLines({ schemaVersion: 8 })).toEqual([]);
  });
});

describe('tester: historical resource reads in selection receipts', () => {
  for (const recorded of [false, true]) {
    for (const expanded of [false, true]) {
      test(`retains the original read and warnings when recorded=${recorded}, expanded=${expanded}`, () => {
        const historical = {
          ...receipt(),
          decisionRead: {
            readAt: '2026-10-27T13:40:00Z',
            observationRefs: ['original-observation'],
          },
          warnings: ['Original unavailable provider.', 'Original stale read.'],
        };
        const parsed = SelectionReceipt.parse(
          JSON.parse(JSON.stringify(historical)),
        );
        const shown = selectionLines(parsed, expanded, recorded);

        expect(parsed).toEqual(historical);
        expect(shown).toContain('Read 2026-10-27 13:40:00 UTC · advisory');
        expect(shown.filter((line) => line.startsWith('Warning:'))).toEqual([
          'Warning: Original unavailable provider.',
          'Warning: Original stale read.',
        ]);
        expect(shown).toContain(
          `${recorded ? 'Actual at recording' : 'Actual'}: not opened · configuration unconfirmed`,
        );
        expect(shown.includes('ctrl+o for saved definition and changes')).toBe(
          !expanded,
        );
        expect(
          shown.some((line) => line.includes('saved definition: fixture')),
        ).toBe(expanded);
        expect(historical.decisionRead.observationRefs).toEqual([
          'original-observation',
        ]);
      });
    }
  }
});
