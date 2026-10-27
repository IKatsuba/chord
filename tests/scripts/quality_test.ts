import { describe, expect, test } from 'bun:test';
import { ValidationError } from '@cliffy/command';
import { spawnSync } from 'node:child_process';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import process from 'node:process';
import { qualityCommand } from '../../scripts/quality.ts';

/** Parses without running a tool. */
async function parsed(argv: string[]) {
  const calls: unknown[] = [];

  await qualityCommand((options) => void calls.push(options))
    .noExit()
    .throwErrors()
    .parse(argv);

  return calls;
}

describe('quality aggregate', () => {
  test('runs everything, or only static checks', async () => {
    expect(await parsed([])).toEqual([{ static: false }]);
    expect(await parsed(['--static'])).toEqual([{ static: true }]);
  });

  test('refuses extra arguments and unknown options', async () => {
    for (const argv of [['tests/'], ['--fix'], ['--static', 'extra']]) {
      await expect(parsed(argv)).rejects.toThrow(ValidationError);
    }
  });

  test('action failures reach the caller', async () => {
    const failure = new Error('fixture action failed');

    await expect(
      qualityCommand(async () => {
        await Promise.resolve();

        throw failure;
      })
        .noExit()
        .throwErrors()
        .parse([]),
    ).rejects.toBe(failure);
  });
});

test('native formatting and types retain their own arguments and failure statuses', async () => {
  const root = join(import.meta.dir, '..', '..');
  const dir = await mkdtemp(join(tmpdir(), 'chord-native-quality-'));

  try {
    await writeFile(join(dir, 'package.json'), '{"type":"module"}');
    await writeFile(
      join(dir, '.prettierrc.json'),
      await readFile(join(root, '.prettierrc.json')),
    );
    await writeFile(
      join(dir, 'tsconfig.json'),
      '{"compilerOptions":{"strict":true},"include":["sample.ts"]}',
    );
    await writeFile(join(dir, 'sample.ts'), 'export const value:number="hi"');

    const run = (args: string[]) => {
      const result = spawnSync(process.execPath, args, {
        cwd: dir,
        encoding: 'utf8',
        timeout: 20_000,
      });

      expect(result.error).toBeUndefined();

      return result;
    };

    expect(run(['fmt', '--check', 'sample.ts']).status).toBe(1);
    expect(run(['fmt', 'sample.ts']).status).toBe(0);
    expect(await readFile(join(dir, 'sample.ts'), 'utf8')).toBe(
      "export const value: number = 'hi';\n",
    );
    expect(run(['fmt', '--check', 'sample.ts']).status).toBe(0);

    const failed = run(['check']);

    expect(failed.status).toBe(1);
    expect(failed.stdout).toContain('TS2322');
    await writeFile(
      join(dir, 'sample.ts'),
      'export const value: number = 1;\n',
    );
    expect(run(['check']).status).toBe(0);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});
