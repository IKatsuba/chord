import { expect, test } from 'bun:test';
import { mkdtemp, readdir, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { build, foreign, here } from '../../scripts/tools.ts';

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
