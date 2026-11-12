import { afterEach, beforeEach, describe, expect, test } from 'bun:test';
import { spawnSync } from 'node:child_process';
import {
  existsSync,
  mkdirSync,
  readFileSync,
  realpathSync,
  rmSync,
  utimesSync,
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

test('a lock a killed run left, however old, is never taken over: it is refused, naming its pid and the path', async () => {
  const file = lockFile(at.release);

  // As a run killed by SIGKILL left it, a year ago.
  mkdirSync(`${file}.lock`);
  writeFileSync(file, '4242\n');

  const year = new Date(Date.now() - 365 * 24 * 60 * 60 * 1000);

  utimesSync(`${file}.lock`, year, year);

  expect(await refusal(at.release)).toBe(
    `another release runs in this checkout (pid 4242); if it was killed, remove ${file}.lock`,
  );
  expect(existsSync(`${file}.lock`)).toBeTrue();

  // Removed by hand, the next run takes it.
  rmSync(`${file}.lock`, { recursive: true });
  await (
    await holdRelease(at.release)
  )();
});

describe('tester: CHD-623 checkout lock boundaries', () => {
  test('a lock directory without a pid remains owned and is refused as unknown', async () => {
    const file = lockFile(at.release);

    mkdirSync(`${file}.lock`);

    expect(await refusal(at.release)).toBe(
      `another release runs in this checkout (pid unknown); if it was killed, remove ${file}.lock`,
    );
    expect(existsSync(`${file}.lock`)).toBeTrue();
    expect(existsSync(file)).toBeFalse();
  });

  test('independent checkouts can hold locks together and release them separately', async () => {
    const other = scratch();
    let unlockFirst: (() => Promise<void>) | undefined;
    let unlockOther: (() => Promise<void>) | undefined;

    try {
      git(other.root, 'init', '-q', '-b', 'main');

      unlockFirst = await holdRelease(at.release);
      unlockOther = await holdRelease(other.release);

      const firstFile = lockFile(at.release);
      const otherFile = lockFile(other.release);

      expect(firstFile).not.toBe(otherFile);
      expect(existsSync(`${firstFile}.lock`)).toBeTrue();
      expect(existsSync(`${otherFile}.lock`)).toBeTrue();
      await unlockFirst();

      unlockFirst = undefined;

      expect(existsSync(`${firstFile}.lock`)).toBeFalse();
      expect(existsSync(`${otherFile}.lock`)).toBeTrue();
      expect(await refusal(other.release)).toContain(`pid ${process.pid}`);
    } finally {
      await unlockOther?.();
      await unlockFirst?.();
      rmSync(other.place, { recursive: true, force: true });
    }
  });
});
