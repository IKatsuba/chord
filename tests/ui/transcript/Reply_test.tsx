/**
 * A reply in the window as a person copies it: what OpenTUI wrapped joins
 * again in the copy, at any width (CHD-396).
 */
import { describe, expect, test } from 'bun:test';
import { useState } from 'react';
import stringWidth from 'string-width';
import { Reply } from '../../../src/ui/transcript/Reply.tsx';
import { TranscriptEntry } from '../../../src/ui/transcript/Transcript.tsx';
import { clipboard } from '../app/selecting.ts';
import { draw, type Drawn } from '../harness.tsx';
import stripAnsi from 'strip-ansi';
import { left, send, until, withWindow, type Window } from '../app/render.tsx';

const HEADING =
  'A heading long enough that at eighty columns it has to wrap onto a second row of its own';

const QUOTE =
  'A quote whose paragraph is long enough to wrap inside its bar at eighty columns, and at a hundred and twenty too, once it runs on.';

/**
 * What a drag copies from the first cell of `first` to the end of `last`,
 * the rows a block starts and ends on.
 */
async function drag(
  window: Window,
  first: string,
  last: string,
): Promise<string> {
  const rows = stripAnsi(window.frame()).split('\n');
  const from = rows.findIndex((row) => row.includes(first));
  const to = rows.findIndex((row) => row.includes(last));
  const end = rows[to]!.indexOf(last) + last.length;

  await window.press(left(rows[from]!.indexOf(first), from, 'down'));

  for (let y = from + 1; y < to; y++) {
    await window.press(left(3, y, 'drag'));
  }

  await window.press(left(end, to, 'drag'));
  await window.press(left(end, to, 'up'));

  return window.selected();
}

for (const columns of [80, 120]) {
  test(`a wrapped heading and quote copy as one line each at ${columns} columns`, () =>
    withWindow(
      async (window) => {
        await send(window, 'markdownwrap');
        await window.shows('break here.');

        // At 80 columns both wrap: the copy is the same as at 120.
        expect(await drag(window, 'A heading long', 'its own')).toStrictEqual(
          HEADING,
        );
        expect(await drag(window, 'A quote whose', 'runs on.')).toStrictEqual(
          QUOTE,
        );
      },
      { columns, rows: 40 },
    ));
}

/** Selects body rows, using terminal cells even when a row contains CJK. */
async function selectBody(drawn: Drawn, first: string, columns: number) {
  const rows = stripAnsi(drawn.frame()).split('\n');
  const from = rows.findIndex((row) => row.includes(first));
  const to = rows.findLastIndex((row) => row.trim().length > 0);
  const start = stringWidth(rows[from]!.slice(0, rows[from]!.indexOf(first)));
  const end = stringWidth(rows[to]!.trimEnd()) - 1;

  expect(from).toBeGreaterThanOrEqual(0);
  await drawn.write(left(start, from, 'down'));

  for (let y = from + 1; y < to; y++) {
    await drawn.write(left(columns - 1, y, 'drag'));
  }

  await drawn.write(left(end, to, 'drag'));
  await drawn.write(left(end, to, 'up'));

  return drawn.selected();
}

const TESTER_PARAGRAPH =
  'Opening tests/parse/printer_test.ts: inspect connection.ts, then retry ' +
  'https://example.com/a-long-path/file.ts and keep every punctuation mark. ' +
  '日本語の文章と広い文字も保存します。 ' +
  'Z'.repeat(170) +
  ' ending.';

const TESTER_BLOCKS =
  TESTER_PARAGRAPH +
  '\n\nSoft\nsource joins, hard  \nbreak stays.\n\nFinal paragraph.';

const TESTER_COPY =
  TESTER_PARAGRAPH +
  '\nSoft source joins, hard\nbreak stays.\nFinal paragraph.';

describe('CHD-396 tester: prose selection boundaries', () => {
  for (const columns of [80, 120]) {
    test(`paragraph punctuation, long words, CJK and source breaks copy exactly at ${columns} columns`, async () => {
      const drawn = await draw(<Reply text={TESTER_BLOCKS} width={columns} />, {
        columns,
        rows: 40,
      });

      try {
        expect(await selectBody(drawn, 'Opening', columns)).toBe(TESTER_COPY);
      } finally {
        await drawn.unmount();
      }
    });

    test(`the copy key keeps a source hard break at ${columns} columns`, () => {
      const { copies, copy } = clipboard();

      return withWindow(
        async (window) => {
          await send(window, 'markdownwrap');
          await window.shows('break here.');
          expect(await drag(window, 'Soft break', 'break here.')).toBe(
            'Soft break and a hard\nbreak here.',
          );
          expect(copies).toHaveLength(0);
          await window.press('\x03');
          await until(
            'the copy key to write the hard break',
            () => copies.length === 1,
          );
          expect(copies[0]?.text).toBe('Soft break and a hard\nbreak here.');
        },
        { columns, rows: 40, copy, copyOnSelect: false },
      );
    });

    test(`sent and received message bodies copy whole without furniture at ${columns} columns`, async () => {
      for (const entry of [
        {
          kind: 'message' as const,
          turnId: 'tester',
          from: { name: 'parser', reachable: true as const },
          text: TESTER_PARAGRAPH,
        },
        {
          kind: 'tool' as const,
          turnId: 'tester',
          call: {
            id: 'tester-message',
            status: 'completed' as const,
            chord: {
              tool: 'send_message' as const,
              input: { to: 'parser', text: TESTER_PARAGRAPH },
            },
          },
        },
      ]) {
        const drawn = await draw(
          <TranscriptEntry
            entry={entry}
            turn={{ status: 'idle' }}
            agent='fake'
            expanded={false}
            width={columns}
          />,
          { columns, rows: 40 },
        );

        try {
          expect(await selectBody(drawn, 'Opening', columns)).toBe(
            TESTER_PARAGRAPH,
          );
        } finally {
          await drawn.unmount();
        }
      }
    });
  }

  test('a growing paragraph reflows, copies its current text, then survives resize', async () => {
    let append: (text: string) => void = () => {};

    const partial = TESTER_PARAGRAPH.slice(0, 155);

    function StreamingReply() {
      const [text, setText] = useState(partial);

      append = setText;

      return <Reply text={text} width={80} />;
    }

    const drawn = await draw(<StreamingReply />, { columns: 80, rows: 24 });

    try {
      expect(await selectBody(drawn, 'Opening', 80)).toBe(partial);
      append(TESTER_PARAGRAPH);
      await until('the growing paragraph to render', async () => {
        await drawn.write('');

        return drawn.mounted(TESTER_PARAGRAPH);
      });

      expect(await selectBody(drawn, 'Opening', 80)).toBe(TESTER_PARAGRAPH);
      await drawn.resize({ columns: 120 });
      expect(await selectBody(drawn, 'Opening', 120)).toBe(TESTER_PARAGRAPH);
    } finally {
      await drawn.unmount();
    }
  });
});
