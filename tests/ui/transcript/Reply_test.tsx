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

/** The three nested items of the first list, as written. */
const ITEMS = [
  'package.json:3: the package @chorded/chord at version 0.54.1 needs Bun 1.4.2 or newer. check runs check:static and then the tests.',
  'a nested item long enough to wrap at eighty columns, whose wrapped lines should hang under its own text',
  'deeper still, a numbered item that also runs past the edge of the window so its hang shows too',
];

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
  test(`a wrapped heading, quote and list item copy as one line each at ${columns} columns`, () =>
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
        // A list copies an item a line, whole, with no marker or indent.
        expect(
          await drag(window, 'package.json:3', 'its hang shows too'),
        ).toStrictEqual(ITEMS.join('\n'));
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

describe('CHD-396 tester: list layout and selection', () => {
  for (const columns of [80, 120]) {
    test(`ordered start numbers and task markers never select or copy at ${columns} columns`, async () => {
      const ordered = [
        'Ordered first ' + TESTER_PARAGRAPH,
        'Ordered second with 日本語 and an ending.',
        'Ordered third ' + TESTER_PARAGRAPH,
      ];
      const task = ['Open task ' + TESTER_PARAGRAPH, 'Done task ending.'];

      for (const [text, items, markers] of [
        [
          ordered.map((item, index) => `${98 + index}. ${item}`).join('\n'),
          ordered,
          ['98.', '99.', '100.'],
        ],
        [`- [ ] ${task[0]}\n- [x] ${task[1]}`, task, ['[ ]', '[x]']],
      ] as const) {
        const drawn = await draw(<Reply text={text} width={columns} />, {
          columns,
          rows: 40,
        });

        try {
          const rows = stripAnsi(drawn.frame()).split('\n');

          for (const marker of markers) {
            expect(rows.some((row) => row.startsWith(marker))).toBe(true);
          }

          // A drag beginning on the first marker must start no selection.
          await drawn.write(left(0, 0, 'down'));
          await drawn.write(left(columns - 1, 1, 'drag'));
          await drawn.write(left(columns - 1, 1, 'up'));
          expect(drawn.selected()).toBe('');

          expect(await selectBody(drawn, items[0]!.slice(0, 10), columns)).toBe(
            items.join('\n'),
          );
        } finally {
          await drawn.unmount();
        }
      }
    });

    test(`loose nested items retain blank rows and code boxes fit their content column at ${columns} columns`, async () => {
      const text = [
        '10. Outer item',
        '',
        '    Outer paragraph.',
        '',
        '    - Inner item',
        '',
        '      ```txt',
        '      ' + 'code'.repeat(45),
        '      ```',
        '',
        '11. Last item',
      ].join('\n');
      const drawn = await draw(<Reply text={text} width={columns} />, {
        columns,
        rows: 40,
      });

      try {
        const rows = stripAnsi(drawn.frame()).split('\n');
        const outer = rows.findIndex((row) => row.includes('10. Outer item'));
        const paragraph = rows.findIndex((row) =>
          row.includes('Outer paragraph.'),
        );
        const inner = rows.findIndex((row) => row.includes('- Inner item'));
        const box = rows.findIndex((row) => row.includes('┌ txt'));
        const last = rows.findIndex((row) => row.includes('11. Last item'));

        expect(rows[outer + 1]?.trim()).toBe('');
        expect(rows[paragraph]?.indexOf('Outer')).toBe(4);
        expect(rows[inner]?.indexOf('-')).toBe(4);
        expect(rows[inner + 1]?.trim()).toBe('');
        expect(rows[box]?.indexOf('┌')).toBe(6);
        expect(rows[last - 1]?.trim()).toBe('');
        expect(rows.every((row) => stringWidth(row) <= columns)).toBe(true);

        const copied = await selectBody(drawn, 'Outer item', columns);

        expect(copied).toContain('Outer paragraph.\nInner item\n┌ txt');
        expect(copied).toContain('│');
        expect(copied).not.toContain('10.');
        expect(copied).not.toContain('11.');
        expect(copied.endsWith('Last item')).toBe(true);
      } finally {
        await drawn.unmount();
      }
    });
  }

  test('a streaming list item grows, reflows on narrow resize and keeps its joined copy', async () => {
    let update: (state: { text: string; width: number }) => void = () => {};

    function StreamingList() {
      const [state, setState] = useState({
        text: '10. First partial',
        width: 80,
      });

      update = setState;

      return <Reply text={state.text} width={state.width} />;
    }

    const drawn = await draw(<StreamingList />, { columns: 80, rows: 40 });
    const items = [
      'First item has 日本語 and a long ending.',
      'Nested item ends.',
    ];
    const text = `10. ${items[0]}\n    - ${items[1]}`;

    try {
      expect(await selectBody(drawn, 'First partial', 80)).toBe(
        'First partial',
      );

      for (const columns of [80, 20, 120]) {
        update({ text, width: columns });
        await drawn.resize({ columns });
        await until('the list to grow', async () => {
          await drawn.write('');

          return drawn.mounted(items[1]!);
        });

        expect(await selectBody(drawn, 'First', columns)).toBe(
          items.join('\n'),
        );
        expect(
          stripAnsi(drawn.frame())
            .split('\n')
            .every((row) => stringWidth(row) <= columns),
        ).toBe(true);
      }
    } finally {
      await drawn.unmount();
    }
  });
});

describe('CHD-396 tester: task list in the fake window', () => {
  for (const columns of [80, 120]) {
    test(`both task bodies copy at ${columns} columns`, () =>
      withWindow(
        async (window) => {
          await send(window, 'markdownwrap');
          await window.shows('break here.');
          expect(await drag(window, 'open task', 'done task')).toBe(
            'open task\ndone task',
          );
        },
        { columns, rows: 40, copyOnSelect: false },
      ));
  }
});
