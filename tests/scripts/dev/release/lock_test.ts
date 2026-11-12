import { afterEach, beforeEach, expect, test } from 'bun:test';
import { spawnSync } from 'node:child_process';
import {
  existsSync,
  mkdirSync,
  readFileSync,
  realpathSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import { join } from 'node:path';
import {
  type Release,
  ReleaseError,
} from '../../../../scripts/dev/release/lib.ts';
import { holdRelease, lockFile } from '../../../../scripts/dev/release/lock.ts';
import { type Scratch, scratch } from './scratch.ts';

let at: Scratch;

beforeEach(() => {
  at = scratch();

  git(at.root, 'init', '-q', '-b', 'main');
  writeFileSync(join(at.root, 'a'), 'a\n');
  git(at.root, 'add', 'a');
  git(
    at.root,
    '-c',
    'user.name=release',
    '-c',
    'user.email=release@example.com',
    'commit',
    '-q',
    '-m',
    'a',
  );
});

afterEach(() => {
  rmSync(at.place, { recursive: true, force: true });
});

function git(cwd: string, ...args: string[]): void {
  expect(spawnSync('git', args, { cwd }).status).toBe(0);
}

async function refusal(release: Release): Promise<string> {
  try {
    await holdRelease(release);
  } catch (error) {
    expect(error).toBeInstanceOf(ReleaseError);

    return (error as Error).message;
  }

  throw new Error('the second release was not refused');
}

test("a second release in the checkout is refused, naming the first's pid and the lock to remove", async () => {
  const unlock = await holdRelease(at.release);
  const file = lockFile(at.release);

  try {
    expect(file).toBe(join(realpathSync(at.root), '.git', 'chord-release'));
    expect(readFileSync(file, 'utf8')).toBe(`${process.pid}\n`);
    expect(await refusal(at.release)).toBe(
      `another release runs in this checkout (pid ${process.pid}); if it was killed, remove ${file}.lock`,
    );
  } finally {
    await unlock();
  }

  expect(existsSync(`${file}.lock`)).toBeFalse();
  await (
    await holdRelease(at.release)
  )();
});

test('a worktree of the clone shares the lock', async () => {
  const other = join(at.place, 'other');

  git(at.root, 'worktree', 'add', '-q', other);

  const unlock = await holdRelease(at.release);

  try {
    expect(lockFile({ ...at.release, root: other })).toBe(lockFile(at.release));
    expect(await refusal({ ...at.release, root: other })).toStartWith(
      'another release runs in this checkout',
    );
  } finally {
    await unlock();
  }
});

test('outside a git checkout, the lock is refused with what git said', async () => {
  rmSync(join(at.root, '.git'), { recursive: true });

  expect(await refusal(at.release)).toStartWith(
    'git rev-parse --git-common-dir failed: fatal: not a git repository',
  );
});

test('a pid that cannot be written lets the lock go before the error', async () => {
  const file = lockFile(at.release);

  // A directory where the pid file goes: writing it fails after the lock.
  mkdirSync(file);

  await expect(holdRelease(at.release)).rejects.toThrow('EISDIR');
  expect(existsSync(`${file}.lock`)).toBeFalse();
});
