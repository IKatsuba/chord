/**
 * The checks every release runs first, which only read: the tree clean,
 * untracked files included (a published build that no commit describes
 * cannot be rebuilt); the version from package.json not on npm for
 * @chorded/chord, or a run stopped between publishes to resume; and the
 * owner's npm login. A run that publishes also needs main, level with
 * origin's, and the version not yet a tag.
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
}

export function preflight(
  release: Release,
  { dryRun, publish }: PreflightOptions,
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

  // 2. The version, refused if the main package has it.
  const version = packageVersion(release);

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

  // 3. The owner's own npm login, before anything is built or published.
  const who = run(release, 'npm', ['whoami']);

  if (who.status !== 0) {
    die(`npm whoami failed: ${said(who.stdout + who.stderr)}`);
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
