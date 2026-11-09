import { afterEach, beforeEach, describe, expect, test } from 'bun:test';
import { spawnSync } from 'node:child_process';
import { mkdir, mkdtemp, realpath, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { buildOptions, withFffWorker } from '../../scripts/dev/compile.ts';
import { type Finder, openFinder } from '../../src/platform/fff.ts';

const FIXTURE = fileURLToPath(
  new URL('../fixtures/fff/main.ts', import.meta.url),
);

const live = () => new AbortController().signal;

describe('the fff finder in its Worker', () => {
  let root: string;
  let finder: Finder;

  beforeEach(async () => {
    root = await realpath(await mkdtemp(join(tmpdir(), 'chord-fff-')));

    await mkdir(join(root, 'src', 'deep'), { recursive: true });
    await writeFile(join(root, 'src', 'a.ts'), 'before\nneedle one\nafter\n');
    await writeFile(join(root, 'src', 'deep', 'b.ts'), 'needle two\n');
    await writeFile(join(root, 'notes.md'), 'nothing here\n');

    finder = openFinder(root);
  });

  afterEach(async () => {
    await finder.destroy();
    await rm(root, { recursive: true, force: true });
  });

  test('greps with context lines', async () => {
    const result = await finder.grep(
      'needle',
      { beforeContext: 1, afterContext: 1 },
      live(),
    );
    const found = result.items
      .map((item) => `${item.relativePath}:${item.lineNumber}`)
      .toSorted();

    expect(found).toEqual(['src/a.ts:2', 'src/deep/b.ts:1']);

    const a = result.items.find((item) => item.relativePath === 'src/a.ts');

    expect(a?.contextBefore).toEqual(['before']);
    expect(a?.contextAfter).toEqual(['after']);
  });

  test('globs files and searches directories', async () => {
    const files = await finder.glob('*.ts', {}, live());

    expect(files.items.map((item) => item.relativePath).toSorted()).toEqual([
      'src/a.ts',
      'src/deep/b.ts',
    ]);

    const directories = await finder.directorySearch('', {}, live());

    expect(directories.items.map((item) => item.relativePath)).toContain(
      'src/deep/',
    );
  });

  test('an aborted call rejects with its reason, and the next call still answers', async () => {
    const controller = new AbortController();
    const reason = new Error('stopped');
    const aborted = finder.grep('needle', {}, controller.signal);

    controller.abort(reason);

    expect(aborted).rejects.toBe(reason);

    // The Worker was ended; a new one scans again and answers.
    const result = await finder.glob('*.md', {}, live());

    expect(result.items.map((item) => item.relativePath)).toEqual(['notes.md']);
  });

  test('a call the abort did not concern is sent again and answers', async () => {
    const controller = new AbortController();
    const aborted = finder.grep('needle', {}, controller.signal);
    const other = finder.glob('*.md', {}, live());

    controller.abort();

    expect(aborted).rejects.toBeDefined();
    expect((await other).items.map((item) => item.relativePath)).toEqual([
      'notes.md',
    ]);
  });

  test('a call on an aborted signal never starts', () => {
    const controller = new AbortController();

    controller.abort(new Error('already'));

    expect(finder.grep('needle', {}, controller.signal)).rejects.toThrow(
      'already',
    );
  });

  test('after destroy, calls fail and a second destroy is harmless', async () => {
    await finder.glob('*.ts', {}, live());
    await finder.destroy();

    expect(finder.glob('*.ts', {}, live())).rejects.toThrow(
      'fff: the finder is destroyed',
    );

    await finder.destroy();
  });

  test('a directory fff cannot open fails the call with its reason', async () => {
    const missing = openFinder(join(root, 'missing'));

    try {
      expect(missing.glob('*', {}, live())).rejects.toThrow(/^fff: /);
    } finally {
      await missing.destroy();
    }
  });
});

test('compiled with its Worker as an entry point, as chord is, the finder answers with no node_modules', async () => {
  const directory = await realpath(
    await mkdtemp(join(tmpdir(), 'chord-fff-compiled-')),
  );
  const binary = join(directory, 'fff');
  const project = join(directory, 'project');

  try {
    await mkdir(project);
    await writeFile(join(project, 'a.txt'), 'needle\n');

    const built = await Bun.build({
      ...buildOptions(FIXTURE, { compiled: true }),
      ...withFffWorker(FIXTURE),
      compile: { outfile: binary },
    });

    expect(built.success).toBe(true);

    const run = spawnSync(binary, [project], {
      cwd: directory,
      encoding: 'utf8',
    });

    expect(run.stderr).toBe('');
    expect(JSON.parse(run.stdout)).toEqual(['a.txt']);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
}, 120_000);
