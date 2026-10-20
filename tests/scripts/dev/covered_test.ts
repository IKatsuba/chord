import { expect, test } from 'bun:test';
import { uncovered } from '../../../scripts/dev/covered.ts';

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
