import { expect, test } from 'bun:test';
import {
  cutPlaceholder,
  type PastedImage,
} from '../../../src/ui/prompt/images.ts';
import type { Cursor } from '../../../src/ui/prompt/prompt.ts';
import {
  cursorOffset,
  startingVim,
  typedAt,
  type Vim,
  vimCleared,
  vimEscape,
  vimKey,
  vimKeyNames,
  vimReset,
  type VimStep,
  vimTakes,
} from '../../../src/ui/prompt/vim.ts';

/** Normal mode, as Esc leaves it, with nothing to undo yet. */
const NORMAL: Vim = { ...startingVim, mode: 'normal', entered: undefined };

interface Played {
  readonly text: string;
  readonly cursor: Cursor;
  readonly vim: Vim;
}

/** `keys`, each a key by the engine's name, played from `text` at `cursor`. */
function play(
  text: string,
  cursor: Cursor,
  keys: readonly string[],
  vim: Vim = NORMAL,
  images: readonly PastedImage[] = [],
): Played {
  let now: Played = { text, cursor, vim };

  for (const key of keys) {
    const step: VimStep = vimKey(
      now.vim,
      now.text,
      now.cursor,
      key,
      (before, after) => cutPlaceholder(before, after, images),
    );

    if ('history' in step) {
      throw new Error(`${key} walked history`);
    }

    now = step;
  }

  return now;
}

/** What `keys` leave: the text and the cursor. */
function after(text: string, cursor: Cursor, keys: string): [string, Cursor] {
  const { text: left, cursor: at } = play(text, cursor, [...keys]);

  return [left, at];
}

const FOX = 'the quick brown fox';

test('h and l move along the line and stop at its ends', () => {
  expect(after(FOX, [0, 4], 'l')).toStrictEqual([FOX, [0, 5]]);
  expect(after(FOX, [0, 4], 'h')).toStrictEqual([FOX, [0, 3]]);
  expect(after(FOX, [0, 0], 'h')).toStrictEqual([FOX, [0, 0]]);
  // Normal mode stands on the last character, never after it.
  expect(after(FOX, [0, 18], 'l')).toStrictEqual([FOX, [0, 18]]);
});

test('j and k move between lines, keeping the column where it fits', () => {
  const text = 'first line\nab\nthird line';

  expect(after(text, [0, 6], 'j')).toStrictEqual([text, [1, 1]]);
  expect(after(text, [1, 1], 'k')).toStrictEqual([text, [0, 1]]);
  expect(after(text, [0, 6], 'jj')).toStrictEqual([text, [2, 6]]);
});

test('k on the first line and j on the last walk history', () => {
  const text = 'one\ntwo';

  expect(vimKey(NORMAL, text, [0, 1], 'k')).toStrictEqual({
    vim: NORMAL,
    history: 'older',
  });
  expect(vimKey(NORMAL, text, [1, 1], 'j')).toStrictEqual({
    vim: NORMAL,
    history: 'newer',
  });
  expect(vimKey(NORMAL, text, [0, 1], '<Up>')).toStrictEqual({
    vim: NORMAL,
    history: 'older',
  });
});

test('w, b and e move by words', () => {
  expect(after(FOX, [0, 0], 'w')).toStrictEqual([FOX, [0, 4]]);
  expect(after(FOX, [0, 10], 'b')).toStrictEqual([FOX, [0, 4]]);
  expect(after(FOX, [0, 0], 'e')).toStrictEqual([FOX, [0, 2]]);
  expect(after(FOX, [0, 2], 'e')).toStrictEqual([FOX, [0, 8]]);
});

test('0, ^ and $ go to the start, the first word and the end', () => {
  const text = '  indented line';

  expect(after(text, [0, 9], '0')).toStrictEqual([text, [0, 0]]);
  expect(after(text, [0, 9], '^')).toStrictEqual([text, [0, 2]]);
  expect(after(text, [0, 0], '$')).toStrictEqual([text, [0, 14]]);
});

test('a count moves that many times', () => {
  expect(after(FOX, [0, 0], '3w')).toStrictEqual([FOX, [0, 16]]);
  expect(after(FOX, [0, 0], '4l')).toStrictEqual([FOX, [0, 4]]);
  expect(after(FOX, [0, 16], '2b')).toStrictEqual([FOX, [0, 4]]);
  expect(after('a\nb\nc\nd', [0, 0], '2j')).toStrictEqual([
    'a\nb\nc\nd',
    [2, 0],
  ]);
});

test('a count waits for its motion, and Esc drops it', () => {
  const half = play(FOX, [0, 0], ['2']);

  expect(half.vim.pending).toStrictEqual(['2']);
  expect(half.cursor).toStrictEqual([0, 0]);
  expect(vimCleared(half.vim).pending).toStrictEqual([]);
  expect(play(FOX, [0, 0], ['2', 'd']).vim.pending).toStrictEqual(['2', 'd']);
});

test('x deletes the character under the cursor, a count that many', () => {
  expect(after(FOX, [0, 0], 'x')).toStrictEqual(['he quick brown fox', [0, 0]]);
  expect(after(FOX, [0, 4], '3x')).toStrictEqual(['the ck brown fox', [0, 4]]);
  // On the last character the cursor steps back onto the new last.
  expect(after('ab', [0, 1], 'x')).toStrictEqual(['a', [0, 0]]);
});

test('dw deletes to the next word, and counts either side', () => {
  expect(after(FOX, [0, 4], 'dw')).toStrictEqual(['the brown fox', [0, 4]]);
  expect(after(FOX, [0, 0], 'd2w')).toStrictEqual(['brown fox', [0, 0]]);
  expect(after(FOX, [0, 0], '2dw')).toStrictEqual(['brown fox', [0, 0]]);
});

test('dd deletes the line, a count that many', () => {
  const text = 'one\ntwo\nthree';

  expect(after(text, [1, 1], 'dd')).toStrictEqual(['one\nthree', [1, 0]]);
  expect(after(text, [0, 0], '2dd')).toStrictEqual(['three', [0, 0]]);
  expect(after(text, [2, 2], 'dd')).toStrictEqual(['one\ntwo', [1, 0]]);
  expect(after('only', [0, 2], 'dd')).toStrictEqual(['', [0, 0]]);
});

test('D deletes to the end of the line', () => {
  expect(after(FOX, [0, 10], 'D')).toStrictEqual(['the quick ', [0, 9]]);
});

test('cw and C change, leaving insert mode at the gap', () => {
  const changed = play(FOX, [0, 4], ['c', 'w']);

  expect(changed.text).toStrictEqual('the  brown fox');
  expect(changed.cursor).toStrictEqual([0, 4]);
  expect(changed.vim.mode).toStrictEqual('insert');

  const rest = play(FOX, [0, 4], ['C']);

  expect(rest.text).toStrictEqual('the ');
  expect(rest.cursor).toStrictEqual([0, 4]);
  expect(rest.vim.mode).toStrictEqual('insert');
});

test('i, a, I and A go to insert mode before, after, at the start, at the end', () => {
  const text = '  word here';
  const insert = (keys: string) => {
    const played = play(text, [0, 4], [...keys]);

    expect(played.vim.mode, keys).toStrictEqual('insert');
    expect(played.text, keys).toStrictEqual(text);

    return played.cursor;
  };

  expect(insert('i')).toStrictEqual([0, 4]);
  expect(insert('a')).toStrictEqual([0, 5]);
  expect(insert('I')).toStrictEqual([0, 2]);
  expect(insert('A')).toStrictEqual([0, 11]);
});

test('o and O open a line below and above, in insert mode', () => {
  const below = play('one\ntwo', [0, 1], ['o']);

  expect(below.text).toStrictEqual('one\n\ntwo');
  expect(below.cursor).toStrictEqual([1, 0]);
  expect(below.vim.mode).toStrictEqual('insert');

  const above = play('one\ntwo', [0, 1], ['O']);

  expect(above.text).toStrictEqual('\none\ntwo');
  expect(above.cursor).toStrictEqual([0, 0]);
});

test('p puts back what was deleted, after the cursor or below the line', () => {
  expect(after(FOX, [0, 4], 'dwp')).toStrictEqual([
    'the bquick rown fox',
    [0, 10],
  ]);
  expect(after('one\ntwo\nthree', [0, 0], 'ddp')).toStrictEqual([
    'two\none\nthree',
    [1, 0],
  ]);
  // The last line's dd takes the line, not the break before it.
  expect(after('one\ntwo', [1, 0], 'ddP')).toStrictEqual(['two\none', [0, 0]]);
  expect(play('one\ntwo', [1, 0], [...'dd']).vim.register).toStrictEqual({
    text: 'two\n',
    linewise: true,
  });
});

test('y yanks into the register and p puts it back: a word, a line, a text object (CHD-215)', () => {
  expect(play(FOX, [0, 4], [...'yw']).vim.register).toStrictEqual({
    text: 'quick ',
    linewise: false,
  });
  expect(after(FOX, [0, 4], 'ywp')).toStrictEqual([
    'the qquick uick brown fox',
    [0, 10],
  ]);
  expect(after('one\ntwo', [0, 0], 'yyp')).toStrictEqual([
    'one\none\ntwo',
    [1, 0],
  ]);
  expect(play('one\ntwo', [0, 0], [...'yy']).vim.register).toStrictEqual({
    text: 'one\n',
    linewise: true,
  });
  // A text object: the word under the cursor, put at the line's end.
  expect(after(FOX, [0, 6], 'yiw$p')).toStrictEqual([
    'the quick brown foxquick',
    [0, 23],
  ]);
});

test('dd keeps a blank line in the register, at the start of a count too', () => {
  expect(after('one\n\ntwo', [1, 0], 'ddp')).toStrictEqual([
    'one\ntwo\n',
    [2, 0],
  ]);
  expect(after('\none\ntwo', [0, 0], '2ddp')).toStrictEqual([
    'two\n\none',
    [1, 0],
  ]);
  expect(after('one\n', [1, 0], 'ddP')).toStrictEqual(['\none', [0, 0]]);
});

test('a counted dd that reaches the last line leaves no blank line', () => {
  expect(after('a\nb\nc', [1, 0], '2dd')).toStrictEqual(['a', [0, 0]]);
  expect(after('a\nb\nc', [1, 0], '5dd')).toStrictEqual(['a', [0, 0]]);
  expect(after('a\n  b\nc\nd', [2, 0], 'dj')).toStrictEqual(['a\n  b', [1, 2]]);
  expect(after('a\nb\nc', [1, 0], '2ddp')).toStrictEqual(['a\nb\nc', [1, 0]]);
});

test('a counted change that reaches the last line keeps its line', () => {
  for (const keys of [
    ['2', 'c', 'c'],
    ['c', 'j'],
  ]) {
    const changed = play('a\nb\nc', [1, 0], keys);

    expect([changed.text, changed.cursor]).toStrictEqual(['a\n', [1, 0]]);
    expect(changed.vim.mode).toStrictEqual('insert');
    expect(typedAt(changed.text, changed.cursor, 'z').text).toStrictEqual(
      'a\nz',
    );
  }
});

test('u undoes one change at a time, back to the start', () => {
  const changed = play(FOX, [0, 4], ['d', 'w', 'x']);

  expect(changed.text).toStrictEqual('the rown fox');

  const once = play(changed.text, changed.cursor, ['u'], changed.vim);

  expect(once.text).toStrictEqual('the brown fox');

  const twice = play(once.text, once.cursor, ['u'], once.vim);

  expect(twice.text).toStrictEqual(FOX);
  expect(twice.cursor).toStrictEqual([0, 4]);
  expect(play(FOX, [0, 4], ['u'], twice.vim).text).toStrictEqual(FOX);
});

test('what insert mode typed is one undo after Esc', () => {
  const opened = play(FOX, [0, 18], ['A']);
  const typed = typedAt(opened.text, opened.cursor, ' jumps');
  const left = vimEscape(opened.vim, typed.text, typed.cursor);

  expect(left.vim.mode).toStrictEqual('normal');
  expect(left.cursor).toStrictEqual([0, 24]);
  expect(play(typed.text, left.cursor, ['u'], left.vim).text).toStrictEqual(
    FOX,
  );
});

test('Esc steps back onto the character insert mode was after', () => {
  expect(vimEscape(startingVim, 'abc', [0, 3]).cursor).toStrictEqual([0, 2]);
  expect(vimEscape(startingVim, '', [0, 0]).cursor).toStrictEqual([0, 0]);
  // Nothing typed is nothing to undo.
  expect(vimEscape(startingVim, '', [0, 0]).vim.undo).toStrictEqual([]);
  expect(vimEscape(startingVim, 'abc', [0, 3]).vim.undo.length).toStrictEqual(
    1,
  );
});

test('a sent prompt leaves insert mode, keeping only the register', () => {
  const deleted = play(FOX, [0, 4], ['d', 'w']);
  const reset = vimReset(deleted.vim);

  expect(reset.mode).toStrictEqual('insert');
  expect(reset.undo).toStrictEqual([]);
  expect(reset.register).toStrictEqual(deleted.vim.register);
});

const IMAGE: PastedImage = {
  id: 1,
  data: '',
  mediaType: 'image/png',
  bytes: 0,
};

test('x and dw take a placeholder whole, never half of it', () => {
  const text = 'see [Image #1] here';
  const cut = play(text, [0, 8], ['x'], NORMAL, [IMAGE]);

  expect(cut.text).toStrictEqual('see  here');
  expect(cut.vim.register).toStrictEqual({
    text: '[Image #1]',
    linewise: false,
  });
  expect(play(text, [0, 5], ['d', 'w'], NORMAL, [IMAGE]).text).toStrictEqual(
    'see  here',
  );
  // Text around it goes as text.
  expect(play(text, [0, 0], ['d', 'w'], NORMAL, [IMAGE]).text).toStrictEqual(
    text.slice(4),
  );
  // A placeholder for no image held is only text.
  expect(play(text, [0, 8], ['x']).text).toStrictEqual('see [Imae #1] here');
});

test('keys normal mode does not take change nothing', () => {
  for (const key of ['v', ':', '/', 'q', 'G', '.']) {
    const step = vimKey(NORMAL, FOX, [0, 4], key);

    expect(step, key).toStrictEqual({ vim: NORMAL, text: FOX, cursor: [0, 4] });
  }

  // After f, any character is the one to find.
  expect(after(FOX, [0, 0], 'f/')).toStrictEqual([FOX, [0, 0]]);
  expect(after(FOX, [0, 0], 'fq')).toStrictEqual([FOX, [0, 4]]);
  expect(vimTakes({ ...NORMAL, pending: ['f'] }, '/')).toStrictEqual(true);
  expect(vimTakes(NORMAL, '/')).toStrictEqual(false);
});

test('a text object follows an operator', () => {
  expect(after(FOX, [0, 6], 'diw')).toStrictEqual(['the  brown fox', [0, 4]]);
  expect(play(FOX, [0, 6], [...'ciw']).vim.mode).toStrictEqual('insert');
});

test("Ink's keys come as the engine names them, a quick burst one by one", () => {
  expect(vimKeyNames('dw', {})).toStrictEqual(['d', 'w']);
  expect(vimKeyNames('', { leftArrow: true })).toStrictEqual(['<Left>']);
  expect(vimKeyNames('', { delete: true })).toStrictEqual(['<BS>']);
  expect(vimKeyNames('w', { ctrl: true })).toStrictEqual([]);
  expect(vimKeyNames('\t', { tab: true })).toStrictEqual([]);
});

test('the cursor stands on a character, and on an empty line on none', () => {
  expect(cursorOffset('ab\ncd', [1, 1])).toStrictEqual(4);
  expect(cursorOffset('ab\ncd', [0, 9])).toStrictEqual(1);
  expect(cursorOffset('ab\n\ncd', [1, 0])).toStrictEqual(undefined);
  expect(cursorOffset('', [0, 0])).toStrictEqual(undefined);
});

test('typing goes in at the cursor, lines and all', () => {
  expect(typedAt('ad', [0, 1], 'bc')).toStrictEqual({
    text: 'abcd',
    cursor: [0, 3],
  });
  expect(typedAt('one\ntwo', [1, 0], 'x')).toStrictEqual({
    text: 'one\nxtwo',
    cursor: [1, 1],
  });
});
