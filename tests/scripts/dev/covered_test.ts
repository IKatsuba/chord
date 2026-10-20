import { expect, test } from 'bun:test';
import { execFileSync } from 'node:child_process';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { trackedFiles, uncovered } from '../../../scripts/dev/covered.ts';

const root = '/work/chord';

test('a tracked TypeScript file missing from tsc’s list is named, by its exact case (CHD-474)', () => {
  const tracked = [
    'src/main.tsx',
    'tests/ui/app/strip_test.ts',
    'tests/ui/app/Strip_test.tsx',
    'README.md',
    'scripts/mark.svg',
  ];
  // As tsc lists them on a file system that ignores case: one of the pair,
  // and files outside the tree, Bun's types among them.
  const listed = [
    `${root}/node_modules/bun-types/index.d.ts`,
    `${root}/src/main.tsx`,
    `${root}/tests/ui/app/strip_test.ts`,
  ];

  expect(uncovered(tracked, listed, root)).toStrictEqual([
    'tests/ui/app/Strip_test.tsx',
  ]);
  expect(
    uncovered(
      tracked,
      [...listed, `${root}/tests/ui/app/Strip_test.tsx`],
      root,
    ),
  ).toStrictEqual([]);
});

test('eslint.config.ts is left out by name until the owner settles its types (CHD-474 Q64)', () => {
  expect(
    uncovered(['eslint.config.ts', 'lint/style.ts'], [], root),
  ).toStrictEqual(['lint/style.ts']);
});

test('a tracked name git would quote, with a quote or a non-ASCII letter, is read as it is and found missing (CHD-474)', async () => {
  const repo = await mkdtemp(join(tmpdir(), 'chord-covered-'));

  try {
    const names = ['a"b.ts', 'café.tsx', 'plain.ts'];
    const git = (...args: string[]) =>
      execFileSync('git', args, { cwd: repo, stdio: 'pipe' });

    git('init', '-q');

    for (const name of names) {
      await writeFile(join(repo, name), 'export {};\n');
    }

    git('add', '.');

    // git ls-files without -z would give "a\"b.ts" and "caf\303\251.tsx".
    expect(trackedFiles(repo).toSorted()).toStrictEqual(names.toSorted());
    expect(
      uncovered(trackedFiles(repo), [join(repo, 'plain.ts')], repo).toSorted(),
    ).toStrictEqual(['a"b.ts', 'café.tsx']);
  } finally {
    await rm(repo, { recursive: true, force: true });
  }
});
