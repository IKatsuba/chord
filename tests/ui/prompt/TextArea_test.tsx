import { expect, test } from 'bun:test';
import chalk from 'chalk';
import stripAnsi from 'strip-ansi';
import type { ReactNode } from 'react';
import { TextAttributes } from '@opentui/core';
import {
  TextArea,
  type TextareaRenderable,
} from '../../../src/ui/prompt/TextArea.tsx';
import { TEXT } from '../../../src/ui/theme/text.ts';
import { until } from '../app/render.tsx';
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

// The search's highlight is drawn over the textarea as such a text.
test("a text wrapped by the cell keeps a textarea's rows, tabs, accents and joined emoji as well (CHD-306)", async () => {
  for (const text of [
    'say a\tauth and more after it',
    'say e\u0301 auth and more after it',
    'say 👩‍💻 auth and more after it',
    '日本語 auth\nand a line of its own',
  ]) {
    const typed = stripAnsi(
      await drawn(<TextArea initialValue={text} wrapMode='char' />, 9),
    );
    const drawnText = stripAnsi(
      await drawn(
        <text {...TEXT} flexGrow={1} wrapMode='char'>
          {text}
        </text>,
        9,
      ),
    );

    expect(drawnText).toStrictEqual(typed);
  }
});

// Measuring by grapheme, as the test renderer does, OpenTUI 0.5.17 started
// each run after a grapheme of several code points one cell late for each
// extra one (CHD-306); 0.6.0 does not (CHD-319).
test('a run after a decomposed accent, a joined emoji or a VS16 emoji starts on its own cell (CHD-319)', async () => {
  for (const before of ['say e\u0301 ', 'say 👩‍💻 ', 'say ⚠️ ']) {
    const row = (
      await drawn(
        <text {...TEXT}>
          {before}
          <span attributes={TextAttributes.INVERSE}>auth</span> done
        </text>,
        30,
        1,
      )
    ).split('\n')[0]!;

    expect(row).toStrictEqual(`${before}\x1b[7mauth\x1b[0m done`);
  }
});

test("a textarea's cursor is in the terminal's foreground, black in a light one (CHD-306)", async () => {
  let textarea: TextareaRenderable | null = null;
  const app = await draw(
    <TextArea
      ref={(own: TextareaRenderable | null) => void (textarea = own)}
      focused
    />,
  );

  // A light terminal as tmux answers: its colours asked for after its mode,
  // and no palette. OpenTUI's own cursor would stay white, all but hidden.
  await app.write('\x1b[?997;2n');
  await app.write(
    '\x1b]10;rgb:1111/2222/3333\x07\x1b]11;rgb:dddd/eeee/ffff\x07',
  );

  try {
    // The mode is heard after the key's frame, its colour drawn in the next.
    await until(
      'a black cursor',
      () => textarea!.cursorColor.toInts()[0] === 0,
      1_000,
    ).catch(() => {});

    expect(textarea!.cursorColor.toInts()).toStrictEqual([0, 0, 0, 255]);
  } finally {
    await app.unmount();
  }
});
