import { afterAll, beforeAll, describe, expect, test } from 'bun:test';
import { rm } from 'node:fs/promises';
import { type Finder, openFinder } from '../../../src/platform/fff.ts';
import { LIMITS } from '../../../src/riff/tools/limits.ts';
import { searcher } from '../../../src/riff/tools/search.ts';
import { makeTree } from '../../fixtures/riff/tree.ts';

const live = () => new AbortController().signal;

/** The files of a search's matches, sorted, once each. */
const files = (answer: string) =>
  [
    ...new Set(
      answer
        .split('\n')
        .filter((line) => /^[^ ]+:\d+: /.test(line))
        .map((line) => line.slice(0, line.indexOf(':'))),
    ),
  ].toSorted();

describe("riff's search in a git repository: fff's set, pinned", () => {
  let root: string;
  let finder: Finder;
  let search: ReturnType<typeof searcher>;

  beforeAll(async () => {
    root = await makeTree(true);
    finder = openFinder(root);
    search = searcher(finder);
  });

  afterAll(async () => {
    await finder.destroy();
    await rm(root, { recursive: true, force: true });
  });

  test("it searches what fff keeps, which is not git's set", async () => {
    // Not searched though git tracks it: tracked.log; never: symlinks and
    // ignored/. Searched though git excludes it: excluded.txt.
    expect(files(await search({ query: 'needle' }, live()))).toEqual([
      '.hidden',
      'excluded.txt',
      'node_modules/pkg/index.js',
      'src/a.ts',
      'src/deep/b.ts',
    ]);
  });

  test('in a regular expression `\\s` crosses a line, reported at its first', async () => {
    expect(
      await search({ query: 'int\\s+foo_probe', regex: true }, live()),
    ).toBe('notes.md:1: static int');
  });

  test('a constraint before the text narrows the search', async () => {
    expect(files(await search({ query: 'src/ needle' }, live()))).toEqual([
      'src/a.ts',
      'src/deep/b.ts',
    ]);
  });

  test('context lines come around a match', async () => {
    expect(await search({ query: 'needle one', context: 1 }, live())).toBe(
      'src/a.ts-1- before\nsrc/a.ts:2: needle one\nsrc/a.ts-3- after',
    );
  });

  test('a page names how to read on, and a page riff never gave is refused', async () => {
    const first = await search({ query: 'needle', limit: 1 }, live());

    expect(first).toMatch(/… more matches; search again with page "p\d+"\.$/);

    const page = /page "(p\d+)"/.exec(first)![1]!;
    const next = await search({ query: 'needle', limit: 1, page }, live());

    expect(files(next)).not.toEqual(files(first));
    await expect(
      search({ query: 'needle', page: 'p999' }, live()),
    ).rejects.toThrow('no page p999; search again without it');
  });

  test('nothing found says so', async () => {
    expect(await search({ query: 'absent-text' }, live())).toBe(
      'Nothing matches.',
    );
  });

  test('an aborted search rejects with its reason', async () => {
    const controller = new AbortController();
    const reason = new Error('stopped');

    controller.abort(reason);

    await expect(search({ query: 'needle' }, controller.signal)).rejects.toBe(
      reason,
    );
  });
});

describe("riff's search outside a git repository: fff's set, pinned", () => {
  test('dotfiles and node_modules are not searched', async () => {
    const root = await makeTree(false);
    const finder = openFinder(root);

    try {
      expect(
        files(await searcher(finder)({ query: 'needle' }, live())),
      ).toEqual(['excluded.txt', 'src/a.ts', 'src/deep/b.ts']);
    } finally {
      await finder.destroy();
      await rm(root, { recursive: true, force: true });
    }
  });
});

describe("riff's search asks fff for its limits", () => {
  test('page, per-file cap, context and an enforced time budget', async () => {
    const asked: unknown[] = [];
    const finder = {
      grep: (query: string, options: unknown) => {
        asked.push([query, options]);

        return Promise.resolve({
          items: [],
          totalMatched: 0,
          totalFilesSearched: 0,
          totalFiles: 0,
          filteredFileCount: 0,
          nextCursor: null,
        });
      },
    } as unknown as Finder;

    await searcher(finder)(
      { query: 'x', regex: true, context: 99, limit: 9999 },
      live(),
    );

    expect(asked).toStrictEqual([
      [
        'x',
        {
          mode: 'regex',
          cursor: null,
          pageSize: LIMITS.searchMax,
          maxMatchesPerFile: LIMITS.searchPerFile,
          timeBudgetMs: LIMITS.searchMs,
          enforceTimeBudget: true,
          beforeContext: LIMITS.searchContext,
          afterContext: LIMITS.searchContext,
        },
      ],
    ]);
  });
});
