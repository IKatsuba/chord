import { afterEach, describe, expect, test } from 'bun:test';
import {
  mkdtemp,
  readFile,
  realpath,
  rm,
  symlink,
  writeFile,
} from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { edit } from '../../../src/riff/tools/edit.ts';
import { apply, STALE } from '../../../src/riff/tools/mutation.ts';

const roots: string[] = [];
const signal = () => new AbortController().signal;
const setup = async (text = 'hello world\n') => {
  const root = await realpath(await mkdtemp(join(tmpdir(), 'chord-edit-')));

  roots.push(root);

  const path = join(root, 'a.txt');

  await writeFile(path, text);

  return { root, path };
};

afterEach(async () => {
  await Promise.all(
    roots.splice(0).map((root) => rm(root, { recursive: true, force: true })),
  );
});

describe('unique-string edit proposals', () => {
  test('builds a diff and applies exactly the unique string', async () => {
    const { path } = await setup();
    const proposal = await edit(
      path,
      { path, oldString: 'world', newString: 'friend' },
      signal(),
    );

    expect(proposal.patch).toContain('-hello world');
    expect(proposal.patch).toContain('+hello friend');
    expect(await readFile(path, 'utf8')).toBe('hello world\n');
    await apply(proposal, signal());
    expect(await readFile(path, 'utf8')).toBe('hello friend\n');
  });

  test('missing and duplicate strings leave bytes unchanged', async () => {
    const { path } = await setup('aaaa');

    for (const oldString of ['absent', 'aa']) {
      await expect(
        edit(path, { path, oldString, newString: 'z' }, signal()),
      ).rejects.toThrow(oldString === 'aa' ? 'not unique' : 'not found');
    }

    expect(await readFile(path, 'utf8')).toBe('aaaa');
  });

  test('a changed file refuses the proposed edit without writing', async () => {
    const { path } = await setup();
    const proposal = await edit(
      path,
      { path, oldString: 'world', newString: 'friend' },
      signal(),
    );

    await writeFile(path, 'changed by someone else');
    await expect(apply(proposal, signal())).rejects.toThrow(STALE);
    expect(await readFile(path, 'utf8')).toBe('changed by someone else');
  });

  test('a symlink resolves outside and a later destination swap is refused', async () => {
    const { path } = await setup();
    const other = await setup('outside\n');
    const link = join(other.root, 'link');

    await symlink(path, link);

    const proposal = await edit(
      link,
      { path: link, oldString: 'world', newString: 'friend' },
      signal(),
    );

    expect(proposal.real).toBe(path);
    await rm(link);
    await symlink(other.path, link);
    await expect(apply(proposal, signal())).rejects.toThrow(
      'destination changed',
    );
    expect(await readFile(path, 'utf8')).toBe('hello world\n');
  });

  test('abort before proposal and before effect leaves the file unchanged', async () => {
    const { path } = await setup();
    const input = { path, oldString: 'world', newString: 'friend' };
    const proposal = await edit(path, input, signal());
    const stopped = AbortSignal.abort(new Error('stopped'));

    await expect(edit(path, input, stopped)).rejects.toThrow('stopped');
    await expect(apply(proposal, stopped)).rejects.toThrow('stopped');
    expect(await readFile(path, 'utf8')).toBe('hello world\n');
  });
});
