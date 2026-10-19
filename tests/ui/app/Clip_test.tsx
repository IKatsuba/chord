import { expect, test } from 'bun:test';
import chalk from 'chalk';
import stripAnsi from 'strip-ansi';
import { type ReactNode, useEffect, useState } from 'react';
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

/** A clipping box above a panel that grows from two rows to three. */
function Squeezed() {
  const [tall, setTall] = useState(false);

  useEffect(() => {
    const timer = setTimeout(() => setTall(true), 50);

    return () => clearTimeout(timer);
  }, []);

  return (
    <box width={20} height={3}>
      <Clip flexGrow={1} flexShrink={1} flexBasis={0}>
        <text {...TEXT}>one-a</text>
        <text {...TEXT}>two-bb</text>
      </Clip>
      <box flexShrink={0} height={tall ? 3 : 2}>
        <text {...TEXT}>panel</text>
      </box>
    </box>
  );
}

test("a clipping box that goes from one row to none leaves nothing of what it held over what follows (the owner's Q57, CHD-158)", async () => {
  const app = await draw(<Squeezed />, { columns: 20, rows: 3 });

  try {
    // One row: something of what it holds.
    expect(stripAnsi(app.frame()).split('\n')[0]).not.toBe('panel');
    await new Promise((resolve) => setTimeout(resolve, 300));
    // None: the panel's row is the panel's alone.
    expect(stripAnsi(app.frame()).split('\n')[0]).toBe('panel');
  } finally {
    await app.unmount();
  }
});
