import { describe, expect, test } from 'bun:test';
import {
  mkdir,
  mkdtemp,
  readdir,
  readFile,
  rm,
  writeFile,
} from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, relative } from 'node:path';

/**
 * What writes the person's real clipboard from a test: OpenTUI's host
 * clipboard, which `testRender`'s local renderer would reach through
 * `best-available`, and macOS's own command. A spike of CHD-172 wrote the
 * owner's clipboard once and lost what was on it, so a test gets only
 * chord's `copy` prop or a stub host (docs/design/CHD-172.md, "Tests").
 */
const clipboardWriters = /\bcreateHostClipboard\b|\bpbcopy\b/;

/** This file, the one place that may name them. */
const self = 'clipboard_guard_test.ts';

/**
 * Every file under `root` that names a clipboard writer, by its path from
 * `root`. Reads the tree itself rather than asking git, so a test not yet
 * added is caught too.
 */
async function clipboardWriting(root: string): Promise<string[]> {
  const entries = await readdir(root, { recursive: true, withFileTypes: true });
  const found: string[] = [];

  for (const entry of entries) {
    if (!entry.isFile()) {
      continue;
    }

    const path = join(entry.parentPath, entry.name);
    const name = relative(root, path);

    if (name === self) {
      continue;
    }

    const bytes = await readFile(path);

    // Every file, binary or not: a NUL in a comment would otherwise hide a
    // call, and the names are ASCII whatever the rest of the bytes are.
    if (clipboardWriters.test(bytes.toString('latin1'))) {
      found.push(name);
    }
  }

  return found.sort();
}

test('a file naming a clipboard writer is found, tracked or not', async () => {
  const root = await mkdtemp(join(tmpdir(), 'chord-'));

  try {
    await mkdir(join(root, 'ui'));
    await writeFile(join(root, 'ui', 'a_test.ts'), 'createHostClipboard()');
    await writeFile(join(root, 'b_test.ts'), "spawn('pbcopy')");
    await writeFile(join(root, 'c_test.ts'), 'createClipboard({ host })');
    await writeFile(join(root, 'd_test.ts'), '// \0\ncreateHostClipboard()');
    await writeFile(join(root, self), 'pbcopy');

    expect(await clipboardWriting(root)).toStrictEqual([
      'b_test.ts',
      'd_test.ts',
      join('ui', 'a_test.ts'),
    ]);
  } finally {
    await rm(root, { recursive: true });
  }
});

test('nothing under tests/ can write the real clipboard', async () => {
  expect(
    await clipboardWriting(import.meta.dir),
    'a test names a clipboard writer; give it the `copy` prop or a stub ' +
      'host instead (docs/design/CHD-172.md, "Tests")',
  ).toStrictEqual([]);
});

describe('tester: clipboard guard path and byte coverage', () => {
  test('only the root guard is exempt, including hidden and binary files', async () => {
    const root = await mkdtemp(join(tmpdir(), 'chord-'));

    try {
      const nested = join(root, '.fixtures', 'nested');

      await mkdir(nested, { recursive: true });
      await writeFile(join(root, self), 'createHostClipboard');
      await writeFile(join(nested, self), 'createHostClipboard');
      await writeFile(join(nested, 'payload'), Buffer.from('\0pbcopy\0'));
      await writeFile(join(root, 'safe.ts'), 'createClipboard({ host: stub })');

      expect(await clipboardWriting(root)).toStrictEqual([
        join('.fixtures', 'nested', self),
        join('.fixtures', 'nested', 'payload'),
      ]);
    } finally {
      await rm(root, { recursive: true });
    }
  });
});
