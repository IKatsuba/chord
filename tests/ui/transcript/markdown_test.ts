import { describe, expect, test } from 'bun:test';
import { execFile } from 'node:child_process';
import process from 'node:process';
import { promisify } from 'node:util';
import stringWidth from 'string-width';
import stripAnsi from 'strip-ansi';
import {
  type Code,
  codeBlocks,
  markdown,
  QUOTE_INSET,
  runCommand,
  type Soft,
  softMarkdown,
} from '../../../src/ui/transcript/markdown.ts';
import { PALETTES } from '../../../src/ui/theme/theme.ts';
import {
  MARKDOWN_LINES,
  MARKDOWN_OPEN_FENCE,
  MARKDOWN_OPEN_NESTED_FENCE,
  MARKDOWN_REPLY,
} from '../../fixtures/markdown.ts';

function lines(text: string, width: number): string[] {
  return markdown(text, width, false).flatMap((block) =>
    block.text.split('\n'),
  );
}

test('markdown marks give way to what they mean', () => {
  const shown = lines(MARKDOWN_REPLY, 116).join('\n');

  for (const mark of ['**', '# ', '`', '```', '](', '| ---']) {
    expect(!shown.includes(mark), `"${mark}" is on screen`).toBeTruthy();
  }

  expect(shown.includes('Reading the session layer')).toBeTruthy();
  expect(shown.includes('Start with src/session/session.ts')).toBeTruthy();
  expect(
    shown.includes('ACP spec (https://agentclientprotocol.com)'),
  ).toBeTruthy();
});

test('each block is apart from the next', () => {
  const blocks = markdown('One.\n\nTwo.\n\n- a\n- b\n\nThree.', 40, false);

  expect(blocks.map((block) => block.text)).toStrictEqual([
    'One.',
    'Two.',
    '- a\n- b',
    'Three.',
  ]);
});

test('a nested list keeps its indent, and a wrapped item hangs', () => {
  const shown = lines('- a long item that has to wrap\n  1. nested', 20);

  expect(shown).toStrictEqual([
    '- a long item that',
    '  has to wrap',
    '  1. nested',
  ]);
});

test('a quote is set apart for its bar, and wraps once inside it', () => {
  const text = 'A quote long enough to wrap at this width once.';
  const [block] = markdown(`> ${text}`, 22 + QUOTE_INSET, false);

  expect(block?.quote).toStrictEqual(true);
  expect(block?.text.split('\n')).toStrictEqual([
    'A quote long enough',
    'to wrap at this width',
    'once.',
  ]);
});

// markdansi does not wrap a heading; one longer than the window is Ink's to
// wrap.
test('no line runs past the width, down to a narrow window', () => {
  for (const width of [116, 76, 40]) {
    for (const line of lines(MARKDOWN_REPLY, width)) {
      expect(stringWidth(line) <= width, `${width}: "${line}"`).toBeTruthy();
    }
  }
});

test('a table cell wraps in its column while the table fits', () => {
  const shown = lines(MARKDOWN_REPLY, 76).join('\n');

  expect(shown.includes('│ session.ts    │ opening, prompting')).toBeTruthy();
  expect(
    shown.includes('│               │ and closing a session'),
  ).toBeTruthy();
  expect(!shown.includes('…')).toBeTruthy();
});

test('a table too narrow to wrap cuts its cells instead', () => {
  const table = markdown(MARKDOWN_REPLY, 40, false)
    .find((block) => block.text.includes('┬'))!
    .text.split('\n')
    .filter((line) => line.startsWith('│'));

  expect(table.some((line) => line.includes('session…'))).toBeTruthy();
  // One row per line: no word pushed a border out of its column.
  expect(new Set(table.map((line) => line.indexOf('│', 1))).size).toStrictEqual(
    1,
  );
});

test('an open code fence mid-stream draws as code to the end', () => {
  const partial = MARKDOWN_LINES.slice(0, MARKDOWN_OPEN_FENCE).join('\n');
  const blocks = markdown(partial, 76, false);
  const code = blocks.at(-1)!.text.split('\n');

  expect(code.length).toStrictEqual(3);
  expect(code[0]!.startsWith('┌ ts ─')).toBeTruthy();
  expect(
    code[1]!.includes(
      "const session = await openSession({ agent: 'claude', cwd });",
    ),
  ).toBeTruthy();
  expect(code[2]!.startsWith('└')).toBeTruthy();
  // The blocks before it are as they will be once the reply is whole.
  expect(blocks.slice(0, -1)).toStrictEqual(
    markdown(MARKDOWN_REPLY, 76, false).slice(0, blocks.length - 1),
  );
});

test('a code block of one line is boxed, with its language', () => {
  expect(
    lines('Run:\n\n```sh\ndeno task check\n```\n\ndone', 40),
  ).toStrictEqual([
    'Run:',
    '┌ sh ─────────────┐',
    '│ deno task check │',
    '└─────────────────┘',
    'done',
  ]);
});

test('a fence just opened is already a box', () => {
  expect(lines('```ts\n', 40)).toStrictEqual([
    '┌ ts ──┐',
    '│      │',
    '└──────┘',
  ]);
  expect(lines('```\nls', 40)).toStrictEqual(['┌────┐', '│ ls │', '└────┘']);
});

test('a code block in a list is boxed under its item', () => {
  const text = [
    '1. Run the checks:',
    '   ```sh',
    '   deno task check',
    '   ```',
    '2. Commit once every check has passed.',
  ].join('\n');

  expect(lines(text, 24)).toStrictEqual([
    '1. Run the checks:',
    '  ┌ sh ─────────────┐',
    '  │ deno task check │',
    '  └─────────────────┘',
    '2. Commit once every',
    '  check has passed.',
  ]);
});

test('a code block in a list wraps in the width beside its indent', () => {
  expect(
    lines('- a\n\n  ```\n  ' + 'x'.repeat(10) + '\n  ```', 12),
  ).toStrictEqual([
    '- a',
    '  ┌────────┐',
    '  │ xxxxxx │',
    '  │ xxxx   │',
    '  └────────┘',
  ]);
});

test("a fence on its bullet's line is boxed from the bullet", () => {
  expect(lines('1. ```sh\n   ls\n   ```\n2. done', 40)).toStrictEqual([
    '1. ┌ sh ──┐',
    '   │ ls   │',
    '   └──────┘',
    '2. done',
  ]);
});

test('each box in a list holds its own code, fences in code kept', () => {
  const text = [
    '- item',
    '',
    '      ```sh',
    '      literal',
    '      ```',
    '',
    '  ```sh',
    '  actual',
    '  ```',
  ].join('\n');

  expect(lines(text, 40).filter((line) => line.trim() !== '')).toStrictEqual([
    '- item',
    '  ┌─────────┐',
    '  │ ```sh   │',
    '  │ literal │',
    '  │ ```     │',
    '  └─────────┘',
    '  ┌ sh ────┐',
    '  │ actual │',
    '  └────────┘',
  ]);
});

test('indented code is boxed, in a list and at the top', () => {
  const box = ['┌───────┐', '│ alpha │', '│ beta  │', '└───────┘'];

  expect(lines('- item\n\n      alpha\n      beta', 40)).toStrictEqual([
    '- item',
    ...box.map((row) => `  ${row}`),
  ]);
  expect(lines('    alpha\n    beta', 40)).toStrictEqual(box);
});

test('code in a quote in a list is boxed inside the bar', () => {
  expect(lines('- a\n\n  > ```sh\n  > q1\n  > q2\n  > ```', 40)).toStrictEqual([
    '- a',
    '  │ ┌ sh ──┐',
    '  │ │ q1   │',
    '  │ │ q2   │',
    '  │ └──────┘',
  ]);
});

test('a list of only code blocks boxes each one', () => {
  expect(lines('- ```sh\n  a\n  ```\n- ```sh\n  b\n  ```', 40)).toStrictEqual([
    '┌ sh ──┐',
    '│ a    │',
    '└──────┘',
    '┌ sh ──┐',
    '│ b    │',
    '└──────┘',
  ]);
});

test('a fence in a list that is still open is a box to the end', () => {
  const partial = MARKDOWN_LINES.slice(0, MARKDOWN_OPEN_NESTED_FENCE).join(
    '\n',
  );
  const blocks = markdown(partial, 76, false);

  expect(blocks.at(-1)?.text.split('\n')).toStrictEqual([
    '1. Run the checks:',
    '  ┌ sh ─────────────┐',
    '  │ deno task check │',
    '  └─────────────────┘',
  ]);
  expect(lines('- a\n  ```sh\n', 40)).toStrictEqual([
    '- a',
    '  ┌ sh ──┐',
    '  │      │',
    '  └──────┘',
  ]);
});

test('code wraps inside its box, and keeps its blank lines', () => {
  expect(lines('```\n\n' + 'x'.repeat(12) + '\n\n```', 10)).toStrictEqual([
    '┌────────┐',
    '│        │',
    '│ xxxxxx │',
    '│ xxxxxx │',
    '│        │',
    '└────────┘',
  ]);
});

test('an H1 is underlined as well as bold, an H2 only bold', () => {
  const [one, two] = markdown('# One\n\n## Two', 40, true);

  expect(one?.text).toStrictEqual('\x1b[1m\x1b[4mOne\x1b[24m\x1b[22m');
  expect(two?.text).toStrictEqual('\x1b[1mTwo\x1b[22m');
});

test('table and code borders are dim, a header stays bold', () => {
  const [table, code] = markdown(
    '| a |\n|---|\n| b |\n\n```txt\nls\n```',
    40,
    true,
  ).map((block) => block.text.split('\n'));

  expect(table?.[0]).toStrictEqual('\x1b[2m┌────┐\x1b[22m');
  expect(table?.[1]).toStrictEqual(
    '\x1b[2m│\x1b[22m\x1b[1m a  \x1b[22m\x1b[2m│\x1b[22m',
  );
  expect(code?.[0]).toStrictEqual('\x1b[2m┌ txt ──┐\x1b[22m');
  expect(code?.[1]).toStrictEqual('\x1b[2m│\x1b[22m ls    \x1b[2m│\x1b[22m');

  const [list] = markdown('- a\n  ```txt\n  ls\n  ```', 40, true);

  expect(list?.text.split('\n').slice(1)).toStrictEqual([
    '  \x1b[2m┌ txt ──┐\x1b[22m',
    '  \x1b[2m│\x1b[22m ls    \x1b[2m│\x1b[22m',
    '  \x1b[2m└───────┘\x1b[22m',
  ]);
});

test('markdown cut mid-span stays as typed until its pair arrives', () => {
  expect(lines('Some **bol', 40)).toStrictEqual(['Some **bol']);
  expect(lines('Some **bold**', 40)).toStrictEqual(['Some bold']);
});

test('colour is left out when asked, and put in when asked', () => {
  expect(markdown('**bold**', 40, false)[0]?.text).toStrictEqual('bold');
  expect(
    markdown('**bold**', 40, true)[0]?.text.includes('\x1b[1m'),
  ).toBeTruthy();
});

test('a reference link resolves once its definition streams in', () => {
  const reply = 'See [docs][ref].\n\n> and [the quote][ref]\n\n';

  expect(lines(reply, 40)).toStrictEqual([
    'See [docs][ref].',
    'and [the quote][ref]',
  ]);
  expect(lines(`${reply}[ref]: https://example.org`, 40)).toStrictEqual([
    'See docs (https://example.org).',
    'and the quote (https://example.org)',
    '[ref]: https://example.org',
  ]);
});

test('a reference link resolves inside a table cell', () => {
  const shown = lines(
    '| a |\n| --- |\n| [docs][ref] |\n\n[ref]: https://e.org',
    40,
  ).join('\n');

  expect(shown.includes('docs (https://e.org)')).toBeTruthy();
  // The definition shows once, as its own block, not inside the table's.
  expect(shown.split('[ref]:').length).toStrictEqual(2);
});

/**
 * The blocks of `text` with colour, rendered by a runtime of their own, since
 * whether code is highlighted follows NO_COLOR, which a process reads once at
 * its start: so the run's own NO_COLOR, set or not, decides nothing here.
 */
async function coloured(
  text: string,
  width = 60,
  noColor = false,
): Promise<string[]> {
  const env = { ...process.env };

  delete env.NO_COLOR;

  const script = `import { markdown } from '${new URL(
    '../../../src/ui/transcript/markdown.ts',
    import.meta.url,
  )}'; console.log(JSON.stringify(markdown(${JSON.stringify(
    text,
  )}, ${width}, true).map((block) => block.text)));`;
  // Rejects when the script fails.
  const { stdout } = await promisify(execFile)(
    process.execPath,
    ['--eval', script],
    { env: noColor ? { ...env, NO_COLOR: '1' } : env },
  );

  return JSON.parse(stdout) as string[];
}

/** A code box's lines between its bars, colours and all. */
function boxed(text: string): string[] {
  const bar = '\x1b[2m│\x1b[22m';

  return text
    .split('\n')
    .slice(1, -1)
    .map((line) => line.slice(bar.length + 1, -(bar.length + 1)).trimEnd());
}

/** The first block of `text`, a code box, as its lines between its bars. */
async function codeLines(text: string, width = 60): Promise<string[]> {
  return boxed((await coloured(text, width))[0]!);
}

test('a fence labelled with a known language is highlighted', async () => {
  const [line] = await codeLines('```ts\nconst a = 1; // one\n```');

  expect(line!.includes('\x1b['), 'coloured').toBeTruthy();
  expect(stripAnsi(line!)).toStrictEqual('const a = 1; // one');
  expect(
    (await codeLines('```sh\necho "hi"\n```'))[0]!.includes('\x1b['),
  ).toBeTruthy();
});

test('a fence with no label or an unknown one stays plain', async () => {
  expect(await codeLines('```\nconst a = 1;\n```')).toStrictEqual([
    'const a = 1;',
  ]);
  expect(await codeLines('```nolang\nconst a = 1;\n```')).toStrictEqual([
    'const a = 1;',
  ]);
  expect(lines('```ts\nconst a = 1;\n```', 40)[1]).toStrictEqual(
    '│ const a = 1; │',
  );
});

test('a comment over several lines is coloured on each', async () => {
  const [open, middle] = await codeLines('```ts\n/* one\n   two */\nx;\n```');

  expect(open!.startsWith('\x1b[')).toBeTruthy();
  expect(middle!.startsWith('\x1b['), 'the comment goes on').toBeTruthy();
});

test('a highlighted line too long for its box goes on below', async () => {
  const code = `const a = '${'x'.repeat(40)}';`;
  const shown = await codeLines(`\`\`\`ts\n${code}\n\`\`\`\n`, 24);

  expect(shown.map(stripAnsi).join('')).toStrictEqual(code);
  expect(shown.every((line) => stringWidth(line) <= 20)).toBeTruthy();
  expect(
    shown[1]!.startsWith('\x1b['),
    'the string is still coloured',
  ).toBeTruthy();
});

test('code in a quote is boxed and highlighted as at the top', async () => {
  const fence = '```ts\n/* one\n   two */\nconst a = 1;\n```';
  const [top] = await coloured(fence);
  const [quoted] = await coloured(
    `> Look:\n>\n${fence.replace(/^/gm, '> ')}\n>\n> after`,
  );
  const quotedLines = quoted!.split('\n');

  expect(quotedLines[0]).toStrictEqual('Look:');
  expect(quotedLines.slice(1, 6).join('\n')).toStrictEqual(top!);
  expect(
    boxed(top!).every((line) => line.startsWith('\x1b[')),
    'coloured',
  ).toBeTruthy();
  expect(quotedLines.slice(6)).toStrictEqual(['', 'after']);
  expect(lines(`> ${'```'}\n> plain\n> ${'```'}`, 40)).toStrictEqual([
    '┌───────┐',
    '│ plain │',
    '└───────┘',
  ]);
});

test('code in a quote in a list is highlighted inside its bar', async () => {
  const [list] = await coloured('- a\n\n  > ```sh\n  > echo "hi"\n  > ```', 40);
  const rows = list!.split('\n');

  expect(rows.map(stripAnsi)).toStrictEqual([
    '- a',
    '  │ ┌ sh ───────┐',
    '  │ │ echo "hi" │',
    '  │ └───────────┘',
  ]);

  const [top] = await coloured('```sh\necho "hi"\n```', 40);

  expect(
    rows[2]!.endsWith(top!.split('\n')[1]!),
    'coloured as at the top',
  ).toBeTruthy();
});

test('NO_COLOR leaves code plain, at the top and in a quote', async () => {
  const [top, quoted] = await coloured(
    '```ts\nconst a = 1;\n```\n\n> ```ts\n> const a = 1;\n> ```',
    40,
    true,
  );

  expect(boxed(top!)).toStrictEqual(['const a = 1;']);
  expect(boxed(quoted!)).toStrictEqual(['const a = 1;']);
});

const ESC = '\x1b';

test('CHD-69: NO_COLOR leaves inline code and links uncoloured', async () => {
  const text = 'Run `deno task check` and see [docs](https://e.org).';
  const [plain] = await coloured(text, 60, true);
  const [painted] = await coloured(text, 60);

  // A foreground or background, 16-colour or more; bold and dim may stay.
  const colour = new RegExp(`${ESC}\\[(38|48|3\\d|4\\d|9\\d)[;m]`);

  expect(!colour.test(plain!), 'no colour at all').toBeTruthy();
  expect(stripAnsi(plain!)).toStrictEqual(stripAnsi(painted!));
  // The theme's inline code colour, the dark theme's #b1b9f9, where there is
  // colour to draw.
  expect(painted!.includes('\x1b[38;2;177;185;249m')).toBeTruthy();
});

test("inline code and links take the palette's colours", () => {
  const [shown] = markdown('`a` [b](https://e.org)', 40, true, PALETTES.light);

  if (process.env.NO_COLOR) {
    return;
  }

  expect(
    shown!.text.includes('\x1b[38;2;74;90;224m'),
    'inline code',
  ).toBeTruthy();
  expect(shown!.text.includes('\x1b[38;2;11;92;173m'), 'link').toBeTruthy();
});

test('soft, a paragraph, a heading and a quote are a line each (CHD-396)', () => {
  const blocks = softMarkdown(
    [
      '## A heading long enough to wrap',
      '',
      'A paragraph long enough to wrap,',
      'with a soft break and a hard  ',
      'one.',
      '',
      '> A quote long enough to wrap at this width.',
    ].join('\n'),
    20,
    false,
  );

  expect(blocks).toStrictEqual([
    { kind: 'text', text: 'A heading long enough to wrap' },
    // A soft break joins with a space; a hard break stays a line break.
    {
      kind: 'text',
      text: 'A paragraph long enough to wrap, with a soft break and a hard\none.',
    },
    { kind: 'quote', text: 'A quote long enough to wrap at this width.' },
  ]);
});

test('soft, a code block is its code for a box as wide as it or its label, within the width (CHD-396)', () => {
  const code = (text: string) => softMarkdown(text, 30, false);

  expect(code('```sh\ndeno task check\n```')).toStrictEqual([
    { kind: 'code', label: 'sh', code: 'deno task check', width: 19 },
  ]);
  // A label wider than its code widens the box so OpenTUI draws it.
  expect(code('```typescript\nx\n```')).toStrictEqual([
    { kind: 'code', label: 'typescript', code: 'x', width: 16 },
  ]);
  // A long line stays whole for OpenTUI to cut; the box keeps to the width.
  // Blank lines in the code are the agent's.
  expect(code('```\n\n' + 'y'.repeat(40) + '\n\nz\n```')).toStrictEqual([
    { kind: 'code', label: '', code: `\n${'y'.repeat(40)}\n\nz`, width: 30 },
  ]);
  // The rows path keeps its drawn box.
  expect(markdown('```sh\nls\n```', 30, false)[0]?.text).toStrictEqual(
    '┌ sh ──┐\n│ ls   │\n└──────┘',
  );
});

test('soft, a list is its items, each beside its own marker (CHD-396)', () => {
  const [bullets, numbers, tasks] = softMarkdown(
    [
      '- an item long enough to wrap',
      '  1. nested, and long enough too',
      '     ```sh',
      '     abcdefghijklmnopqrstu',
      '     ```',
      '',
      '9. nine',
      '10. ten',
      '',
      '- [ ] open',
      '- [x] done',
    ].join('\n'),
    20,
    false,
  );

  expect(bullets).toStrictEqual({
    kind: 'list',
    loose: false,
    items: [
      {
        marker: '- ',
        blocks: [
          { kind: 'text', text: 'an item long enough to wrap' },
          {
            kind: 'list',
            loose: false,
            items: [
              {
                marker: '1. ',
                // The box takes the 15 cells beside both markers.
                blocks: [
                  { kind: 'text', text: 'nested, and long enough too' },
                  {
                    kind: 'code',
                    label: 'sh',
                    code: 'abcdefghijklmnopqrstu',
                    width: 15,
                  },
                ],
              },
            ],
          },
        ],
      },
    ],
  });
  // Numbered on from the first as written, each marker its own width.
  expect(
    numbers?.kind === 'list' && numbers.items.map((item) => item.marker),
  ).toStrictEqual(['9. ', '10. ']);
  expect(
    tasks?.kind === 'list' && tasks.items.map((item) => item.marker),
  ).toStrictEqual(['[ ] ', '[x] ']);
});

test('soft, a loose list says so (CHD-396)', () => {
  const [list] = softMarkdown('- a\n\n  more\n- b', 20, false);

  expect(list).toStrictEqual({
    kind: 'list',
    loose: true,
    items: [
      {
        marker: '- ',
        blocks: [
          { kind: 'text', text: 'a' },
          { kind: 'text', text: 'more' },
        ],
      },
      { marker: '- ', blocks: [{ kind: 'text', text: 'b' }] },
    ],
  });
});

test("a reply's code blocks are listed as drawn: label, text as written, whether it has [run], and where (CHD-394)", () => {
  const reply = [
    'Run this:',
    '',
    '```sh',
    'bun test --isolate',
    '```',
    '',
    '- then',
    '',
    '  ```bash',
    '  echo "one"',
    '  echo "two"',
    '  ```',
    '',
    '> quoted:',
    '>',
    '> ```console',
    '> $ ls',
    '> a.ts',
    '> ```',
    '',
    '```',
    'no label',
    '```',
    '',
    '```ts title.ts',
    'const a = 1;',
    '```',
    '',
    '```Bash',
    'echo case',
  ].join('\n');
  const blocks = codeBlocks(reply);
  const lines = reply.split('\n');

  expect(
    blocks.map(({ index, label, text, runnable, quoted }) => [
      index,
      label,
      text,
      runnable,
      quoted,
    ]),
  ).toStrictEqual([
    [0, 'sh', 'bun test --isolate', true, false],
    [1, 'bash', 'echo "one"\necho "two"', true, false],
    // A console block mixes commands with output: [copy] only.
    [2, 'console', '$ ls\na.ts', false, true],
    [3, '', 'no label', false, false],
    [4, 'ts', 'const a = 1;', false, false],
    // An open fence, mid-stream, to the end; a label is matched as written.
    [5, 'Bash', 'echo case', false, false],
  ]);
  // Each starts on its fence's line of the reply.
  expect(blocks.map(({ line }) => lines[line]?.trim())).toStrictEqual([
    '```sh',
    '```bash',
    '> ```console',
    '```',
    '```ts title.ts',
    '```Bash',
  ]);

  // The boxes the transcript draws, in the same order, hold the same code.
  const boxes = (soft: readonly Soft[]): Code[] =>
    soft.flatMap((block) =>
      block.kind === 'code'
        ? [block]
        : block.kind === 'list'
          ? block.items.flatMap((item) => boxes(item.blocks))
          : [],
    );

  expect(
    boxes(softMarkdown(reply, 80, true)).map(({ label, code }) => [
      label,
      stripAnsi(code),
    ]),
  ).toStrictEqual(
    blocks
      .filter(({ quoted }) => !quoted)
      .map(({ label, text }) => [label, text]),
  );
});

test('a reply with no code has no blocks, and an indented block has no label, its text without the line break it ends on', () => {
  expect(codeBlocks('Just prose.')).toStrictEqual([]);
  expect(codeBlocks('Here:\n\n    make all\n')).toStrictEqual([
    {
      index: 0,
      line: 2,
      label: '',
      // marked keeps the reply's last line break, which a copy leaves out.
      text: 'make all',
      runnable: false,
      quoted: false,
    },
  ]);
});

test("[run] puts a block's every line in, each leading `$ ` taken off, the rest as written (the owner's answer, CHD-394)", () => {
  expect(runCommand('deno task check')).toStrictEqual('deno task check');
  expect(runCommand('$ bun install\n$ bun test tests/parse')).toStrictEqual(
    'bun install\nbun test tests/parse',
  );
  expect(
    runCommand(
      'deno task compile --all\nfor bin in dist/*/chord; do echo "$bin"; done',
    ),
  ).toStrictEqual(
    'deno task compile --all\nfor bin in dist/*/chord; do echo "$bin"; done',
  );
  // Only a `$ ` the line starts with: an indented one, or `$` alone, stays.
  expect(runCommand('  $ ls\n$\n$HOME\n$ ')).toStrictEqual(
    '  $ ls\n$\n$HOME\n',
  );
});

describe('CHD-394 U1 tester: block source boundaries', () => {
  test('nested lists and quotes retain their original fence lines and quoted identity', () => {
    const reply = [
      'Intro',
      '',
      '> - quoted item',
      '>',
      '>   ~~~console',
      '>   $ echo "hi"',
      '>   hi',
      '>   ~~~',
      '',
      '- outer',
      '',
      '  1. inner',
      '',
      '     ```bash extra',
      '     printf "nested"',
      '     ```',
    ].join('\n');

    expect(codeBlocks(reply)).toStrictEqual([
      {
        index: 0,
        line: 4,
        label: 'console',
        text: '$ echo "hi"\nhi',
        runnable: false,
        quoted: true,
      },
      {
        index: 1,
        line: 13,
        label: 'bash',
        text: 'printf "nested"',
        runnable: true,
        quoted: false,
      },
    ]);
  });

  test('a longer open fence preserves literal shorter fences, Unicode and command prompts without rewriting', () => {
    const before =
      'A reply\r\n\r\n````sh title\r\n$ printf "café 👍🏽"\r\n```\r\noutput';
    const expected = '$ printf "café 👍🏽"\n```\noutput';

    expect(codeBlocks(before)).toStrictEqual([
      {
        index: 0,
        line: 2,
        label: 'sh',
        text: expected,
        runnable: true,
        quoted: false,
      },
    ]);
    expect(
      codeBlocks(before + '\r\n````').map(({ index, line, text }) => ({
        index,
        line,
        text,
      })),
    ).toStrictEqual([{ index: 0, line: 2, text: expected }]);
  });

  test('inline fence-like text and tables add no blocks, while empty and indented code remain listed', () => {
    expect(
      codeBlocks(
        'Inline `echo hi` and `` ```sh ``.\n\n| a | b |\n| - | - |\n| c | d |',
      ),
    ).toStrictEqual([]);
    expect(codeBlocks('```bash\n```\n\n    indented\n')).toStrictEqual([
      {
        index: 0,
        line: 0,
        label: 'bash',
        text: '',
        runnable: true,
        quoted: false,
      },
      {
        index: 1,
        line: 3,
        label: '',
        text: 'indented',
        runnable: false,
        quoted: false,
      },
    ]);
  });
});

describe('CHD-394 U1 tester: command and copy boundaries', () => {
  test('run removes one exact prompt prefix per line, preserving blank lines, whitespace and Unicode', () => {
    expect(runCommand('')).toBe('');
    expect(
      runCommand('$ $ printf "café 👍🏽"\n\n\t$ keep\n$\tkeep\n $ keep\n$ \n'),
    ).toBe('$ printf "café 👍🏽"\n\n\t$ keep\n$\tkeep\n $ keep\n\n');
  });

  test('copy strips trailing line breaks while keeping internal blanks and spaces on the last line', () => {
    const blocks = codeBlocks(
      '```sh\n$ first\n\n$ second  \n\n\n```\n\n```bash\n\n\n```',
    );

    expect(blocks.map(({ text }) => text)).toStrictEqual([
      '$ first\n\n$ second  ',
      '',
    ]);
    expect(runCommand(blocks[0]?.text ?? '')).toBe('first\n\nsecond  ');
  });
});
