import { expect, test } from 'bun:test';
import chalk from 'chalk';
import stripAnsi from 'strip-ansi';
import type { ReactNode } from 'react';
import { Clip } from '../../../src/ui/app/Clip.tsx';
import { TEXT } from '../../../src/ui/theme/text.ts';
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

test('a clipping box laid out to no rows draws nothing of what it holds', async () => {
  const frame = await drawn(
    <box width={20} height={3}>
      <Clip flexGrow={1}>
        <text {...TEXT}>one</text>
        <text {...TEXT}>two</text>
      </Clip>
      <box flexShrink={0} height={3}>
        <text {...TEXT}>panel</text>
      </box>
    </box>,
    20,
    3,
  );

  expect(stripAnsi(frame).split('\n')).toStrictEqual(['panel']);
});
