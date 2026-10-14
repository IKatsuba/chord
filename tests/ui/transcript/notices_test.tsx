/** The notes a resumed past ends with: who was left open, what was running. */
import { expect, test } from 'bun:test';
import chalk from 'chalk';
import stripAnsi from 'strip-ansi';
import type { Entry } from '../../../src/session/transcript/types.ts';
import { TranscriptEntry } from '../../../src/ui/transcript/Transcript.tsx';
import { draw } from '../harness.tsx';

/**
 * The frame `entry` draws in, with colour on as a terminal has it, `width`
 * cells beside its gutter.
 */
async function frameOf(entry: Entry, width = 80): Promise<string> {
  const level = chalk.level;

  chalk.level = 3;

  try {
    const drawn = await draw(
      <TranscriptEntry
        entry={entry}
        turn={{ status: 'idle' }}
        agent='fake'
        expanded={false}
        width={width}
      />,
      { columns: 80, rows: 8 },
    );
    const frame = drawn.frame();

    await drawn.unmount();

    return frame;
  } finally {
    chalk.level = level;
  }
}

// A coloured run and its reset; a line erase and a hyperlink, which are not
// SGR, leave only their text.
const ESCAPED =
  '\x1b[31mred\x1b[0m\x1b[2K \x1b]8;;https://example.com\x07link\x1b]8;;\x07';

test("a monitor's escapes in what it was colour it, the rest go", async () => {
  const frame = await frameOf({
    kind: 'monitors_left',
    turnId: 't',
    monitors: [{ id: 'm', description: ESCAPED }],
  });

  expect(frame).toContain('\x1b[31mred');
  expect(stripAnsi(frame)).toContain(
    '⏺ red link was running when this session was left and is not restarted',
  );
  expect(stripAnsi(frame)).not.toMatch(/\[\d*[mK]|\]8;;/);
});

test("an agent's escapes in its saved name and runtime colour them, the rest go", async () => {
  const frame = await frameOf({
    kind: 'left_open',
    turnId: 't',
    agents: [{ name: ESCAPED, runtime: '\x1b[32mcodex\x1b[39m' }],
  });

  expect(frame).toContain('\x1b[31mred');
  expect(frame).toContain('\x1b[32mcodex');
  expect(stripAnsi(frame)).toContain('⏺ red link (codex)');
  expect(stripAnsi(frame)).not.toMatch(/\[\d*[mK]|\]8;;/);
});

test('the line closing a turn the agent started on its own hangs under what it drew, or stands alone, cut at 80 columns', async () => {
  const from = { name: 'main', reachable: true } as const;
  // The width an 80-column window gives the transcript, inset by 4.
  const under = stripAnsi(
    await frameOf(
      { kind: 'self_started', turnId: 't', from, alone: false },
      76,
    ),
  );
  const alone = stripAnsi(
    await frameOf({ kind: 'self_started', turnId: 't', from, alone: true }, 76),
  );

  expect(under).toContain(
    "⎿  Interrupted · the agent started this on its own; @main's message goes as…",
  );
  expect(under).not.toContain('⏺');
  expect(under).not.toContain('next turn');
  expect(alone).toContain(
    "⏺ Interrupted · the agent started this on its own; @main's message goes as th…",
  );
});
