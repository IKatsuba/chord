import { afterEach, describe, expect, test } from 'bun:test';
import { mkdtemp, readFile, realpath, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { apply, STALE } from '../../../src/riff/tools/mutation.ts';
import { write } from '../../../src/riff/tools/write.ts';

const roots: string[] = [];
const signal = () => new AbortController().signal;
const setup = async () => {
  const root = await realpath(await mkdtemp(join(tmpdir(), 'chord-write-')));

  roots.push(root);

  return join(root, 'new.txt');
};

afterEach(async () => {
  await Promise.all(
    roots.splice(0).map((root) => rm(root, { recursive: true, force: true })),
  );
});

describe('whole-file write proposals', () => {
  test('creates a new file with an additions-only diff', async () => {
    const path = await setup();
    const proposal = await write(path, { path, content: 'new\n' }, signal());

    expect(proposal.hash).toBeNull();
    expect(proposal.content).toEqual([
      { type: 'diff', path, oldText: null, newText: 'new\n' },
    ]);
    await apply(proposal, signal());
    expect(await readFile(path, 'utf8')).toBe('new\n');
  });

  test('replaces the whole existing file, including truncation to empty', async () => {
    const path = await setup();

    await writeFile(path, 'old content');
    await apply(await write(path, { path, content: '' }, signal()), signal());
    expect(await readFile(path, 'utf8')).toBe('');
  });

  test('does not overwrite a file that appeared after the proposal', async () => {
    const path = await setup();
    const proposal = await write(path, { path, content: 'proposed' }, signal());

    await writeFile(path, 'appeared');
    await expect(apply(proposal, signal())).rejects.toThrow(STALE);
    expect(await readFile(path, 'utf8')).toBe('appeared');
  });

  test('abort before effect does not create a file', async () => {
    const path = await setup();
    const proposal = await write(path, { path, content: 'proposed' }, signal());

    await expect(
      apply(proposal, AbortSignal.abort(new Error('stop'))),
    ).rejects.toThrow('stop');
    await expect(readFile(path)).rejects.toMatchObject({ code: 'ENOENT' });
  });
});
