/**
 * One release per checkout at a time (CHD-623): two runs in one clone would
 * move each other's version commits, and nothing in the tree or the branch
 * catches the second. The lock is proper-lockfile's on a file in git's
 * common directory, so every worktree of the clone shares it.
 */
import { readFileSync, realpathSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { lock } from 'proper-lockfile';
import { die, type Release, run, said } from './lib.ts';

// A release runs its long stages (install, quality, compile) with spawnSync,
// which holds back proper-lockfile's mtime updates for minutes: with its
// default 10 s `stale`, a second run would take the lock in the middle of a
// release. A day outlasts any release; a run killed by SIGKILL, which the
// lock's own exit handler cannot see, leaves it to be removed by hand.
const STALE = 24 * 60 * 60 * 1000;

/** The file the lock is taken on, in git's common directory. */
export function lockFile(release: Release): string {
  const common = run(release, 'git', ['rev-parse', '--git-common-dir']);

  if (common.status !== 0) {
    die(`git rev-parse --git-common-dir failed: ${said(common.stderr)}`);
  }

  const dir = resolve(release.root, said(common.stdout));

  // Its real path: git names it relative to a main checkout and absolute,
  // through no symlink, from a worktree.
  try {
    return join(realpathSync(dir), 'chord-release');
  } catch (error) {
    die(`git's common directory ${dir}: ${(error as Error).message}`);
  }
}

/**
 * Takes the checkout's release lock, or dies naming the run that holds it,
 * and answers its release.
 */
export async function holdRelease(
  release: Release,
): Promise<() => Promise<void>> {
  const file = lockFile(release);
  let unlock: () => Promise<void>;

  try {
    unlock = await lock(file, {
      realpath: false,
      stale: STALE,
      update: STALE / 2,
    });
  } catch (error) {
    if ((error as { code?: string }).code !== 'ELOCKED') {
      throw error;
    }

    die(
      `another release runs in this checkout (pid ${holder(file)}); if it was killed, remove ${file}.lock`,
    );
  }

  // The holder's pid, for the refusal a second run prints; a lock whose pid
  // cannot be written is let go before the error goes on.
  try {
    writeFileSync(file, `${process.pid}\n`);
  } catch (error) {
    await unlock();

    throw error;
  }

  return unlock;
}

/** The pid the holding run wrote, if it has yet. */
function holder(file: string): string {
  try {
    return readFileSync(file, 'utf8').trim() || 'unknown';
  } catch {
    return 'unknown';
  }
}
