/**
 * Eligibility guards before authentication or release work: a clean tree,
 * a new version only once package.json's is published, an unpublished
 * version or a stopped publish to resume; publishing also
 * requires main level with origin and no version tag. Registry reads and
 * the existing fetch may use the network, but these guards do not log in.
 */
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { die, PLATFORMS, published, type Release, run, said } from './lib.ts';

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
  { dryRun, publish, version = packageVersion(release) }: PreflightOptions,
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
  const current = packageVersion(release);

  if (version !== current && !published(release, 'chord', current)) {
    die(
      `@chorded/chord@${current} is not published yet; \`bun dev release\` without a version finishes it`,
    );
  }

  // 3. The version, refused if the main package has it.
  if (published(release, 'chord', version)) {
    die(`@chorded/chord@${version} is on npm already`);
  }

  let mode: Preflight['mode'] = 'fresh';

  for (const name of PLATFORMS) {
    if (published(release, name, version)) {
      if (dryRun) {
        die(
          `--dry-run does not resume a stopped publish: @chorded/${name}@${version} is published`,
        );
      }

      if (!publish) {
        die(
          `a run without publish does not resume a stopped publish: @chorded/${name}@${version} is published; include publish`,
        );
      }

      mode = 'resume';

      break;
    }
  }

  if (publish) {
    onMain(release);
    notTagged(release, version);
  }

  return { mode, version };
}

/** package.json's version. */
export function packageVersion(release: Release): string {
  let version: unknown;

  try {
    version = (
      JSON.parse(readFileSync(join(release.root, 'package.json'), 'utf8')) as {
        version?: unknown;
      }
    ).version;
  } catch {
    version = undefined;
  }

  if (typeof version !== 'string' || version === '') {
    die('package.json has no version');
  }

  return version;
}

/** main checked out, and the same commit as origin's once fetched. */
function onMain(release: Release): void {
  const branch = run(release, 'git', ['symbolic-ref', '--short', 'HEAD']);

  if (branch.status !== 0 || said(branch.stdout) !== 'main') {
    die(
      `a release that publishes runs from main; HEAD is ${said(branch.stdout) || said(branch.stderr)}`,
    );
  }

  const fetched = run(release, 'git', ['fetch', 'origin']);

  if (fetched.status !== 0) {
    die(`git fetch origin failed: ${said(fetched.stderr)}`);
  }

  const head = said(run(release, 'git', ['rev-parse', 'main']).stdout);
  const origin = run(release, 'git', ['rev-parse', 'origin/main']);

  if (origin.status !== 0) {
    die(`git rev-parse origin/main failed: ${said(origin.stderr)}`);
  }

  if (said(origin.stdout) !== head) {
    die(
      `main is not origin/main: main is ${head}, origin/main is ${said(origin.stdout)}`,
    );
  }
}

/** No v<version> tag, here or on origin. */
function notTagged(release: Release, version: string): void {
  const tag = `v${version}`;

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
