import { describe, expect, test } from 'bun:test';
import { spawnSync } from 'node:child_process';
import {
  cp,
  mkdtemp,
  readFile,
  rm,
  symlink,
  writeFile,
} from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
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

describe('tester: direct lint process boundaries', () => {
  test('fix flags, literal empty arguments and ESLint failure status reach the package caller', async () => {
    const root = join(import.meta.dir, '..', '..');
    const dir = await mkdtemp(join(tmpdir(), 'chord-lint-tester-'));

    try {
      await cp(join(root, 'scripts'), join(dir, 'scripts'), {
        recursive: true,
      });
      await symlink(join(root, 'node_modules'), join(dir, 'node_modules'));
      await writeFile(
        join(dir, 'package.json'),
        JSON.stringify({
          type: 'module',
          scripts: { lint: 'bun scripts/lint.ts', eslint: 'bun eslint.ts' },
        }),
      );
      await writeFile(
        join(dir, 'eslint.ts'),
        [
          "import { writeFileSync } from 'node:fs';",
          "writeFileSync('arguments.json', JSON.stringify(process.argv.slice(2)));",
          'process.exit(Number(process.env.LINT_FIXTURE_STATUS));',
        ].join('\n'),
      );

      for (const status of [0, 23]) {
        const result = spawnSync(
          process.execPath,
          ['lint', '--fix', '--', 'a b.ts', ''],
          {
            cwd: dir,
            encoding: 'utf8',
            timeout: 10_000,
            env: { ...process.env, LINT_FIXTURE_STATUS: String(status) },
          },
        );

        expect(result.error).toBeUndefined();
        expect(result.status, result.stdout + result.stderr).toBe(status);
        expect(
          JSON.parse(await readFile(join(dir, 'arguments.json'), 'utf8')),
        ).toEqual(['.', '--fix', 'a b.ts', '']);
      }
    } finally {
      await rm(dir, { recursive: true, force: true });
    }
  });
});
