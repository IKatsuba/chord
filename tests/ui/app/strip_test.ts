import { expect, test } from 'bun:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import stringWidth from 'string-width';
import { emptyWatch } from '../../../src/notify.ts';
import { idle } from '../../../src/session/tabs.ts';
import {
  GLYPHS,
  stripLayout,
  type StripTab,
  type StripView,
  glyphsOf,
  tabGlyphs,
} from '../../../src/ui/app/strip.ts';

const MOCKS = new URL(
  '../../../docs/design/evidence/CHD-114/mock/',
  import.meta.url,
);

/** The header's first row of a mock, without the spaces after its directory. */
async function mockHeader(name: string): Promise<string> {
  const text = await readFile(new URL(`${name}.txt`, MOCKS), 'utf8');

  return text.split('\n')[0]!.trimEnd();
}

/**
 * The header row as the window draws it, inside one column of padding each
 * side, as text: the front tab's inverse cannot show in text, as the mocks
 * say, so it reads as its padded name.
 */
function row(view: StripView, columns: number): string {
  const left =
    'chord' +
    view.pieces
      .map((piece) =>
        piece.kind === 'tab' && glyphsOf(piece.glyphs).length > 0
          ? `${piece.text} ${glyphsOf(piece.glyphs)
              .map((glyph) => GLYPHS[glyph])
              .join('')}`
          : piece.text,
      )
      .join('');
  const gap = columns - 2 - stringWidth(left) - stringWidth(view.directory);

  return ` ${left}${' '.repeat(gap)}${view.directory} `;
}

const TWO: StripTab[] = [
  { number: 1, agent: 'fake', front: true },
  { number: 2, agent: 'claude', front: false, glyphs: { state: 'working' } },
];

const SIX: StripTab[] = [
  { number: 1, agent: 'fake', front: true },
  { number: 2, agent: 'claude', front: false, glyphs: { state: 'asking' } },
  { number: 3, agent: 'fake', front: false, glyphs: { mark: 'replied' } },
  { number: 4, agent: 'codex', front: false, glyphs: { state: 'working' } },
  { number: 5, agent: 'fake', front: false },
  { number: 6, agent: 'claude', front: false, glyphs: { state: 'working' } },
];

/**
 * A mock's header ends its directory in the last column, where the window
 * keeps one column of padding; the rest is to the column.
 */
async function matchesMock(tabs: StripTab[], name: string, columns: number) {
  const view = stripLayout(tabs, '~/src/app', columns - 2);

  assert(view, 'no strip');

  const drawn = row(view, columns);

  expect(stringWidth(drawn)).toStrictEqual(columns);
  expect(drawn.trimEnd()).toStrictEqual(
    (await mockHeader(name)).replace(/ (\S+)$/, '$1'),
  );
}

test('one session draws no strip, and the header is as it was', () => {
  expect(stripLayout([TWO[0]!], '~/src/app', 118)).toStrictEqual(undefined);
});

test('two sessions at 120 and 80 columns read as the mock does', async () => {
  await matchesMock(TWO, '120-two', 120);
  await matchesMock(TWO, '80-two', 80);
});

test('six sessions keep their names at 120, and drop them at 80', async () => {
  await matchesMock(SIX, '120-narrow-many', 120);
  await matchesMock(SIX, '80-narrow-many', 80);
});

test('the directory is cut at a / before any tab drops its name', () => {
  const view = stripLayout(TWO, '/tmp/chord-qa.Xa9c/projects/app', 50);

  assert(view);
  expect(view.directory).toStrictEqual('…/projects/app');
  expect(view.pieces.some((piece) => piece.text === '2 claude')).toBeTruthy();
});

test('the tabs behind drop their names together, the front keeps its', () => {
  const view = stripLayout(
    SIX,
    '/a/long/way/down/to/where/the/window/was/opened/app',
    60,
  );

  assert(view);
  expect(
    view.pieces
      .filter((piece) => piece.kind !== 'gap')
      .map((piece) => piece.text),
  ).toStrictEqual([' 1 fake ', '2', '3', '4', '5', '6']);
  expect(
    view.directory.startsWith('…/') && view.directory.endsWith('/app'),
  ).toBeTruthy();
});

test('nine short tabs fit 80 columns with the directory', () => {
  const nine = Array.from({ length: 9 }, (_, index): StripTab => ({
    number: index + 1,
    agent: 'claude',
    front: index === 4,
    glyphs: index === 4 ? undefined : { state: 'asking' },
  }));
  const view = stripLayout(nine, '~/src/app', 78);

  assert(view);
  expect(stringWidth(row(view, 80)) <= 80).toBeTruthy();
  expect(view.directory).toStrictEqual('~/src/app');
});

test('a tab shows its state, none while idle, then what of it is not yet seen (CHD-471)', () => {
  const asking = {
    on: { kind: 'permission', title: 'Write notes.txt' },
    since: 1,
  } as const;

  expect(tabGlyphs(idle)).toStrictEqual({});
  expect(tabGlyphs({ watch: emptyWatch, working: 1 })).toStrictEqual({
    state: 'working',
  });
  // Working with a reply not yet seen: both.
  expect(
    tabGlyphs({
      watch: emptyWatch,
      working: 1,
      unseen: { kind: 'replied', since: 2 },
    }),
  ).toStrictEqual({ state: 'working', mark: 'replied' });
  // A failed turn is a mark, the tab idle; an exit is its state.
  expect(
    tabGlyphs({ watch: emptyWatch, unseen: { kind: 'failed', since: 2 } }),
  ).toStrictEqual({ mark: 'failed' });
  expect(
    tabGlyphs({
      watch: emptyWatch,
      exited: true,
      unseen: { kind: 'failed', since: 2, failure: 'exited' },
    }),
  ).toStrictEqual({ state: 'failed' });
  expect(
    tabGlyphs({
      watch: emptyWatch,
      unseen: { kind: 'message', from: '@main', since: 2 },
    }),
  ).toStrictEqual({ mark: 'message' });
  expect(
    tabGlyphs({
      watch: emptyWatch,
      asking,
      unseen: { kind: 'failed', since: 2 },
    }),
  ).toStrictEqual({ state: 'asking', mark: 'failed' });

  // Drawn after the tab, state first: `2 codex ✻✓`.
  const view = stripLayout(
    [
      { number: 1, agent: 'fake', front: true },
      {
        number: 2,
        agent: 'codex',
        front: false,
        glyphs: { state: 'working', mark: 'replied' },
      },
      { number: 3, agent: 'fake', front: false, glyphs: { mark: 'replied' } },
    ],
    '~/src/app',
    78,
  );

  assert(view);
  expect(row(view, 80)).toContain('2 codex ✻✓    3 fake ✓');
});
