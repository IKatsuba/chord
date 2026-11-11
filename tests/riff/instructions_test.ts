import { afterEach, beforeEach, describe, expect, test } from 'bun:test';
import { spawnSync } from 'node:child_process';
import {
  chmod,
  mkdir,
  mkdtemp,
  realpath,
  rm,
  writeFile,
} from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import {
  BASE_INSTRUCTIONS,
  capped,
  foldersOf,
  INSTRUCTIONS_CAP,
  readInstructions,
  TRUNCATED_NOTE,
} from '../../src/riff/instructions.ts';

let root: string;

beforeEach(async () => {
  root = await realpath(await mkdtemp(join(tmpdir(), 'chord-instr-')));
});

afterEach(async () => {
  await rm(root, { recursive: true, force: true });
});

const bytes = (text: string) => new TextEncoder().encode(text).length;

describe('riff instructions', () => {
  test('reads the base, the repository root down to the session, then the user file', async () => {
    const repo = join(root, 'repo');
    const deep = join(repo, 'a', 'b');
    const config = join(root, 'config');

    await mkdir(join(repo, '.git'), { recursive: true });
    await mkdir(deep, { recursive: true });
    await mkdir(join(config, 'chord'), { recursive: true });
    await writeFile(join(root, 'AGENTS.md'), 'above the repository');
    await writeFile(join(repo, 'AGENTS.md'), 'root rules');
    await writeFile(join(repo, 'a', 'b', 'AGENTS.md'), 'deep rules');
    await writeFile(join(repo, 'CLAUDE.md'), 'never read');
    await writeFile(join(repo, 'a', 'b', 'c.md'), 'not instructions');
    await writeFile(join(config, 'chord', 'AGENTS.md'), 'user rules');

    const text = await readInstructions({
      directory: deep,
      configHome: config,
    });

    expect(text.startsWith(BASE_INSTRUCTIONS)).toBe(true);
    expect(text).toContain(`Session directory: ${deep}`);
    expect(text).not.toContain('above the repository');
    expect(text).not.toContain('never read');

    const order = ['root rules', 'deep rules', 'user rules'].map((part) =>
      text.indexOf(part),
    );

    expect(order.every((at) => at > 0)).toBe(true);
    expect(order).toStrictEqual([...order].sort((a, b) => a - b));
    expect(text).toContain(`Instructions from ${join(repo, 'AGENTS.md')}:`);
  });

  test('a .git file marks a worktree root', async () => {
    const repo = join(root, 'worktree');
    const inner = join(repo, 'src');

    await mkdir(inner, { recursive: true });
    await writeFile(join(repo, '.git'), 'gitdir: elsewhere');

    expect(await foldersOf(inner)).toStrictEqual([repo, inner]);
  });

  test('outside a repository only the session directory own file is read', async () => {
    const inner = join(root, 'plain', 'inner');

    await mkdir(inner, { recursive: true });
    await writeFile(join(root, 'plain', 'AGENTS.md'), 'parent rules');
    await writeFile(join(inner, 'AGENTS.md'), 'own rules');

    const text = await readInstructions({
      directory: inner,
      configHome: undefined,
    });

    expect(text).toContain('own rules');
    expect(text).not.toContain('parent rules');
  });

  test('no config home and no files leave the base alone', async () => {
    const text = await readInstructions({
      directory: root,
      configHome: undefined,
    });

    expect(text).toBe(`${BASE_INSTRUCTIONS}\n\nSession directory: ${root}`);
  });

  test('a folder named AGENTS.md is no instructions', async () => {
    await mkdir(join(root, 'AGENTS.md'));

    const text = await readInstructions({
      directory: root,
      configHome: undefined,
    });

    expect(text).not.toContain('Instructions from');
  });

  test('a FIFO named AGENTS.md is skipped, never waited on', async () => {
    const made = spawnSync('mkfifo', [join(root, 'AGENTS.md')]);

    expect(made.status).toBe(0);

    const text = await readInstructions({
      directory: root,
      configHome: undefined,
    });

    expect(text).not.toContain('Instructions from');
  });

  test('a file far over the cap is read only up to it', async () => {
    await writeFile(join(root, 'AGENTS.md'), 'y'.repeat(4 * 1024 * 1024));

    const text = await readInstructions({
      directory: root,
      configHome: undefined,
    });

    expect(bytes(text)).toBeLessThanOrEqual(INSTRUCTIONS_CAP);
    expect(text.endsWith(TRUNCATED_NOTE)).toBe(true);
  });

  test('long instructions are cut at 32 KiB with the note', async () => {
    await writeFile(join(root, 'AGENTS.md'), 'x'.repeat(40 * 1024));

    const text = await readInstructions({
      directory: root,
      configHome: undefined,
    });

    expect(bytes(text)).toBeLessThanOrEqual(INSTRUCTIONS_CAP);
    expect(text.endsWith(TRUNCATED_NOTE)).toBe(true);
    expect(text.startsWith(BASE_INSTRUCTIONS)).toBe(true);
  });

  test('rules dropped by the read cut keep the note, even if trailing space shrinks the rest', async () => {
    await writeFile(
      join(root, 'AGENTS.md'),
      `rule one\n${' '.repeat(40 * 1024)}rule two`,
    );

    const text = await readInstructions({
      directory: root,
      configHome: undefined,
    });

    expect(text).toContain('rule one');
    expect(text).not.toContain('rule two');
    expect(text.endsWith(TRUNCATED_NOTE)).toBe(true);
  });

  test('an unreadable file fails the read, naming the file and why', async () => {
    const file = join(root, 'AGENTS.md');

    await writeFile(file, 'secret');
    await chmod(file, 0o000);

    await expect(
      readInstructions({ directory: root, configHome: undefined }),
    ).rejects.toThrow(`${file}: EACCES`);
  });

  test('a cut never splits a character', () => {
    const text = capped('é'.repeat(200), 151);

    expect(bytes(text)).toBeLessThanOrEqual(151);
    expect(text).not.toContain('�');
    expect(text.endsWith(TRUNCATED_NOTE)).toBe(true);
    expect(capped('short', 151)).toBe('short');
  });
});

describe('CHD-610 tester: instruction boundaries', () => {
  test('the nearest repository excludes outer repository instructions', async () => {
    const outer = join(root, 'outer');
    const inner = join(outer, 'nested');
    const directory = join(inner, 'src');

    await mkdir(join(outer, '.git'), { recursive: true });
    await mkdir(directory, { recursive: true });
    await writeFile(join(inner, '.git'), 'gitdir: fixture');
    await writeFile(join(outer, 'AGENTS.md'), 'outer-only rule');
    await writeFile(join(inner, 'AGENTS.md'), 'nested-root rule');
    await writeFile(join(directory, 'AGENTS.md'), 'nested-session rule');

    const text = await readInstructions({ directory, configHome: undefined });

    expect(text).not.toContain('outer-only rule');
    expect(text.indexOf('nested-root rule')).toBeLessThan(
      text.indexOf('nested-session rule'),
    );
    expect(await foldersOf(directory)).toStrictEqual([inner, directory]);
  });

  test('parallel session directories keep their own rules', async () => {
    const directories = [join(root, 'one'), join(root, 'two')];

    for (const [index, directory] of directories.entries()) {
      await mkdir(directory);
      await writeFile(join(directory, 'AGENTS.md'), `session-rule-${index}`);
    }

    const texts = await Promise.all(
      directories.map((directory) =>
        readInstructions({ directory, configHome: undefined }),
      ),
    );

    expect(texts[0]).toContain('session-rule-0');
    expect(texts[0]).not.toContain('session-rule-1');
    expect(texts[1]).toContain('session-rule-1');
    expect(texts[1]).not.toContain('session-rule-0');
  });

  test('a later session read sees changed instructions', async () => {
    const file = join(root, 'AGENTS.md');
    const sources = { directory: root, configHome: undefined };

    await writeFile(file, 'original-rule');

    const first = await readInstructions(sources);

    await writeFile(file, 'replacement-rule');

    const next = await readInstructions(sources);

    expect(first).toContain('original-rule');
    expect(first).not.toContain('replacement-rule');
    expect(next).toContain('replacement-rule');
    expect(next).not.toContain('original-rule');
  });

  test('the aggregate cap includes multibyte rules and the final note', async () => {
    const directory = join(root, 'src');
    const configHome = join(root, 'config');

    await mkdir(join(root, '.git'));
    await mkdir(directory);
    await mkdir(join(configHome, 'chord'), { recursive: true });
    await writeFile(join(root, 'AGENTS.md'), '😀'.repeat(5000));
    await writeFile(join(directory, 'AGENTS.md'), '界'.repeat(5000));
    await writeFile(join(configHome, 'chord', 'AGENTS.md'), 'last-user-rule');

    const text = await readInstructions({ directory, configHome });

    expect(bytes(text)).toBeLessThanOrEqual(INSTRUCTIONS_CAP);
    expect(text).not.toContain('�');
    expect(text.endsWith(TRUNCATED_NOTE)).toBe(true);
    expect(text.split(TRUNCATED_NOTE)).toHaveLength(2);
    expect(text).not.toContain('last-user-rule');
  });

  test('an unreadable user file refuses even when project text fills the cap', async () => {
    const configHome = join(root, 'config');
    const file = join(configHome, 'chord', 'AGENTS.md');

    await mkdir(join(configHome, 'chord'), { recursive: true });
    await writeFile(join(root, 'AGENTS.md'), 'x'.repeat(INSTRUCTIONS_CAP * 2));
    await writeFile(file, 'unreadable-user-rule');
    await chmod(file, 0o000);

    await expect(
      readInstructions({ directory: root, configHome }),
    ).rejects.toThrow(`${file}: EACCES`);
  });
});
