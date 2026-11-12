import { describe, expect, test } from 'bun:test';
import { spawnSync } from 'node:child_process';
import { mkdtemp, readdir, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { build, foreign, here, PACKED, tooOld } from '../../scripts/tools.ts';

test("foreign names a build's inputs outside the package's src/, by a path from the cwd or absolute", () => {
  const root = join(here, '..', '..');

  expect(
    foreign(
      [
        'packages/cursor-cloud-acp/src/bin.ts',
        join(here, 'src', 'main.ts'),
        'node_modules/.bun/@cursor+sdk@1.3.1/node_modules/@cursor/sdk/dist/esm/index.js',
        'packages/cursor-cloud-acp/scripts/tools.ts',
        'packages/cursor-cloud-acp/srcs/a.ts',
      ],
      root,
    ),
  ).toEqual([
    'node_modules/.bun/@cursor+sdk@1.3.1/node_modules/@cursor/sdk/dist/esm/index.js',
    'packages/cursor-cloud-acp/scripts/tools.ts',
    'packages/cursor-cloud-acp/srcs/a.ts',
  ]);
});

describe('CHD-622 tester: built Node launcher', () => {
  test('Node reports a thrown error or primitive without a stack or stdout', async () => {
    const outdir = await mkdtemp(
      join(tmpdir(), 'cursor-cloud-acp-node-error-'),
    );

    try {
      expect(await build({ output: () => undefined }, outdir)).toBe(0);
      await writeFile(join(outdir, 'package.json'), '{"type":"module"}\n');

      for (const thrown of [
        "Object.assign(new Error('fixture failure'), { stack: 'private-stack-marker' })",
        "'fixture failure'",
      ]) {
        await writeFile(
          join(outdir, 'main.js'),
          `export function main() { throw ${thrown}; }\n`,
        );

        const result = spawnSync('node', [join(outdir, 'bin.js')], {
          encoding: 'utf8',
          stdio: ['ignore', 'pipe', 'pipe'],
          timeout: 5000,
        });

        expect(result.error).toBeUndefined();
        expect(result.signal).toBeNull();
        expect(result.status).toBe(1);
        expect(result.stdout).toBe('');
        expect(result.stderr).toBe('cursor-cloud-acp: fixture failure\n');
      }
    } finally {
      await rm(outdir, { recursive: true, force: true });
    }
  });

  test('rejects old versions before loading main and forwards arguments and exit status on supported versions', async () => {
    const outdir = await mkdtemp(join(tmpdir(), 'cursor-cloud-acp-node-'));

    try {
      expect(await build({ output: () => undefined }, outdir)).toBe(0);
      await writeFile(join(outdir, 'package.json'), '{"type":"module"}\n');
      await writeFile(
        join(outdir, 'main.js'),
        'export function main(args) { process.stdout.write(JSON.stringify(args)); return 7; }\n',
      );

      for (const version of ['21.99.0', '22.12.999', '22.13.0', '23.0.0']) {
        const accepted = version === '22.13.0' || version === '23.0.0';
        const result = spawnSync(
          'node',
          [
            '--input-type=module',
            '-e',
            `Object.defineProperty(process.versions, 'node', { value: ${JSON.stringify(version)} }); process.argv = ['node', 'bin.js', 'login', 'a b', '']; await import(${JSON.stringify(pathToFileURL(join(outdir, 'bin.js')).href)});`,
          ],
          {
            encoding: 'utf8',
            stdio: ['ignore', 'pipe', 'pipe'],
            timeout: 5000,
          },
        );

        expect(result.error).toBeUndefined();
        expect(result.signal).toBeNull();
        expect(result.status).toBe(accepted ? 7 : 1);
        expect(result.stdout).toBe(accepted ? '["login","a b",""]' : '');
        expect(result.stderr).toBe(
          accepted
            ? ''
            : `cursor-cloud-acp needs Node 22.13 or newer; this is Node ${version}.\n`,
        );
      }
    } finally {
      await rm(outdir, { recursive: true, force: true });
    }
  });
});

test('a main that rejects ends the built bin.js with one line and status 1, never a stack', async () => {
  const outdir = await mkdtemp(join(tmpdir(), 'cursor-cloud-acp-reject-'));

  try {
    expect(await build({ output: () => undefined }, outdir)).toBe(0);
    await writeFile(
      join(outdir, 'main.js'),
      "export function main() { return Promise.reject(new Error('Usage limit exceeded')); }\n",
    );

    const run = spawnSync(process.execPath, [join(outdir, 'bin.js')], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
    });

    expect(run.stderr).toBe('cursor-cloud-acp: Usage limit exceeded\n');
    expect(run.stdout).toBe('');
    expect(run.status).toBe(1);
  } finally {
    await rm(outdir, { recursive: true, force: true });
  }
});

test("build writes bin.js, whose only import is main's chunk, after Node's version is checked", async () => {
  const outdir = await mkdtemp(join(tmpdir(), 'cursor-cloud-acp-build-'));
  const lines: string[] = [];

  try {
    expect(await build({ output: (line) => lines.push(line) }, outdir)).toBe(0);
    expect(lines).toEqual([]);

    const bin = await readFile(join(outdir, 'bin.js'), 'utf8');

    expect(bin.startsWith('#!/usr/bin/env node\n')).toBe(true);
    expect(bin.match(/\bimport\b[^)]*\)/g)).toEqual(['import("./main.js")']);
    expect(bin.indexOf('process.exit(1)')).toBeLessThan(bin.indexOf('import('));
    expect((await readdir(outdir)).toSorted()).toEqual(['bin.js', 'main.js']);
  } finally {
    await rm(outdir, { recursive: true, force: true });
  }
});

test("tooOld refuses a Node below 22.13, naming it as the node found past Bun's", () => {
  expect(tooOld('v22.13.0')).toBeUndefined();
  expect(tooOld('v24.1.0')).toBeUndefined();
  expect(tooOld('v22.12.0')).toBe(
    "the smoke needs Node 22.13 or newer; v22.12.0 is the first node past Bun's on PATH",
  );
});

test('the tarball holds dist, README.md, LICENSE and package.json alone, as files names them', async () => {
  const manifest = JSON.parse(
    await readFile(join(here, 'package.json'), 'utf8'),
  ) as { files: string[] };

  expect(manifest.files).toEqual(['dist', 'README.md', 'LICENSE']);
  expect(PACKED).toEqual([
    'LICENSE',
    'README.md',
    'dist/bin.js',
    'dist/main.js',
    'package.json',
  ]);
});
