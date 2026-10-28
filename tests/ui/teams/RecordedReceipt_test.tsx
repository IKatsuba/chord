import chalk from 'chalk';
import { DIM, runs } from '../../../src/ui/theme/text.ts';
import { describe, expect, test } from 'bun:test';
import assert from 'node:assert/strict';
import {
  freezeSelection,
  selectionReceipt,
} from '../../../src/session/team_selection.ts';
import { RecordedReceipt } from '../../../src/ui/teams/RecordedReceipt.tsx';
import { Colours } from '../../../src/ui/app/context.ts';
import { paletteOf } from '../../../src/ui/theme/theme.ts';
import { draw } from '../harness.tsx';

for (const columns of [80, 120]) {
  test(`owned historical receipt at ${columns} cells has no ACP marker or current success claim`, async () => {
    const frozen = freezeSelection(
      {
        description: 'Fixture',
        lead: { agent: 'fake', model: 'fake-small' },
        members: [],
        body: 'Keep instructions.',
      },
      {
        reason:
          'Preserve instructions and exact permissions; resource freshness remains unknown.',
      },
      {},
      ['fake'],
    );

    assert('frozen' in frozen);

    const initial = selectionReceipt(
      'actual-attempt',
      { name: 'fixture', place: 'project' },
      frozen.frozen,
    );
    const receipt = {
      ...initial,
      roles: initial.roles.map((role) => ({
        ...role,
        state: 'refused' as const,
        note: 'Cancelled before its first job; closing.',
      })),
    };
    const level = chalk.level;

    chalk.level = 3;

    let rendered: Awaited<ReturnType<typeof draw>> | undefined;

    try {
      rendered = await draw(
        <Colours.Provider value={paletteOf('dark', false)}>
          <RecordedReceipt
            historical
            width={columns}
            call={{
              tool: 'run_team',
              asked: receipt.runId,
              input: { job: 'Actual recorded job.' },
              answer: { id: receipt.runId, receipt },
              error: 'Actual recorded refusal.',
            }}
          />
        </Colours.Provider>,
        { columns, rows: 60 },
      );

      const frame = rendered.frame();

      expect(frame).toContain('Recorded Team receipt (fixture)');
      expect(frame).toContain('Recorded by Chord');
      expect(frame).toContain('current state unknown');
      expect(frame).toContain('historical observation');
      expect(frame).toContain('Actual at recording: refused');
      expect(frame).toContain('Recorded: time unknown');
      expect(frame).not.toContain('⏺');

      const styles = runs(frame);
      const provenance = styles.find((run) =>
        run.text.includes('Recorded by Chord'),
      );
      const reason = styles.find((run) => run.text.includes('Reason:'));

      assert(provenance !== undefined && reason !== undefined);
      expect(Boolean(provenance.attributes & DIM)).toBe(true);
      expect(Boolean(reason.attributes & DIM)).toBe(false);
    } finally {
      await rendered?.unmount();

      chalk.level = level;
    }
  });
}

describe('tester: historical decision reads in recorded receipt frames', () => {
  for (const columns of [80, 120]) {
    test(`keeps original read and warnings at ${columns} columns`, async () => {
      const frozen = freezeSelection(
        {
          description: 'Fixture',
          lead: { agent: 'fake' },
          members: [],
          body: '',
        },
        { reason: 'Preserve the original selection.' },
        {},
        ['fake'],
      );

      assert('frozen' in frozen);

      const receipt = {
        ...selectionReceipt(
          'historical-run',
          { name: 'fixture', place: 'project' },
          frozen.frozen,
        ),
        decisionRead: {
          readAt: '2026-10-27T13:40:00Z',
          observationRefs: ['original-observation'],
        },
        warnings: ['Original unavailable provider.'],
      };
      const rendered = await draw(
        <Colours.Provider value={paletteOf('dark', false)}>
          <RecordedReceipt
            historical
            width={columns}
            call={{
              tool: 'run_team',
              asked: receipt.runId,
              input: { team: 'fixture', job: 'Original recorded job.' },
              answer: { id: receipt.runId, receipt },
            }}
          />
        </Colours.Provider>,
        { columns, rows: 24 },
      );

      try {
        const frame = rendered.frame();

        expect(frame).toContain('Read 2026-10-27 13:40:00 UTC · advisory');
        expect(frame).toContain('Warning: Original unavailable provider.');
        expect(frame).toContain('Actual at recording: not opened');
        expect(frame).toContain('saved definition: fixture (project)');
        expect(frame).not.toContain('none recorded');
      } finally {
        await rendered.unmount();
      }
    });
  }
});
