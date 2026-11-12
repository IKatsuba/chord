/**
 * Eligibility guards before authentication or release work, for one
 * package: a clean tree, a new version only once its package.json's is
 * published under its main npm name, an unpublished version or a stopped
 * publish to resume; publishing also requires the version's branch, main or
 * its channel's, level with origin, no tag of its form, and `gh` for a
 * package with a GitHub release. Registry reads and the existing fetch may use the network, but these
 * guards do not log in.
 */
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { channelOf } from '../../../src/channel.ts';
import {
  die,
  mainName,
  published,
  type Release,
  type ReleasePackage,
  run,
  said,
  tagName,
} from './lib.ts';
import { ghReady } from './source.ts';

/** What preflight found: a fresh version, or a stopped publish to finish. */
export interface Preflight {
  readonly mode: 'fresh' | 'resume';
  readonly version: string;
}

export interface PreflightOptions {
  readonly dryRun: boolean;
  /** Whether the run's stages include publish. */
  readonly publish: boolean;
  /** The version to release, before it is written; package.json's if none. */
  readonly version?: string | undefined;
}

export function preflight(
  release: Release,
  of: ReleasePackage,
  {
    dryRun,
    publish,
    version = packageVersion(release, of.folder),
  }: PreflightOptions,
): Preflight {
  // 1. The tree, untracked files included.
  const status = run(release, 'git', [
    'status',
    '--porcelain',
    '--untracked-files=all',
  ]);

  if (status.status !== 0) {
    die(`git status failed: ${said(status.stderr)}`);
  }

  const dirty = said(status.stdout);

  if (dirty !== '') {
    die(`the tree is not clean:\n${dirty}`);
  }

  // 2. A new version, refused while package.json's never reached npm: a
  // stopped release is finished, not bumped past.
  const current = packageVersion(release, of.folder);
  const main = mainName(of);

  if (version !== current && !published(release, main, current)) {
    die(
      `${main}@${current} is not published yet; \`bun dev release ${of.name}\` without --bump finishes it`,
    );
  }

  // 3. The version, refused if the main package has it.
  if (published(release, main, version)) {
    die(`${main}@${version} is on npm already`);
  }

  let mode: Preflight['mode'] = 'fresh';

  for (const name of of.publish.npm.slice(0, -1)) {
    if (published(release, name, version)) {
      if (dryRun) {
        die(
          `--dry-run does not resume a stopped publish: ${name}@${version} is published`,
        );
      }

      if (!publish) {
        die(
          `a run without publish does not resume a stopped publish: ${name}@${version} is published; include publish`,
        );
      }

      mode = 'resume';

      break;
    }
  }

  if (publish) {
    onBranch(release, channelOf(version));
    notTagged(release, tagName(of, version));

    if (of.publish.githubRelease) {
      ghReady(release);
    }
  }

  return { mode, version };
}

/** The package.json's version in `folder`, the root's for `.`. */
export function packageVersion(release: Release, folder: string): string {
  let version: unknown;

  try {
    version = (
      JSON.parse(
        readFileSync(join(release.root, folder, 'package.json'), 'utf8'),
      ) as {
        version?: unknown;
      }
    ).version;
  } catch {
    version = undefined;
  }

  if (typeof version !== 'string' || version === '') {
    die(`${join(folder, 'package.json')} has no version`);
  }

  return version;
}

/**
 * The branch of `channel`, or main for a stable version, checked out, and the
 * same commit as origin's once fetched.
 */
function onBranch(release: Release, channel: string | null): void {
  const wanted = channel ?? 'main';
  const branch = run(release, 'git', ['symbolic-ref', '--short', 'HEAD']);

  if (branch.status !== 0 || said(branch.stdout) !== wanted) {
    const head = said(branch.stdout) || said(branch.stderr);

    die(
      channel === null
        ? `a release that publishes runs from main; HEAD is ${head}`
        : `a release on channel ${channel} publishes only from branch ${channel}; HEAD is ${head}`,
    );
  }

  const fetched = run(release, 'git', ['fetch', 'origin']);

  if (fetched.status !== 0) {
    die(`git fetch origin failed: ${said(fetched.stderr)}`);
  }

  const head = said(run(release, 'git', ['rev-parse', wanted]).stdout);
  const origin = run(release, 'git', ['rev-parse', `origin/${wanted}`]);

  if (origin.status !== 0) {
    die(`git rev-parse origin/${wanted} failed: ${said(origin.stderr)}`);
  }

  if (said(origin.stdout) !== head) {
    die(
      `${wanted} is not origin/${wanted}: ${wanted} is ${head}, origin/${wanted} is ${said(origin.stdout)}`,
    );
  }
}

/** No `tag`, here or on origin. */
function notTagged(release: Release, tag: string): void {
  if (said(run(release, 'git', ['tag', '--list', tag]).stdout) !== '') {
    die(`${tag} is a tag already`);
  }

  const remote = run(release, 'git', [
    'ls-remote',
    '--tags',
    'origin',
    `refs/tags/${tag}`,
  ]);

  if (remote.status !== 0) {
    die(`git ls-remote origin failed: ${said(remote.stderr)}`);
  }

  if (said(remote.stdout) !== '') {
    die(`${tag} is a tag on origin already: ${said(remote.stdout)}`);
  }
}
