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
 * the rows a block starts and ends on; `byCell`, across `last`'s row a
 * cell at a time, as a terminal reports a pointer moving along it.
 */
async function drag(
  window: Window,
  first: string,
  last: string,
  byCell = false,
): Promise<string> {
  const rows = stripAnsi(window.frame()).split('\n');
  const from = rows.findIndex((row) => row.includes(first));
  const to = rows.findIndex((row) => row.includes(last));
  const end = rows[to]!.indexOf(last) + last.length;

  await window.press(left(rows[from]!.indexOf(first), from, 'down'));

  for (let y = from + 1; y < to; y++) {
    await window.press(left(3, y, 'drag'));
  }

  for (let x = byCell ? rows[to]!.indexOf(last) : end; x <= end; x++) {
    await window.press(left(x, to, 'drag'));
  }

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
        // Out of a nested item to the next outer one, OpenTUI widens the
        // selection a box level per pointer event, so the drag moves along
        // the row as a person's does (docs/decisions.md).
        expect(
          await drag(window, 'deeper still', 'a short item', true),
        ).toStrictEqual(`${ITEMS[2]}\na short item`);
      },
      { columns, rows: 40 },
    ));
}

const LONG_CODE =
  'bun dev chord --fake --qa capture && tmux capture-pane -t chord-qa -p > /tmp/screen.txt';

for (const columns of [80, 120]) {
  test(`a code box is OpenTUI's, and a drag over it copies the code alone at ${columns} columns`, () =>
    withWindow(
      async (window) => {
        await send(window, 'markdowncode');
        await window.shows('A paragraph after.');

        const frame = stripAnsi(window.frame());

        // The label sits one cell past the corner, as OpenTUI draws a title,
        // and widens a box whose code is narrower than it.
        expect(frame).toContain('┌─ typescript ─┐\n   │ x            │');
        expect(frame).toContain('┌─ sh ──────────┐');
        expect(
          frame.split('\n').every((row) => stringWidth(row) <= columns),
        ).toBe(true);
        // A line cut at the box's edge copies whole; a blank line stays.
        expect(await drag(window, 'bun dev chord', 'echo done')).toStrictEqual(
          `${LONG_CODE}\n\necho done`,
        );
        expect(
          await drag(window, 'A paragraph before', 'echo done'),
        ).toStrictEqual(
          `A paragraph before the code.\n \nx\n \n${LONG_CODE}\n\necho done`,
        );
        expect(
          await drag(window, 'a loose item with', 'bun dev check'),
        ).toStrictEqual('a loose item with a box:\n \nbun dev check');
      },
      { columns, rows: 40 },
    ));

  test(`a copy keeps the blank rows between a reply's blocks and a loose list's, each one space, at ${columns} columns`, () =>
    withWindow(
      async (window) => {
        await send(window, 'markdowncode');
        await window.shows('A paragraph after.');

        // Between top-level blocks, and between a loose list's items and an
        // item's blocks, a blank row copies as a line of one space (Q186).
        expect(
          await drag(window, 'echo done', 'A paragraph after.'),
        ).toStrictEqual(
          [
            'echo done',
            ' ',
            'a loose item',
            ' ',
            'a loose item with a box:',
            ' ',
            'bun dev check',
            ' ',
            'A paragraph after.',
          ].join('\n'),
        );
      },
      { columns, rows: 40 },
    ));

  test(`a tight list's items copy with no blank line between them at ${columns} columns`, () =>
    withWindow(
      async (window) => {
        await send(window, 'markdownwrap');
        await window.shows('break here.');

        expect(await drag(window, 'nine', 'marker shows')).toStrictEqual(
          'nine\nten, with a two-digit marker and text long enough to wrap so the hang under a wider marker shows',
        );
      },
      { columns, rows: 40 },
    ));
}

test("a loose list's blank rows are selected at the text column of the item below, and of an item's own text within it", async () => {
  const drawn = await draw(
    <Reply
      text={[
        '9. nine',
        '',
        '10. ten',
        '',
        '    - inner',
        '',
        '      more',
      ].join('\n')}
      width={40}
    />,
    { columns: 40, rows: 12 },
  );

  try {
    const rows = stripAnsi(drawn.frame()).split('\n');
    const from = rows.findIndex((row) => row.includes('nine'));
    const to = rows.findIndex((row) => row.includes('more'));

    await drawn.write(left(rows[from]!.indexOf('nine'), from, 'down'));

    for (let y = from + 1; y <= to; y++) {
      await drawn.write(left(39, y, 'drag'));
    }

    await drawn.write(left(39, to, 'up'));

    // A selected blank row keeps its highlighted space, so its last cell is
    // where the space sits.
    const shown = stripAnsi(drawn.frame()).split('\n');
    const blanks = shown
      .slice(from, to)
      .filter((row) => row.trim() === '')
      .map((row) => row.length - 1);

    // Under `10.` (4), between ten and its list (4), and inside `- inner`
    // (6); never at a marker's column.
    expect(blanks).toStrictEqual([4, 4, 6]);
  } finally {
    await drawn.unmount();
  }
});

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
  '\n \nSoft source joins, hard\nbreak stays.\n \nFinal paragraph.';

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
        const box = rows.findIndex((row) => row.includes('┌─ txt'));
        const last = rows.findIndex((row) => row.includes('11. Last item'));

        expect(rows[outer + 1]?.trim()).toBe('');
        expect(rows[paragraph]?.indexOf('Outer')).toBe(4);
        expect(rows[inner]?.indexOf('-')).toBe(4);
        expect(rows[inner + 1]?.trim()).toBe('');
        expect(rows[box]?.indexOf('┌')).toBe(6);
        expect(rows[last - 1]?.trim()).toBe('');
        expect(rows.every((row) => stringWidth(row) <= columns)).toBe(true);

        const copied = await selectBody(drawn, 'Outer item', columns);

        expect(copied).toBe(
          'Outer item\n \nOuter paragraph.\n \nInner item\n \n' +
            'code'.repeat(45) +
            '\n \nLast item',
        );
        expect(copied).not.toContain('│');
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

describe('CHD-396 U3 tester: native code selection boundaries', () => {
  for (const columns of [80, 120]) {
    test(`the copy key writes bare code at ${columns} columns`, () => {
      const { copies, copy } = clipboard();

      return withWindow(
        async (window) => {
          await send(window, 'markdowncode');
          await window.shows('A paragraph after.');
          expect(await drag(window, 'bun dev chord', 'echo done')).toBe(
            `${LONG_CODE}\n\necho done`,
          );
          expect(copies).toHaveLength(0);
          await window.press('\x03');
          await until(
            'the code copy to reach the clipboard',
            () => copies.length === 1,
          );
          expect(copies[0]?.text).toBe(`${LONG_CODE}\n\necho done`);
        },
        { columns, rows: 40, copy, copyOnSelect: false },
      );
    });

    test(`border and language-label drags start no selection at ${columns} columns`, async () => {
      for (const start of [0, 3]) {
        const drawn = await draw(
          <Reply text={'```txt\nalpha target omega\n```'} width={columns} />,
          { columns, rows: 24 },
        );

        try {
          expect(stripAnsi(drawn.frame())).toContain('┌─ txt');
          await drawn.write(left(start, 0, 'down'));
          await drawn.write(left(12, 1, 'drag'));
          await drawn.write(left(12, 1, 'up'));
          expect(drawn.selected()).toBe('');
        } finally {
          await drawn.unmount();
        }
      }
    });

    test(`partial code selection copies only the dragged characters at ${columns} columns`, async () => {
      const drawn = await draw(
        <Reply text={'```txt\nalpha target omega\n```'} width={columns} />,
        { columns, rows: 24 },
      );

      try {
        const rows = stripAnsi(drawn.frame()).split('\n');
        const row = rows.findIndex((line) =>
          line.includes('alpha target omega'),
        );
        const start = rows[row]!.indexOf('target');

        await drawn.write(left(start, row, 'down'));
        await drawn.write(left(start + 5, row, 'drag'));
        await drawn.write(left(start + 5, row, 'up'));
        expect(drawn.selected()).toBe('target');
      } finally {
        await drawn.unmount();
      }
    });

    test(`source trailing spaces survive but box padding does not at ${columns} columns`, async () => {
      const source = 'alpha  \nb\nlast   ';
      const drawn = await draw(
        <Reply text={'```txt\n' + source + '\n```'} width={columns} />,
        { columns, rows: 24 },
      );

      try {
        const rows = stripAnsi(drawn.frame()).split('\n');
        const first = rows.findIndex((row) => row.includes('alpha'));
        const last = rows.findIndex((row) => row.includes('last'));

        await drawn.write(left(2, first, 'down'));
        await drawn.write(left(columns - 1, first, 'drag'));
        await drawn.write(left(columns - 1, first + 1, 'drag'));
        await drawn.write(left(columns - 1, last, 'drag'));
        await drawn.write(left(columns - 1, last, 'up'));
        expect(drawn.selected()).toBe(source);
      } finally {
        await drawn.unmount();
      }
    });

    test(`fenced sent and received message bodies use bare-code copies at ${columns} columns`, async () => {
      const code = 'const value = ' + '1'.repeat(150) + ';\nreturn value;';
      const text = '```ts\n' + code + '\n```';

      for (const entry of [
        {
          kind: 'message' as const,
          turnId: 'u3',
          from: { name: 'parser', reachable: true as const },
          text,
        },
        {
          kind: 'tool' as const,
          turnId: 'u3',
          call: {
            id: 'u3-message',
            status: 'completed' as const,
            chord: {
              tool: 'send_message' as const,
              input: { to: 'parser', text },
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
          { columns, rows: 24 },
        );

        try {
          expect(stripAnsi(drawn.frame())).toContain('┌─ ts');
          expect(await selectBody(drawn, 'const value', columns)).toBe(code);
        } finally {
          await drawn.unmount();
        }
      }
    });
  }

  test('an open fence grows and its code reflows at narrow and wide widths', async () => {
    let update: (state: { text: string; width: number }) => void = () => {};

    function StreamingCode() {
      const [state, setState] = useState({ text: '```txt\nfirst', width: 80 });

      update = setState;

      return <Reply text={state.text} width={state.width} />;
    }

    const drawn = await draw(<StreamingCode />, { columns: 80, rows: 40 });
    const code = 'first ' + 'Z'.repeat(140) + '\nlast line';

    try {
      expect(stripAnsi(drawn.frame())).toContain('┌─ txt');
      expect(await selectBody(drawn, 'first', 80)).toBe('first');

      for (const columns of [80, 20, 120]) {
        update({ text: '```txt\n' + code, width: columns });
        await drawn.resize({ columns });
        await until('the open code fence to grow', async () => {
          await drawn.write('');

          return drawn.mounted('last line');
        });

        expect(await selectBody(drawn, 'first', columns)).toBe(code);
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

  for (const columns of [6, 12, 15, 16]) {
    test(`a typescript label fits only when its column has sixteen cells: ${columns}`, async () => {
      const drawn = await draw(
        <Reply text={'```typescript\nx\n```'} width={columns} />,
        { columns, rows: 12 },
      );

      try {
        const frame = stripAnsi(drawn.frame());

        expect(frame.includes('typescript')).toBe(columns === 16);
        expect(
          frame.split('\n').every((row) => stringWidth(row) <= columns),
        ).toBe(true);
        expect(await selectBody(drawn, 'x', columns)).toBe('x');
      } finally {
        await drawn.unmount();
      }
    });
  }
});
