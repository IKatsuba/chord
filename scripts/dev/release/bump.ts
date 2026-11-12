/**
 * The commit a release given a new version makes before any stage
 * (CHD-412): the package's package.json's version written and committed
 * alone, with bun.lock where Bun records it, so every stage, which reads
 * package.json, builds and packs that version. A run
 * that publishes pushes it to origin's main, or its channel's branch, and
 * drops it if the push fails; any other run drops it at the end, leaving the
 * branch as it found it. Until it is pushed or dropped, Ctrl+C, SIGTERM and
 * SIGHUP drop it too; SIGKILL cannot be caught, and leaves it.
 */
import process from 'node:process';
import { readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { channelOf } from '../../../src/channel.ts';
import { die, type Release, type ReleasePackage, run, said } from './lib.ts';
import { packageVersion } from './preflight.ts';

/**
 * Commits the package's package.json at `version`, with bun.lock where Bun
 * records it, and answers the commit it was made on.
 */
export function commitVersion(
  release: Release,
  of: ReleasePackage,
  version: string,
): string {
  const head = run(release, 'git', ['rev-parse', 'HEAD']);

  if (head.status !== 0) {
    die(`git rev-parse HEAD failed: ${said(head.stderr)}`);
  }

  const manifest = join(of.folder, 'package.json');
  const file = join(release.root, manifest);
  const before = readFileSync(file, 'utf8');
  // Only the value replaced, so the rest of the file stays as Prettier laid it.
  const after = before.replace(
    /("version"\s*:\s*)"[^"]*"/,
    (_all, key: string) => `${key}"${version}"`,
  );

  writeFileSync(file, after);

  if (packageVersion(release, of.folder) !== version) {
    writeFileSync(file, before);
    die(`${manifest}'s version could not be set to ${version}`);
  }

  const paths = [
    manifest,
    ...locked(release, of, () => writeFileSync(file, before)),
  ];
  const committed = run(release, 'git', [
    'commit',
    '-q',
    '-m',
    `chore: ${of.name} v${version}`,
    '--',
    ...paths,
  ]);

  if (committed.status !== 0) {
    writeFileSync(file, before);
    run(release, 'git', ['checkout', '-q', '--', ...paths.slice(1)]);
    die(
      `git commit of ${paths.join(' and ')} failed: ${said(committed.stderr)}`,
    );
  }

  return said(head.stdout);
}

/**
 * bun.lock, when Bun's own lockfile install changed it: Bun records a
 * workspace package's version there, never the root's (CHD-623), so only a
 * workspace package's version needs it. A failure undoes the package.json
 * edit through `undo` before the release dies.
 */
function locked(
  release: Release,
  of: ReleasePackage,
  undo: () => void,
): string[] {
  if (of.folder === '.') {
    return [];
  }

  if (run(release, 'bun', ['install', '--lockfile-only']).status !== 0) {
    undo();
    run(release, 'git', ['checkout', '-q', '--', 'bun.lock']);
    die('bun install --lockfile-only failed');
  }

  const changed = run(release, 'git', [
    'status',
    '--porcelain',
    '--',
    'bun.lock',
  ]);

  return said(changed.stdout) === '' ? [] : ['bun.lock'];
}

/** The signals a held version commit is dropped on. */
const SIGNALS = ['SIGINT', 'SIGTERM', 'SIGHUP'] as const;

/** A local version commit, dropped once, or kept once pushed. */
export interface Held {
  /** Drops the commit, if it is still held, and stops watching for signals. */
  drop(): void;
  /** Keeps the commit, pushed, and stops watching for signals. */
  keep(): void;
}

/**
 * Holds the version commit made on `head`: a signal while it is held drops
 * it, then raises the signal again once its listener is gone, as
 * selftest's cleanup does: every other listener (selftest's tmux server)
 * still runs, and the run ends by the signal, its status 128 + its number.
 */
export function holdVersion(release: Release, head: string): Held {
  let held = true;
  const done = () => {
    held = false;

    for (const signal of SIGNALS) {
      process.removeListener(signal, onSignal);
    }
  };

  const onSignal = (signal: NodeJS.Signals) => {
    try {
      if (held) {
        dropVersion(release, head);
      }
    } catch (error) {
      release.err(`release: ${(error as Error).message}`);
    }

    done();
    process.kill(process.pid, signal);
  };

  for (const signal of SIGNALS) {
    process.on(signal, onSignal);
  }

  return {
    drop: () => {
      if (!held) {
        return;
      }

      held = false;

      // The handlers outlive the drop by a turn of the event loop: Ctrl+C
      // during a stage's child is handled only once the stage has failed
      // and the commit is dropped, and must still end the run by it.
      setImmediate(done);
      dropVersion(release, head);
    },
    keep: done,
  };
}

/**
 * The version's branch, main or its channel's, pushed to origin with the
 * version commit. A held commit (a run without a state) is dropped if the
 * push fails; one a state records stays, and the next run pushes it.
 */
export function pushVersion(
  release: Release,
  of: ReleasePackage,
  version: string,
  held?: Held,
): void {
  const branch = channelOf(version) ?? 'main';
  const pushed = run(release, 'git', ['push', '-q', 'origin', branch]);

  if (pushed.status !== 0) {
    if (held === undefined) {
      die(
        `git push origin ${branch} failed; chore: ${of.name} v${version} stays committed, and \`bun dev release ${of.name}\` pushes it: ${said(pushed.stderr)}`,
      );
    }

    held.drop();
    die(
      `git push origin ${branch} failed, so chore: ${of.name} v${version} is dropped: ${said(pushed.stderr)}`,
    );
  }

  held?.keep();
}

/**
 * The version commit dropped: the branch back at `head`. `--keep`, so a
 * change a stage left in a tracked file is never thrown away with it.
 */
export function dropVersion(release: Release, head: string): void {
  const reset = run(release, 'git', ['reset', '-q', '--keep', head]);

  if (reset.status !== 0) {
    die(
      `git reset --keep ${head} failed, so the version commit is still on the branch: ${said(reset.stderr)}`,
    );
  }
}
