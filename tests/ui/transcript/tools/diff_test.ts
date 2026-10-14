import { expect, test } from 'bun:test';
import assert from 'node:assert/strict';
import stripAnsi from 'strip-ansi';
import { highlightLines } from '../../../../src/ui/transcript/highlight.ts';
import {
  DIFF_CONTEXT,
  DIFF_ROWS,
  diffHeadline,
  diffView,
} from '../../../../src/ui/transcript/tools/diff.ts';
import { type CodeTones, PALETTES } from '../../../../src/ui/theme/theme.ts';

/** The light theme's tokens: on the terminal, and on a tint. */
const LIGHT = PALETTES.light.code!;

function numbered(count: number, label = 'line'): string {
  return Array.from({ length: count }, (_, n) => `${label} ${n + 1}\n`).join(
    '',
  );
}

test('a replaced line reads as its removal, then its addition', () => {
  const view = diffView('a.ts', 'a\nb\nc\n', 'a\nB\nc\n', false);

  expect(view.rows).toStrictEqual([
    { kind: 'context', number: 1, text: 'a' },
    { kind: 'removed', number: 2, text: 'b' },
    { kind: 'added', number: 2, text: 'B' },
    { kind: 'context', number: 3, text: 'c' },
  ]);
  expect(diffHeadline(view)).toStrictEqual(
    'Updated a.ts with 1 addition and 1 removal',
  );
  expect(view.hidden).toStrictEqual(0);
});

test('a removal is numbered in the old text, the rest in the new', () => {
  const view = diffView('a.ts', 'a\nb\nc\n', 'new\na\nc\n', false);

  expect(view.rows).toStrictEqual([
    { kind: 'added', number: 1, text: 'new' },
    { kind: 'context', number: 2, text: 'a' },
    { kind: 'removed', number: 2, text: 'b' },
    { kind: 'context', number: 3, text: 'c' },
  ]);
});

test('context stops a few lines from a change, and hunks are parted by a gap', () => {
  const old = numbered(30);
  const changed = old
    .replace('line 2\n', 'two\n')
    .replace('line 25\n', 'twenty-five\n');
  const { rows } = diffView('a.ts', old, changed, true);
  const gap = rows.findIndex((row) => row.kind === 'gap');

  expect(gap).toStrictEqual(1 + 2 + DIFF_CONTEXT);
  expect(rows[gap - 1]).toStrictEqual({
    kind: 'context',
    number: 2 + DIFF_CONTEXT,
    text: `line ${2 + DIFF_CONTEXT}`,
  });
  expect(rows[gap + 1]).toStrictEqual({
    kind: 'context',
    number: 25 - DIFF_CONTEXT,
    text: `line ${25 - DIFF_CONTEXT}`,
  });
  expect(rows.filter((row) => row.kind === 'gap').length).toStrictEqual(1);
});

test('a long diff folds to its first rows and counts the lines folded', () => {
  const view = diffView('a.ts', '', numbered(25), false);

  expect(view.rows.length).toStrictEqual(DIFF_ROWS);
  expect(view.hidden).toStrictEqual(25 - DIFF_ROWS);
  expect(view.added).toStrictEqual(25);
  expect(diffView('a.ts', '', numbered(25), true).rows.length).toStrictEqual(
    25,
  );
  expect(diffView('a.ts', '', numbered(25), true).hidden).toStrictEqual(0);
});

test('a fold never ends on a gap', () => {
  const old = numbered(40);
  // Two hunks: the first fills exactly the folded rows, less the gap.
  const changed = old
    .replace('line 1\nline 2\nline 3\nline 4\n', '')
    .replace('line 30\n', 'thirty\n');
  const first = 4 + DIFF_CONTEXT;
  const view = diffView('a.ts', old, changed, false);

  expect(first < DIFF_ROWS).toStrictEqual(true);
  expect(view.rows.at(-1)?.kind === 'gap').toStrictEqual(false);
  expect(view.hidden).toStrictEqual(
    diffView('a.ts', old, changed, true).rows.filter(
      (row) => row.kind !== 'gap',
    ).length - view.rows.filter((row) => row.kind !== 'gap').length,
  );
});

test('the number column is as wide as the widest number shown', () => {
  const old = numbered(120);
  const view = diffView('a.ts', old, old.replace('line 100\n', 'x\n'), false);

  expect(view.numberWidth).toStrictEqual(3);
  expect(diffView('a.ts', 'a\n', 'b\n', false).numberWidth).toStrictEqual(1);
});

test('tabs become spaces, since Ink cannot measure a tab stop', () => {
  const [row] = diffView('a.ts', '', '\tx\n', false).rows;

  expect(row).toStrictEqual({ kind: 'added', number: 1, text: '  x' });
});

test('a repeated line counts each time it is added or removed', () => {
  expect(diffHeadline(diffView('a.ts', 'a\na\n', 'a\n', false))).toStrictEqual(
    'Updated a.ts with 0 additions and 1 removal',
  );
  expect(diffHeadline(diffView('a.ts', 'a\n', 'a\na\n', false))).toStrictEqual(
    'Updated a.ts with 1 addition and 0 removals',
  );
});

test('a line that only moved counts as removed and added', () => {
  expect(
    diffHeadline(diffView('a.ts', 'a\nb\n', 'b\na\n', false)),
  ).toStrictEqual('Updated a.ts with 1 addition and 1 removal');
});

test('line endings are not edits; a new file is all additions', () => {
  const endings = diffView('a.ts', 'a\r\nb', 'a\nb\n', false);

  expect(diffHeadline(endings)).toStrictEqual(
    'Updated a.ts with 0 additions and 0 removals',
  );
  expect(endings.rows).toStrictEqual([]);
  expect(diffHeadline(diffView('a.ts', null, 'a\nb\n', false))).toStrictEqual(
    'Updated a.ts with 2 additions and 0 removals',
  );
});

test('with colour, each row carries its line coloured by the file', () => {
  const view = diffView(
    'src/a.ts',
    'const a = 1;\nconst b = 2;\n',
    'const a = 1;\nconst b = 3;\n',
    true,
    LIGHT,
  );

  for (const row of view.rows) {
    assert(row.kind !== 'gap' && row.code !== undefined);
    expect(row.code.includes('\x1b['), 'coloured').toBeTruthy();
    expect(stripAnsi(row.code)).toStrictEqual(row.text);
  }

  expect(
    view.rows.map((row) => (row.kind === 'gap' ? '' : stripAnsi(row.code!))),
  ).toStrictEqual(['const a = 1;', 'const b = 2;', 'const b = 3;']);
});

test('a changed row is coloured for the tint, an unchanged one not', () => {
  const [context, removed, added] = diffView(
    'src/a.ts',
    'const a = 1;\nconst b = 2;\n',
    'const a = 1;\nconst b = 2;;\n',
    true,
    LIGHT,
  ).rows;
  const code = (row: typeof context) => (row?.kind === 'gap' ? '' : row?.code);

  expect(code(context)).toStrictEqual(
    highlightLines('const a = 1;', 'ts', LIGHT.terminal)[0],
  );
  expect(code(removed)).toStrictEqual(
    highlightLines('const a = 1;\nconst b = 2;\n', 'ts', LIGHT.tint)[1],
  );
  expect(code(added)).toStrictEqual(
    highlightLines('const a = 1;\nconst b = 2;;\n', 'ts', LIGHT.tint)[1],
  );
});

test('a row inside a comment opened rows above is coloured as one', () => {
  const old = '/*\n * one\n * two\n */\nx;\n';
  const [, changed] = diffView(
    'a.ts',
    old,
    old.replace('two', 'three'),
    true,
    LIGHT,
  ).rows.filter((row) => row.kind !== 'context');

  expect(
    changed?.kind === 'added' && changed.code!.startsWith('\x1b['),
  ).toBeTruthy();
});

test('a theme with no tint leaves a changed row plain', () => {
  const [context, removed] = diffView(
    'a.ts',
    'const a = 1;\nconst b = 2;\n',
    'const a = 1;\nconst b = 3;\n',
    true,
    PALETTES['dark-ansi'].code,
  ).rows;

  expect(
    context?.kind === 'context' && context.code?.includes('\x1b['),
  ).toBeTruthy();
  expect(
    removed?.kind === 'removed' && removed.code === undefined,
  ).toBeTruthy();
});

test('a file of no known language, or no colour, has no code', () => {
  const rows = (path: string, tones?: CodeTones) =>
    diffView(path, 'a\n', 'b\n', false, tones).rows;

  expect(
    rows('notes.unknown', LIGHT).every((row) => !('code' in row)),
  ).toBeTruthy();
  expect(rows('a.ts').every((row) => !('code' in row))).toBeTruthy();
});

test('a coloured row keeps a tab as two spaces', () => {
  const [row] = diffView('a.go', '', '\tx := 1\n', false, LIGHT).rows;

  expect(stripAnsi(row?.kind === 'gap' ? '' : row!.code!)).toStrictEqual(
    '  x := 1',
  );
});
