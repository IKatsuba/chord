import { describe, expect, test } from 'bun:test';
import chalk from 'chalk';
import stripAnsi from 'strip-ansi';
import type { Entry } from '../../../src/session/transcript/types.ts';
import { Colours } from '../../../src/ui/app/context.ts';
import { paletteOf } from '../../../src/ui/theme/theme.ts';
import {
  noticeDescription,
  noticeMarker,
} from '../../../src/ui/transcript/notice.ts';
import { TranscriptEntry } from '../../../src/ui/transcript/Transcript.tsx';
import { draw } from '../harness.tsx';

/** The frame `entry` draws in at `columns`, in the dark theme's colours. */
async function frameOf(entry: Entry, columns = 80): Promise<string> {
  const level = chalk.level;

  chalk.level = 3;

  try {
    const drawn = await draw(
      <Colours.Provider value={paletteOf('dark', true)}>
        <TranscriptEntry
          entry={entry}
          turn={{ status: 'idle' }}
          agent='fake'
          expanded={false}
          width={columns - 4}
        />
      </Colours.Provider>,
      { columns, rows: 10 },
    );
    const frame = drawn.frame();

    await drawn.unmount();

    return frame;
  } finally {
    chalk.level = level;
  }
}

/** The frame's rows as text, their trailing blanks gone, empty rows out. */
function rowsOf(frame: string): string[] {
  return stripAnsi(frame)
    .split('\n')
    .map((row) => row.trimEnd())
    .filter((row) => row !== '');
}

test('a description folds each run of blank lines to one break', () => {
  expect(noticeDescription('one\n\n\ntwo\n \t\nthree\n')).toBe(
    'one\ntwo\nthree',
  );
});

test("info's marker is dim; warning's and error's take their role", () => {
  const colours = { warning: '#ffc107', error: '#ff6b80' };

  expect(noticeMarker('info', colours)).toBeUndefined();
  expect(noticeMarker('warning', colours)).toBe('#ffc107');
  expect(noticeMarker('error', colours)).toBe('#ff6b80');
});

test('a notice is its title by ⏺, its description under it at the text column, wrapped and never cut', async () => {
  const description =
    'The selected model does not support Auto mode; using Accept edits instead, until the model changes again.';
  const rows = rowsOf(
    await frameOf(
      {
        kind: 'notice',
        turnId: 't',
        severity: 'info',
        title: 'Auto mode unavailable',
        description,
      },
      60,
    ),
  );

  expect(rows[0]).toBe('⏺ Auto mode unavailable');
  expect(rows.slice(1).every((row) => row.startsWith('  '))).toBeTruthy();
  expect(rows.length).toBeGreaterThan(2);
  expect(
    rows
      .slice(1)
      .map((row) => row.trim())
      .join(' '),
  ).toBe(description);
});

const DIM = '\x1b[2m';

describe('CHD-629 tester: notice display boundaries', () => {
  async function noticeFrame(
    entry: Extract<Entry, { kind: 'notice' }>,
    theme: 'dark' | 'light',
    expanded: boolean,
  ): Promise<string> {
    const drawn = await draw(
      <Colours.Provider value={paletteOf(theme, true)}>
        <TranscriptEntry
          entry={entry}
          turn={{ status: 'idle' }}
          agent='fake'
          expanded={expanded}
          width={76}
        />
      </Colours.Provider>,
      { columns: 80, rows: 24 },
    );

    try {
      return drawn.frame();
    } finally {
      await drawn.unmount();
    }
  }

  for (const theme of ['dark', 'light'] as const) {
    test(`long title and description wrap without loss in ${theme}, expanded or folded`, async () => {
      const title = 'A long notice title that must stay readable. '.repeat(5);
      const description =
        'The selected model does not support this setting; use another model or choose an available setting. '.repeat(
          4,
        );
      const entry = {
        kind: 'notice',
        turnId: 't',
        severity: 'warning',
        title,
        description,
      } as const;
      const folded = rowsOf(await noticeFrame(entry, theme, false));
      const expanded = rowsOf(await noticeFrame(entry, theme, true));

      expect(expanded).toStrictEqual(folded);
      expect(folded.length).toBeGreaterThan(6);
      expect(folded.every((row) => row.length <= 80)).toBe(true);
      expect(folded.slice(1).every((row) => row.startsWith('  '))).toBe(true);
      expect(folded.join('').replace(/\s/g, '')).toBe(
        `⏺${title}${description}`.replace(/\s/g, ''),
      );
    });
  }

  test('agent escape sequences are rendered as text styling without raw control commands', async () => {
    const escaped =
      '\x1b[31mred\x1b[0m\x1b[2K \x1b]8;;https://example.com\x07link\x1b]8;;\x07';
    const rows = rowsOf(
      await noticeFrame(
        {
          kind: 'notice',
          turnId: 't',
          severity: 'error',
          title: escaped,
          description: `${escaped}\n\n\nFinal line`,
        },
        'dark',
        false,
      ),
    );

    expect(rows).toStrictEqual(['⏺ red link', '  red link', '  Final line']);
  });
});

for (const [severity, marker] of [
  ['info', `${DIM}⏺`],
  ['warning', '\x1b[38;2;255;193;7m⏺'],
  ['error', '\x1b[38;2;255;107;128m⏺'],
] as const) {
  test(`an ${severity} notice's ⏺ is ${severity === 'info' ? 'dim' : 'in its role'}, its text dim`, async () => {
    const frame = await frameOf({
      kind: 'notice',
      turnId: 't',
      severity,
      title: 'Fast mode turned off',
      description: 'Rate limit reached.',
    });

    expect(frame).toContain(marker);
    expect(frame).toContain(`${DIM}Fast mode turned off`);
    expect(frame).toContain(`${DIM}Rate limit reached.`);
  });
}
