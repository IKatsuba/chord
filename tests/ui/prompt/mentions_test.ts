import { describe, expect, test } from 'bun:test';
import { mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { listFiles } from '../../../src/files.ts';
import {
  insertMention,
  firstFiles,
  matchFiles,
  mentionAt,
  mentionsIn,
} from '../../../src/ui/prompt/mentions.ts';

test('an @ at the start of a word opens a mention, up to the cursor', () => {
  expect(mentionAt('@', [0, 1])).toStrictEqual({
    query: '',
    line: 0,
    column: 0,
  });
  expect(mentionAt('look at @src/ma', [0, 15])).toStrictEqual({
    query: 'src/ma',
    line: 0,
    column: 8,
  });
  expect(mentionAt('one\ntwo @a', [1, 6])).toStrictEqual({
    query: 'a',
    line: 1,
    column: 4,
  });
  // The part before the cursor is what is matched.
  expect(mentionAt('@src/main.ts', [0, 4])?.query).toStrictEqual('src');
});

test('an @ inside a word, or a space after it, is no mention', () => {
  expect(mentionAt('me@example.com', [0, 14])).toStrictEqual(undefined);
  expect(mentionAt('@src/main.ts ', [0, 13])).toStrictEqual(undefined);
  expect(mentionAt('no at sign', [0, 10])).toStrictEqual(undefined);
  expect(mentionAt('@a', [3, 0])).toStrictEqual(undefined);
});

const FILES = [
  'README.md',
  'deno.json',
  'src/main.tsx',
  'src/ui/App.tsx',
  'src/ui/state.ts',
  'tests/state_test.ts',
];

test('the files match fuzzily, the shorter path first on a tie', async () => {
  expect(await matchFiles(FILES, 'stt')).toStrictEqual([
    'src/ui/state.ts',
    'tests/state_test.ts',
  ]);
  expect((await matchFiles(FILES, 'APP'))?.[0]).toStrictEqual('src/ui/App.tsx');
  expect(await matchFiles(FILES, 'zzz')).toStrictEqual([]);
  expect(firstFiles(FILES)).toStrictEqual(FILES);
});

test('a picked file takes the place of the mention, with a space after', () => {
  const draft = 'look at @stt please';
  const cursor = [0, 12] as const;
  const mention = mentionAt(draft, cursor)!;

  expect(
    insertMention(draft, cursor, mention, 'src/ui/state.ts'),
  ).toStrictEqual({
    text: 'look at @src/ui/state.ts please',
    cursor: [0, 25],
  });
  // At the end of the draft the space is added, and the cursor goes past it.
  expect(
    insertMention('@a', [0, 2], mentionAt('@a', [0, 2])!, 'a.ts'),
  ).toStrictEqual({
    text: '@a.ts ',
    cursor: [0, 6],
  });
  // The rest of a path the cursor stood inside goes too.
  expect(
    insertMention('@srcmain', [0, 4], mentionAt('@srcmain', [0, 4])!, 'b.ts')
      .text,
  ).toStrictEqual('@b.ts ');
  // A path with a space in it is quoted.
  expect(
    insertMention(
      'one\n@my',
      [1, 3],
      mentionAt('one\n@my', [1, 3])!,
      'my f.md',
    ),
  ).toStrictEqual({ text: 'one\n@"my f.md" ', cursor: [1, 11] });
});

test('the walk leaves out .git and what .gitignore names, the top first', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'chord-files-'));

  try {
    for (const path of ['.git/HEAD', 'dist/out.js', 'src/ui/App.tsx']) {
      await mkdir(join(dir, path, '..'), { recursive: true });
      await writeFile(join(dir, path), '');
    }

    await writeFile(join(dir, '.gitignore'), 'dist/\n*.log\n');
    await writeFile(join(dir, 'debug.log'), '');
    await writeFile(join(dir, 'README.md'), '');
    await writeFile(join(dir, 'src/ui/.gitignore'), 'gen.ts\n');
    await writeFile(join(dir, 'src/ui/gen.ts'), '');
    await writeFile(join(dir, 'src/main.ts'), '');

    expect(await listFiles(dir)).toStrictEqual([
      '.gitignore',
      'README.md',
      'src/main.ts',
      'src/ui/.gitignore',
      'src/ui/App.tsx',
    ]);
  } finally {
    await rm(dir, { recursive: true });
  }
});

test('a prompt mentions each @path at the start of a word, quoted as a pick writes it', () => {
  expect(
    mentionsIn('@a.ts and @"my notes.md"\nthen @src/b.ts, not me@there.com'),
  ).toStrictEqual(['a.ts', 'my notes.md', 'src/b.ts,']);
  expect(mentionsIn('a lone @ and none')).toStrictEqual([]);
});

test('a picked path reads back as the one mention it is', () => {
  for (const path of ['src/main.ts', 'my notes.md']) {
    const { text } = insertMention(
      'look at @',
      [0, 9],
      mentionAt('look at @', [0, 9])!,
      path,
    );

    expect(mentionsIn(text)).toStrictEqual([path]);
  }
});

test('a newer match cancels the one still running, which comes back as none', async () => {
  // More files than AsyncFzf scores in one step, so the first find yields.
  const many = Array.from({ length: 5000 }, (_, at) => `src/file${at}.ts`);
  const first = matchFiles(many, 'file1');
  const second = matchFiles(many, 'file42');

  expect(await first).toStrictEqual(undefined);
  expect((await second)?.[0]).toStrictEqual('src/file42.ts');
});

test('the match runs off the call that starts it: the call returns before the scoring ends', () => {
  const many = Array.from({ length: 50_000 }, (_, at) => `src/file${at}.ts`);
  let done = false;

  void matchFiles(many, 'fl9').then(() => {
    done = true;
  });

  // AsyncFzf scores a step, then yields: nothing has come back yet.
  expect(done).toStrictEqual(false);
});

describe('CHD-398 tester: async matching yields and cancels', () => {
  const paths = Array.from(
    { length: 20_001 },
    (_, index) => `src/package-${index % 37}/token-${index}.ts`,
  );

  test('a large in-memory match lets a timer run before its result', async () => {
    let ticks = 0;
    const timer = setInterval(() => {
      ticks++;
    }, 1);

    try {
      const result = await matchFiles(paths, 'src');

      expect(result?.length).toBe(100);
      expect(ticks).toBeGreaterThan(0);
    } finally {
      clearInterval(timer);
    }
  });

  test('a newer query cancels real AsyncFzf work, without returning old paths', async () => {
    const old = matchFiles(paths, 'src');
    const current = matchFiles(paths, 'token-19999');

    expect(await old).toBeUndefined();
    expect((await current)?.[0]).toEndWith('/token-19999.ts');
  });
});
