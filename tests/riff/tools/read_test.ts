import { afterEach, beforeEach, describe, expect, test } from 'bun:test';
import { spawnSync } from 'node:child_process';
import {
  mkdir,
  mkdtemp,
  realpath,
  rename,
  rm,
  symlink,
  writeFile,
} from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { LIMITS } from '../../../src/riff/tools/limits.ts';
import { openReal } from '../../../src/riff/tools/paths.ts';
import { readLines } from '../../../src/riff/tools/read.ts';

const live = () => new AbortController().signal;

describe("riff's read", () => {
  let root: string;

  beforeEach(async () => {
    root = await realpath(await mkdtemp(join(tmpdir(), 'chord-riff-read-')));

    await writeFile(join(root, 'a.txt'), 'one\ntwo\nthree\nfour\n');
  });

  afterEach(async () => {
    await rm(root, { recursive: true, force: true });
  });

  test('a whole file comes numbered from 1', async () => {
    expect(
      await readLines(join(root, 'a.txt'), { path: 'a.txt' }, live()),
    ).toBe('1\tone\n2\ttwo\n3\tthree\n4\tfour');
  });

  test('a range returns its lines and says where to read on', async () => {
    expect(
      await readLines(
        join(root, 'a.txt'),
        { path: 'a.txt', offset: 2, limit: 2 },
        live(),
      ),
    ).toBe('2\ttwo\n3\tthree\n… more from line 4; read on with offset 4.');
  });

  test('an offset past the end says how long the file is', async () => {
    expect(
      await readLines(
        join(root, 'a.txt'),
        { path: 'a.txt', offset: 9 },
        live(),
      ),
    ).toBe(`${join(root, 'a.txt')} has 4 lines; nothing at line 9.`);
  });

  test('an empty file says so', async () => {
    await writeFile(join(root, 'empty.txt'), '');

    expect(
      await readLines(join(root, 'empty.txt'), { path: 'empty.txt' }, live()),
    ).toBe(`${join(root, 'empty.txt')} is empty.`);
  });

  test('without a limit, at most the line limit, and a long line is cut', async () => {
    const lines = Array.from(
      { length: LIMITS.readLines + 5 },
      (_, index) => `line ${index + 1}`,
    );

    lines[0] = 'x'.repeat(LIMITS.readLineChars + 10);

    await writeFile(join(root, 'long.txt'), lines.join('\n'));

    const read = (
      await readLines(join(root, 'long.txt'), { path: 'long.txt' }, live())
    ).split('\n');

    expect(read).toHaveLength(LIMITS.readLines + 1);
    expect(read[0]).toBe(`1\t${'x'.repeat(LIMITS.readLineChars)}…`);
    expect(read.at(-1)).toBe(
      `… more from line ${LIMITS.readLines + 1}; read on with offset ${LIMITS.readLines + 1}.`,
    );
  });

  test('at most the byte limit, whatever the range', async () => {
    const line = 'y'.repeat(1000);

    await writeFile(join(root, 'big.txt'), `${line}\n`.repeat(1000));

    const read = await readLines(
      join(root, 'big.txt'),
      { path: 'big.txt', limit: 1000 },
      live(),
    );

    expect(read.length).toBeLessThanOrEqual(LIMITS.readBytes + 100);
    expect(read).toMatch(/read on with offset \d+\.$/);
  });

  test('a binary file is refused by what file-type says it is', async () => {
    await writeFile(
      join(root, 'image.png'),
      Buffer.from('89504e470d0a1a0a0000000d49484452', 'hex'),
    );

    expect(
      readLines(join(root, 'image.png'), { path: 'image.png' }, live()),
    ).rejects.toThrow('a binary file (image/png); not read');
  });

  test('text file-type names, such as XML, is read', async () => {
    await writeFile(join(root, 'a.xml'), '<?xml version="1.0"?>\n<a/>\n');

    expect(
      await readLines(join(root, 'a.xml'), { path: 'a.xml' }, live()),
    ).toBe('1\t<?xml version="1.0"?>\n2\t<a/>');
  });

  test('a missing file, a directory and an aborted call are refused', async () => {
    await mkdir(join(root, 'dir'));

    await expect(
      readLines(join(root, 'none.txt'), { path: 'none.txt' }, live()),
    ).rejects.toThrow('no such file');
    await expect(
      readLines(join(root, 'dir'), { path: 'dir' }, live()),
    ).rejects.toThrow('is a directory; list it instead');

    const controller = new AbortController();
    const reason = new Error('stopped');

    controller.abort(reason);

    await expect(
      readLines(join(root, 'a.txt'), { path: 'a.txt' }, controller.signal),
    ).rejects.toBe(reason);
  });

  test('a symlink is read at its real path', async () => {
    const outside = await realpath(
      await mkdtemp(join(tmpdir(), 'chord-riff-outside-')),
    );

    try {
      await writeFile(join(outside, 'secret.txt'), 'out there\n');
      await symlink(join(outside, 'secret.txt'), join(root, 'link.txt'));

      expect(
        await readLines(join(root, 'link.txt'), { path: 'link.txt' }, live()),
      ).toBe('1\tout there');
    } finally {
      await rm(outside, { recursive: true, force: true });
    }
  });
});

describe('a real path opened', () => {
  let root: string;
  let outside: string;
  let path: string;

  beforeEach(async () => {
    root = await realpath(await mkdtemp(join(tmpdir(), 'chord-riff-swap-')));
    outside = await realpath(
      await mkdtemp(join(tmpdir(), 'chord-riff-outside-')),
    );
    path = join(root, 'a.txt');

    await writeFile(path, 'first\n');
    await writeFile(join(outside, 'secret.txt'), 'secret\n');
  });

  afterEach(async () => {
    await rm(root, { recursive: true, force: true });
    await rm(outside, { recursive: true, force: true });
  });

  const changed = 'the file changed while it was opened; read it again';

  test('another file swapped in before the open is refused', async () => {
    await expect(
      openReal(path, {
        beforeOpen: async () => {
          await rename(path, join(root, 'old.txt'));
          await writeFile(path, 'second\n');
        },
      }),
    ).rejects.toThrow(changed);
  });

  test('a link to a file outside swapped in before the open is refused', async () => {
    await expect(
      openReal(path, {
        beforeOpen: async () => {
          await rm(path);
          await symlink(join(outside, 'secret.txt'), path);
        },
      }),
    ).rejects.toThrow(changed);
  });

  test('another file swapped in after the open is refused', async () => {
    await expect(
      openReal(path, {
        afterOpen: async () => {
          await rename(path, join(root, 'old.txt'));
          await writeFile(path, 'second\n');
        },
      }),
    ).rejects.toThrow(changed);
  });

  test('a FIFO is refused without waiting on it, and so is one swapped in', async () => {
    const fifo = join(root, 'pipe');

    expect(spawnSync('mkfifo', [fifo]).status).toBe(0);
    await expect(openReal(fifo)).rejects.toThrow('not a regular file');
    await expect(
      openReal(path, {
        beforeOpen: async () => {
          await rm(path);
          expect(spawnSync('mkfifo', [path]).status).toBe(0);
        },
      }),
    ).rejects.toThrow(changed);
  });

  test('an untouched file opens, its size read', async () => {
    const opened = await openReal(path);

    try {
      expect(opened.real).toBe(path);
      expect(opened.size).toBe(6);
    } finally {
      await opened.handle.close();
    }
  });
});
