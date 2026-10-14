import { expect, test } from 'bun:test';
import chalk from 'chalk';
import stripAnsi from 'strip-ansi';
import type { ReactNode } from 'react';
import { Ansi } from '../../../src/ui/theme/Ansi.tsx';
import { DIM, TEXT } from '../../../src/ui/theme/text.ts';
import { draw } from '../harness.tsx';

/** What `node` draws in a terminal of `columns` × `rows`, escapes kept. */
async function drawn(node: ReactNode, columns = 20, rows = 6): Promise<string> {
  // chalk sees no terminal under test, and the harness writes no escapes
  // while it sees none.
  const level = chalk.level;

  chalk.level = 3;

  try {
    const app = await draw(node, { columns, rows });
    const frame = app.frame();

    await app.unmount();

    return frame;
  } finally {
    chalk.level = level;
  }
}

test('a dim text stays dim after a bold run its string closes (CHD-279)', async () => {
  chalk.level = 3;

  const styled = `a ${chalk.bold('bold')} after`;

  chalk.level = 0;

  const frame = await drawn(
    <text {...TEXT} attributes={DIM}>
      <Ansi text={styled} />
    </text>,
  );

  expect(frame).toContain('\x1b[1m\x1b[2mbold');
  expect(frame).toContain('\x1b[2m after');
});

test("a string's escapes other than its colours and weights are left out", async () => {
  const frame = await drawn(
    <text {...TEXT}>
      <Ansi
        text={'\x1b]8;;https://example.com\x07link\x1b]8;;\x07 \x1b[2Kend'}
      />
    </text>,
  );

  expect(stripAnsi(frame)).toStrictEqual('link end');
});

test("a string's colours are its own, however its SGR writes them", async () => {
  const frame = await drawn(
    <text {...TEXT}>
      <Ansi
        text={
          '\x1b[38;2;127;224;232ma\x1b[39m\x1b[38;2;1;2;3;1mb\x1b[0m' +
          '\x1b[38:2::4:5:6mc\x1b[38:5:9md\x1b[0m'
        }
      />
    </text>,
  );

  expect(frame).toContain('\x1b[38;2;127;224;232ma');
  expect(frame).toContain('\x1b[1m\x1b[38;2;1;2;3mb');
  expect(frame).toContain('\x1b[38;2;4;5;6mc');
  expect(frame).toContain('\x1b[91md');
});
