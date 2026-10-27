import { expect, test } from 'bun:test';
import { lintCommand } from '../../scripts/lint.ts';

/** The arguments passed to ESLint, with no tool run. */
async function parsed(argv: string[]) {
  const calls: (readonly string[])[] = [];

  await lintCommand((args) => void calls.push(args))
    .noExit()
    .throwErrors()
    .parse(argv);

  return calls;
}

test('ESLint flags and words retain their forwarding boundaries', async () => {
  expect(await parsed(['--fix', 'a b', '--quiet'])).toEqual([
    ['--fix', 'a b', '--quiet'],
  ]);
  expect(await parsed(['--fix', '--', '--quiet', ''])).toEqual([
    ['--fix', '--quiet', ''],
  ]);
  expect(await parsed(['--fix', ''])).toEqual([['--fix']]);
  expect(await parsed(['--', '--help'])).toEqual([['--help']]);
});
