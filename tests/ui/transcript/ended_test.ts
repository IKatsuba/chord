import { describe, expect, test } from 'bun:test';
import stringWidth from 'string-width';
import type { Entry } from '../../../src/session/transcript/types.ts';
import { endedLine } from '../../../src/ui/transcript/ended.ts';

type ItemEnded = Extract<Entry, { kind: 'item_ended' }>;

const ended = (more: Partial<ItemEnded>): ItemEnded => ({
  kind: 'item_ended',
  turnId: 't1',
  item: 'agent',
  name: 'Run the test suite',
  end: 'done',
  startedAt: 0,
  endedAt: 4000,
  ...more,
});

/** The line as it reads, its parts joined. */
const read = (more: Partial<ItemEnded>, width = 120) => {
  const line = endedLine(ended(more), width);

  return `${line.marker} ${line.name}${line.kind}${line.end}${
    line.reason === undefined ? '' : `: ${line.reason}`
  }`;
};

test("each end in the view's words, its marker and tone with it (CHD-479)", () => {
  expect(read({})).toStrictEqual('✓ Run the test suite · agent · done in 4s');
  expect(read({ end: 'failed', endedAt: 22_000 })).toStrictEqual(
    '✗ Run the test suite · agent · failed after 22s',
  );
  expect(read({ end: 'stopped', byPerson: true, endedAt: 43_000 })).toBe(
    '■ Run the test suite · agent · stopped with x after 43s',
  );
  expect(read({ end: 'stopped', endedAt: 30_000 })).toBe(
    '■ Run the test suite · agent · stopped after 30s',
  );
  expect(read({ end: 'ended', endedAt: 62_000 })).toBe(
    '■ Run the test suite · agent · ended after 1m 2s',
  );
  expect(read({ end: 'disconnected', endedAt: 240_000 })).toBe(
    '✗ Run the test suite · agent · disconnected after 4m',
  );
  expect(
    (['done', 'failed', 'stopped', 'ended', 'disconnected'] as const).map(
      (end) => endedLine(ended({ end }), 80).tone,
    ),
  ).toStrictEqual(['success', 'error', 'dim', 'dim', 'error']);
});

test("a failure's reason is its error's first line, cut to the width with …", () => {
  expect(
    read({ end: 'failed', endedAt: 22_000, error: 'tsc exited 2\nat line 4' }),
  ).toBe('✗ Run the test suite · agent · failed after 22s: tsc exited 2');

  const cut = read(
    { end: 'failed', endedAt: 22_000, error: 'x'.repeat(200) },
    60,
  );

  expect(cut.endsWith('…')).toBeTruthy();
  // The gutter's marker and its space stand beside the 60 cells.
  expect([...cut].length - 2).toStrictEqual(60);
});

test("a reason's cut keeps whole characters: wide, combined and joined ones (CHD-479)", () => {
  const segments = new Intl.Segmenter();

  for (const unit of ['語', 'é', '👩‍💻']) {
    const line = endedLine(
      ended({ end: 'failed', endedAt: 22_000, error: unit.repeat(80) }),
      60,
    );
    const reason = line.reason ?? '';
    const kept = [...segments.segment(reason)].map(({ segment }) => segment);

    expect(kept.at(-1), unit).toStrictEqual('…');
    expect(
      kept.slice(0, -1).every((segment) => segment === unit),
      unit,
    ).toBeTruthy();
    expect(
      stringWidth(`${line.name}${line.kind}${line.end}: ${reason}`),
      unit,
    ).toBeLessThanOrEqual(60);
  }
});

describe('CHD-479 tester: failure reason and stop edge cases', () => {
  test('ANSI in a failure cannot leak another line or spend the reason width', () => {
    for (const width of [40, 74, 114]) {
      const line = endedLine(
        ended({
          name: 'Check',
          end: 'failed',
          error: '\x1b[31m日本語👩‍💻'.repeat(50) + '\x1b[0m\nNEVER SHOWN',
        }),
        width,
      );
      const words = `${line.name}${line.kind}${line.end}: ${line.reason}`;

      expect(words).not.toContain('\x1b');
      expect(words).not.toContain('NEVER SHOWN');
      expect(stringWidth(words)).toBeLessThanOrEqual(width);
      expect(line.reason?.endsWith('…')).toBe(true);
    }
  });

  test('missing or reversed timestamps cannot invent a negative duration', () => {
    expect(
      endedLine(
        {
          kind: 'item_ended',
          turnId: 't1',
          item: 'agent',
          name: 'Run the test suite',
          end: 'stopped',
        },
        80,
      ).end,
    ).toBe('stopped');
    expect(read({ startedAt: 20, endedAt: 10 })).toBe(
      '✓ Run the test suite · agent · done in 0s',
    );
    expect(
      read({ end: 'failed', error: '\x1b[31m  \x1b[0m\nnot first' }),
    ).not.toContain(':');
  });

  test('a pending person stop does not relabel natural completion or failure', () => {
    expect(read({ byPerson: true })).toBe(
      '✓ Run the test suite · agent · done in 4s',
    );
    expect(read({ byPerson: true, end: 'failed' })).toBe(
      '✗ Run the test suite · agent · failed after 4s',
    );
    expect(read({ byPerson: true, end: 'ended' })).toBe(
      '■ Run the test suite · agent · stopped with x after 4s',
    );
  });
});
