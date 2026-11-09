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

  test('the window gets the lines as read, and messages the label', async () => {
    const shown: string[] = [];

    expect(
      await readLines(
        join(root, 'a.txt'),
        { path: 'a.txt', offset: 2, limit: 2 },
        live(),
        { label: 'a.txt', onShown: (text) => shown.push(text) },
      ),
    ).toBe('2\ttwo\n3\tthree\n… more from line 4; read on with offset 4.');
    expect(
      await readLines(
        join(root, 'a.txt'),
        { path: 'a.txt', offset: 9 },
        live(),
        { label: 'a.txt', onShown: (text) => shown.push(text) },
      ),
    ).toBe('a.txt has 4 lines; nothing at line 9.');
    expect(shown).toStrictEqual([
      'two\nthree',
      'a.txt has 4 lines; nothing at line 9.',
    ]);
    await expect(
      readLines(join(root, 'none.txt'), { path: 'none.txt' }, live(), {
        label: 'none.txt',
      }),
    ).rejects.toThrow(/^none\.txt: no such file$/);
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

  test('a refusal after the open names the file by its label', async () => {
    await expect(
      openReal(path, {
        label: 'a.txt',
        afterOpen: async () => {
          await rename(path, join(root, 'old.txt'));
          await writeFile(path, 'second\n');
        },
      }),
    ).rejects.toThrow(
      /^a\.txt: the file changed while it was opened; read it again$/,
    );
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

describe('a read cut by its signal', () => {
  test('an abort between lines rejects with its reason, and the next read answers', async () => {
    const root = await realpath(
      await mkdtemp(join(tmpdir(), 'chord-riff-abort-')),
    );
    const path = join(root, 'big.txt');

    try {
      await writeFile(path, 'line\n'.repeat(10_000));

      const controller = new AbortController();
      const reason = new Error('stopped');

      await expect(
        readLines(path, { path: 'big.txt' }, controller.signal, {
          onLine: (line) => {
            if (line === 3) {
              controller.abort(reason);
            }
          },
        }),
      ).rejects.toBe(reason);
      expect(
        await readLines(path, { path: 'big.txt', limit: 1 }, live()),
      ).toStartWith('1\tline\n');
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });
});

describe('tester: read boundaries and continuation', () => {
  let root: string;

  beforeEach(async () => {
    root = await realpath(
      await mkdtemp(join(tmpdir(), 'chord-riff-read-edge-')),
    );
  });

  afterEach(async () => {
    await rm(root, { recursive: true, force: true });
  });

  test('a chain of relative symlinks opens the final outside file', async () => {
    const inside = join(root, 'project');
    const outside = join(root, 'outside');

    await mkdir(inside);
    await mkdir(outside);
    await writeFile(join(outside, 'text.txt'), 'outside\n');
    await symlink('../outside/text.txt', join(inside, 'second'));
    await symlink('second', join(inside, 'first'));

    const opened = await openReal(join(inside, 'first'));

    try {
      expect(opened.real).toBe(join(outside, 'text.txt'));
    } finally {
      await opened.handle.close();
    }

    expect(
      await readLines(join(inside, 'first'), { path: 'first' }, live()),
    ).toBe('1\toutside');
  });

  test('a large UTF-8 file respects byte limits and resumes at the first omitted line', async () => {
    const path = join(root, 'large.txt');
    const content = '界'.repeat(1000);

    await writeFile(path, `${content}\n`.repeat(5000));

    const answer = await readLines(
      path,
      { path: 'large.txt', offset: 4000, limit: 1000 },
      live(),
    );
    const rows = answer.split('\n');
    const notice = rows.pop()!;
    const next = Number(/offset (\d+)\.$/.exec(notice)![1]);

    expect(rows[0]).toBe(`4000\t${content}`);
    expect(Buffer.byteLength(rows.join('\n'))).toBeLessThanOrEqual(
      LIMITS.readBytes,
    );
    expect(next).toBe(4000 + rows.length);
    expect(
      await readLines(
        path,
        { path: 'large.txt', offset: next, limit: 1 },
        live(),
      ),
    ).toBe(
      `${next}\t${content}\n… more from line ${next + 1}; read on with offset ${next + 1}.`,
    );
  });
});

describe('tester: cancelling while a read skips to its offset', () => {
  test('an external abort at a held line returns its reason and leaves the file readable', async () => {
    const root = await realpath(
      await mkdtemp(join(tmpdir(), 'chord-riff-read-cancel-')),
    );
    const path = join(root, 'large.txt');
    const reached = Promise.withResolvers<void>();
    const resume = Promise.withResolvers<void>();
    const controller = new AbortController();
    const reason = new Error('cancel while skipping');
    const seen: number[] = [];

    try {
      await writeFile(path, 'line\n'.repeat(100_000));

      const reading = readLines(
        path,
        { path: 'large.txt', offset: 90_000, limit: 1 },
        controller.signal,
        {
          onLine: (line) => {
            seen.push(line);

            if (line === 32) {
              reached.resolve();

              return resume.promise;
            }
          },
        },
      );

      await reached.promise;
      controller.abort(reason);
      resume.resolve();
      await expect(reading).rejects.toBe(reason);
      expect(seen.at(-1)).toBe(32);
      expect(seen).toHaveLength(32);
      expect(
        await readLines(path, { path: 'large.txt', limit: 1 }, live()),
      ).toBe('1\tline\n… more from line 2; read on with offset 2.');
    } finally {
      resume.resolve();
      await rm(root, { recursive: true, force: true });
    }
  });
});
