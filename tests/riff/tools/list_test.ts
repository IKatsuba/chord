import { afterAll, beforeAll, describe, expect, test } from 'bun:test';
import { rm } from 'node:fs/promises';
import { type Finder, openFinder } from '../../../src/platform/fff.ts';
import { list } from '../../../src/riff/tools/list.ts';
import { makeTree } from '../../fixtures/riff/tree.ts';

const live = () => new AbortController().signal;

/** The entries of a list's answer, sorted, without its footer. */
const entries = (answer: string) =>
  answer
    .split('\n')
    .filter((line) => !line.startsWith('…'))
    .toSorted();

describe("riff's list in a git repository: fff's set, pinned", () => {
  let root: string;
  let finder: Finder;

  beforeAll(async () => {
    root = await makeTree(true);
    finder = openFinder(root);
  });

  afterAll(async () => {
    await finder.destroy();
    await rm(root, { recursive: true, force: true });
  });

  test("`*` crosses `/`: every file fff keeps, which is not git's set", async () => {
    // Left out though git lists them: tracked.log (tracked, matching an
    // ignore rule) and both symlinks. Listed though git leaves it out:
    // excluded.txt (.git/info/exclude). Dotfiles and node_modules stay.
    expect(entries(await list(finder, { pattern: '*' }, live()))).toEqual([
      '.gitignore',
      '.hidden',
      'excluded.txt',
      'node_modules/pkg/index.js',
      'notes.md',
      'src/a.ts',
      'src/deep/b.ts',
    ]);
  });

  test('a pattern without `/` matches at any depth, and `src/*` all under src/', async () => {
    expect(entries(await list(finder, { pattern: '*.ts' }, live()))).toEqual([
      'src/a.ts',
      'src/deep/b.ts',
    ]);
    expect(entries(await list(finder, { pattern: 'src/*' }, live()))).toEqual([
      'src/a.ts',
      'src/deep/b.ts',
    ]);
  });

  test('directories come from the fuzzy directory search', async () => {
    const found = entries(
      await list(finder, { pattern: '', directories: true }, live()),
    );

    expect(found).toContain('src/deep/');
    expect(found).not.toContain('ignored/');
    expect(found.some((path) => path.startsWith('linked'))).toBe(false);
  });

  test('nothing outside the directory is reached', async () => {
    expect(await list(finder, { pattern: '../*' }, live())).toBe(
      'Nothing matches.',
    );
    expect(await list(finder, { pattern: '/etc/*' }, live())).toBe(
      'Nothing matches.',
    );
  });

  test('a page says which offset lists on', async () => {
    const first = await list(finder, { pattern: '*', limit: 2 }, live());

    expect(first.split('\n')).toHaveLength(3);
    expect(first).toEndWith('… 2 of 7; list on with offset 2.');

    const last = await list(
      finder,
      { pattern: '*', limit: 2, offset: 6 },
      live(),
    );

    expect(last.split('\n')).toHaveLength(1);
    expect(await list(finder, { pattern: '*', offset: 9 }, live())).toBe(
      '7 match; nothing from offset 9.',
    );
  });

  test('an aborted list rejects with its reason', async () => {
    const controller = new AbortController();
    const reason = new Error('stopped');

    controller.abort(reason);

    await expect(
      list(finder, { pattern: '*' }, controller.signal),
    ).rejects.toBe(reason);
  });
});

describe("riff's list outside a git repository: fff's set, pinned", () => {
  test('dotfiles and node_modules are left out, .gitignore still holds', async () => {
    const root = await makeTree(false);
    const finder = openFinder(root);

    try {
      expect(entries(await list(finder, { pattern: '*' }, live()))).toEqual([
        'excluded.txt',
        'notes.md',
        'src/a.ts',
        'src/deep/b.ts',
      ]);
    } finally {
      await finder.destroy();
      await rm(root, { recursive: true, force: true });
    }
  });
});
