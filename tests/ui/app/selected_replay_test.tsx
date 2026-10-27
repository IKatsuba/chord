import { expect, test } from 'bun:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { selectedReceiptFixture } from '../../fixtures/selected_receipt.ts';
import { readRecords } from '../../../src/session/sessions.ts';
import { readPast } from '../../../src/session/record.ts';
import { recordedSelection } from '../../../src/session/team_selection.ts';
import { recordedReceipts } from '../../../src/ui/teams/recorded_receipts.ts';
import { ready, send, until, withWindow } from './render.tsx';

for (const columns of [80, 120]) {
  test(`receipt-only replay at ${columns} columns shows actual recorded attempts without launching them`, async () => {
    const directory = await mkdtemp(join(tmpdir(), 'chord-selected-replay-'));
    const stateDir = join(directory, 'state');

    try {
      await selectedReceiptFixture(directory, stateDir);

      const [parent, ...others] = await readRecords(stateDir);

      assert(parent !== undefined);
      expect(others).toEqual([]);
      expect(parent.prompt).toBe('Team attempt: fixture');

      const past = await readPast(parent.path);

      expect(past.some((entry) => entry.type === 'prompt')).toBe(false);
      expect(
        past.some(
          (entry) =>
            entry.type === 'update' &&
            entry.update.sessionUpdate === 'tool_call',
        ),
      ).toBe(false);

      const ids = [
        ...new Set(
          past.flatMap((entry) =>
            entry.type === 'served'
              ? [recordedSelection(entry.call)?.runId].filter(
                  (id): id is string => id !== undefined,
                )
              : [],
          ),
        ),
      ];

      expect(ids).toHaveLength(2);

      let receipts = 0;

      await withWindow(
        async (window) => {
          await ready(window);
          await until('owned historical receipt mounted', () =>
            window.mounted('Recorded Team receipt (fixture)'),
          );
          expect(window.mounted('current state unknown')).toBe(true);
          expect(window.mounted('historical observation')).toBe(true);
          expect(window.mounted('Actual at recording: refused')).toBe(true);
          expect(window.pids).toHaveLength(1);
          expect(receipts).toBe(2);
          await send(window, `/team show ${ids[0]}`);
          expect(window.pids).toHaveLength(1);
          expect(window.mounted('Recorded Team receipt (fixture)')).toBe(true);
        },
        {
          columns,
          rows: 24,
          stateDir,
          runtimes: ['fake'],
          resume: {
            sessionId: parent.sessionId,
            cwd: directory,
            record: parent.path,
          },
          onState: (state) => {
            const transcript = state.sessions[state.front]?.transcript;

            if (transcript !== undefined) {
              receipts = recordedReceipts(transcript).length;
            }
          },
        },
      );
    } finally {
      await rm(directory, { recursive: true });
    }
  });
}
