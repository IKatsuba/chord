import { expect, test } from 'bun:test';
import { spawnSync } from 'node:child_process';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import steps from '../steps.ts';
import { isPublish } from '../scripts/dev/steps.ts';

test("chord's checks are the six, in order, only the suite not static", () => {
  expect(
    steps.checks.map((check) => [check.name, check.static === true]),
  ).toEqual([
    ['types', true],
    ['covered', true],
    ['eslint', true],
    ['format', true],
    ["lint/'s tests", true],
    ['the suite', false],
  ]);
});

test("chord's checks are today's argv: Bun's check, covered, ESLint, Bun's fmt, lint/'s tests, the suite", () => {
  const bun = process.execPath;

  expect(steps.checks.map((check) => check.run)).toEqual([
    [bun, 'check'],
    [bun, 'scripts/dev/covered.ts'],
    [bun, 'run', 'eslint', '.'],
    [bun, 'fmt', '--check', '.'],
    [bun, 'test', 'lint/'],
    [bun, 'scripts/dev.ts', 'test'],
  ]);
  expect(steps.lint).toEqual([bun, 'run', 'eslint', '.']);
});

test('no check of chord names packages/, the other packages', () => {
  for (const check of steps.checks) {
    expect(JSON.stringify(check.run)).not.toContain('packages');
  }
});

test("chord's release is today's nine stages, check renamed quality", () => {
  expect(steps.release.map((stage) => stage.name)).toEqual([
    'install',
    'quality',
    'natives',
    'compile',
    'sign',
    'selftest',
    'notarise',
    'pack',
    'publish',
  ]);
});

test('signing stages need the arm64 Mac, and compile carries the version', () => {
  const stages = steps.release.filter((stage) => !isPublish(stage));

  expect(
    stages.filter((stage) => 'machine' in stage).map((stage) => stage.name),
  ).toEqual(['natives', 'sign', 'notarise']);
  expect(
    stages.filter((stage) => 'versioned' in stage).map((stage) => stage.name),
  ).toEqual(['compile']);
});

test("publish sends chord's five npm names, the main one last, with a GitHub release", () => {
  const publish = steps.release.at(-1)!;

  expect(publish).toEqual({
    name: 'publish',
    npm: [
      '@chorded/chord-darwin-arm64',
      '@chorded/chord-darwin-x64',
      '@chorded/chord-linux-arm64',
      '@chorded/chord-linux-x64',
      '@chorded/chord',
    ],
    tag: 'v{version}',
    githubRelease: true,
  });
});

test('native formatting and types keep their own arguments and failure statuses', async () => {
  const root = join(import.meta.dir, '..');
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
