import { describe, expect, test } from 'bun:test';
import { ValidationError } from '@cliffy/command';
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
import process from 'node:process';
import { qualityCommand } from '../../scripts/quality.ts';

/** Parses without running a tool. */
async function parsed(argv: string[]) {
  const calls: unknown[][] = [];

  await qualityCommand({
    check: (options) => void calls.push(['check', options]),
    lint: (args) => void calls.push(['lint', args]),
    fmt: () => void calls.push(['fmt']),
  })
    .noExit()
    .throwErrors()
    .parse(argv);

  return calls;
}

describe('quality package commands', () => {
  test('check runs everything, or only static checks', async () => {
    expect(await parsed(['check'])).toEqual([['check', { static: false }]]);
    expect(await parsed(['check', '--static'])).toEqual([
      ['check', { static: true }],
    ]);
  });

  test('check and fmt refuse extra arguments and unknown options', async () => {
    for (const argv of [
      ['check', 'tests/'],
      ['check', '--fix'],
      ['check', '--static', 'extra'],
      ['fmt', 'src/'],
      ['fmt', '--fix'],
    ]) {
      await expect(parsed(argv)).rejects.toThrow(ValidationError);
    }

    expect(await parsed(['fmt'])).toEqual([['fmt']]);
  });

  test('lint forwards words and options, with literal empty arguments', async () => {
    expect(await parsed(['lint', '--fix', 'a b', '--', ''])).toEqual([
      ['lint', ['--fix', 'a b', '']],
    ]);
    expect(await parsed(['lint', '--', '--help'])).toEqual([
      ['lint', ['--help']],
    ]);
  });

  test('action failures reach the caller', async () => {
    const failure = new Error('fixture action failed');

    await expect(
      qualityCommand({
        check: () => {},
        fmt: () => {},
        lint: async () => {
          await Promise.resolve();

          throw failure;
        },
      })
        .noExit()
        .throwErrors()
        .parse(['lint']),
    ).rejects.toBe(failure);
  });
});

test('Bun resolves quality scripts and preserves forwarded argv and tool status', async () => {
  const root = join(import.meta.dir, '..', '..');
  const dir = await mkdtemp(join(tmpdir(), 'chord-quality-'));
  const manifest = JSON.parse(
    await readFile(join(root, 'package.json'), 'utf8'),
  ) as {
    scripts: Record<string, string>;
  };

  try {
    await cp(join(root, 'scripts'), join(dir, 'scripts'), { recursive: true });
    await symlink(join(root, 'node_modules'), join(dir, 'node_modules'));
    await writeFile(
      join(dir, 'package.json'),
      JSON.stringify({
        type: 'module',
        scripts: {
          ...manifest.scripts,
          eslint: 'bun tool.ts',
          prettier: 'bun tool.ts',
          tsc: 'bun tool.ts',
        },
      }),
    );
    await writeFile(
      join(dir, 'tool.ts'),
      "await Bun.write('argv.json', JSON.stringify(process.argv.slice(2))); process.exit(Number(process.env.TOOL_STATUS ?? 0));\n",
    );

    const run = (args: string[], status = 0) => {
      const result = spawnSync(process.execPath, args, {
        cwd: dir,
        encoding: 'utf8',
        env: { ...process.env, TOOL_STATUS: String(status) },
        timeout: 20_000,
      });

      expect(result.error).toBeUndefined();

      return result;
    };

    const argv = async () =>
      JSON.parse(await readFile(join(dir, 'argv.json'), 'utf8')) as unknown;

    expect(run(['lint', '--fix', 'a b', '--', ''], 7).status).toBe(7);
    expect(await argv()).toEqual(['.', '--fix', 'a b', '']);
    expect(run(['run', 'fmt']).status).toBe(0);
    expect(await argv()).toEqual(['--write', '.']);
    expect(run(['run', 'fmt', '--fix']).status).not.toBe(0);

    for (const args of [
      ['run', 'fmt', '--help'],
      ['run', 'check', '--help'],
    ]) {
      const result = run(args);

      expect(result.status).toBe(0);
      expect(result.stdout).toContain('Usage:');
      expect(result.stdout).toContain('bun run');
    }

    const failed = run(['check', '--static'], 9);

    expect(failed.status).toBe(9);
    expect(failed.stderr).toContain('check: tsc failed with status 9');
    expect(await argv()).toEqual([]);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});
