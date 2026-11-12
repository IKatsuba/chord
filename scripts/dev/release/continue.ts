/**
 * A release that goes on from its state (CHD-623): the guards a run with a
 * state passes before npm authentication, and the acts a killed run left
 * pending, settled by reading git, npm or GitHub once. Nothing else is
 * inferred from them: what the state does not record is refused.
 */
import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { die, type Release, type ReleasePackage, run, said } from './lib.ts';
import { withVersion } from './bump.ts';
import { abandon, type ReleaseState } from './state.ts';
import { sha256 } from './sums.ts';

/** A refusal a state causes, naming how to abandon the release (S1). */
function refuse(of: ReleasePackage, why: string): never {
  die(`${why}; ${abandon(of.name)}`);
}

/** `args`'s output, or the release stops naming the command. */
function git(release: Release, ...args: string[]): string {
  const ran = run(release, 'git', args);

  if (ran.status !== 0) {
    die(`git ${args.join(' ')} failed: ${said(ran.stderr)}`);
  }

  return said(ran.stdout);
}

/** Whether `git args` succeeds. */
function holds(release: Release, ...args: string[]): boolean {
  return run(release, 'git', args).status === 0;
}

/** What a pending version commit turned out to be. */
export type VersionCommit =
  | { readonly at: 'none' }
  | { readonly at: 'base' }
  | { readonly at: 'made'; readonly sha: string };

/**
 * The version commit as the state and HEAD have it: none to make, one left
 * pending that never happened (HEAD is still `base`), or one made before the
 * run was killed (HEAD is `base` plus only the version change). Anything
 * else is refused.
 */
export function versionCommit(
  release: Release,
  of: ReleasePackage,
  state: ReleaseState,
): VersionCommit {
  const commit = state.versionCommit;

  if (commit === undefined || commit.state !== 'pending') {
    return { at: 'none' };
  }

  const head = git(release, 'rev-parse', 'HEAD');

  if (head === state.base) {
    return { at: 'base' };
  }

  const parent = run(release, 'git', ['rev-parse', 'HEAD~1']);

  if (
    said(parent.stdout) === state.base &&
    onlyVersion(release, of, state.base, head, state.version)
  ) {
    return { at: 'made', sha: head };
  }

  refuse(
    of,
    `the version commit of ${of.name} ${state.version} was left pending on ${state.base}, and HEAD ${head} is neither that commit nor it plus only the version change`,
  );
}

/**
 * Whether `head` changes `base` by the version alone: the package's
 * package.json as `base` had it with only the version replaced, and, for a
 * workspace package, bun.lock's lines that differ only by that version.
 */
function onlyVersion(
  release: Release,
  of: ReleasePackage,
  base: string,
  head: string,
  version: string,
): boolean {
  const manifest = join(of.folder, 'package.json');
  const changed = git(release, 'diff', '--name-only', base, head)
    .split('\n')
    .filter((path) => path !== '');
  const show = (commit: string, path: string) =>
    run(release, 'git', ['show', `${commit}:${path}`]).stdout;
  const before = versionAt(release, base, manifest);

  if (
    !changed.includes(manifest) ||
    changed.some((path) => path !== manifest && path !== 'bun.lock') ||
    show(head, manifest) !== withVersion(show(base, manifest), version) ||
    before === undefined
  ) {
    return false;
  }

  if (!changed.includes('bun.lock')) {
    return true;
  }

  // Bun records a workspace package's version in bun.lock, never the root's.
  const lines = git(release, 'diff', '-U0', base, head, '--', 'bun.lock')
    .split('\n')
    .filter((line) => /^[-+]/.test(line) && !/^(---|\+\+\+) /.test(line));
  const removed = lines.filter((line) => line.startsWith('-'));
  const added = lines.filter((line) => line.startsWith('+'));
  const old = new RegExp(`("version":\\s*)"${before.replaceAll('.', '\\.')}"`);

  return (
    of.folder !== '.' &&
    removed.length > 0 &&
    removed.length === added.length &&
    removed.every(
      (line, at) =>
        old.test(line) &&
        `+${line.slice(1).replace(old, `$1"${version}"`)}` === added[at],
    )
  );
}

/** The version `manifest` holds at `commit`, if it holds one. */
function versionAt(
  release: Release,
  commit: string,
  manifest: string,
): string | undefined {
  const shown = run(release, 'git', ['show', `${commit}:${manifest}`]);

  try {
    return (JSON.parse(shown.stdout) as { version?: string }).version;
  } catch {
    return undefined;
  }
}

/** What the guards are asked of a run with a state. */
export interface Continuation {
  /** The commit the stages build from, once a pending version commit is settled. */
  readonly built: string;
  /** Whether a stage before publish is left to run. */
  readonly building: boolean;
  /** Whether publish is left. */
  readonly publishing: boolean;
  /** The done stages that stay done, in stage order, whose recorded sums must hold. */
  readonly kept: readonly string[];
  /** Whether the run may record HEAD as the new built commit. */
  readonly rebuild: boolean;
}

/**
 * The guards before npm authentication: a clean tree, `built` in HEAD's
 * history at the state's version, HEAD at `built` while a stage before
 * publish is left, the branch level with origin and no tag the state did
 * not make while publish is left, and every recorded sum still holding.
 */
export function guarded(
  release: Release,
  of: ReleasePackage,
  state: ReleaseState,
  at: Continuation,
): void {
  const dirty = git(release, 'status', '--porcelain', '--untracked-files=all');

  if (dirty !== '') {
    refuse(of, `the tree is not clean:\n${dirty}`);
  }

  const head = git(release, 'rev-parse', 'HEAD');

  if (!holds(release, 'merge-base', '--is-ancestor', at.built, 'HEAD')) {
    refuse(
      of,
      `${of.name} ${state.version} was built from ${at.built}, which is not in HEAD ${head}'s history`,
    );
  }

  const manifest = join(of.folder, 'package.json');
  const version = versionAt(release, at.built, manifest);

  if (state.versionCommit?.state !== 'pending' && version !== state.version) {
    refuse(
      of,
      `${manifest} at ${at.built} is ${version ?? 'without a version'}, not ${of.name} ${state.version}`,
    );
  }

  // Building again from HEAD: it must still be the state's version.
  if (at.rebuild && head !== at.built) {
    const now = versionAt(release, head, manifest);

    if (now !== state.version) {
      refuse(
        of,
        `${manifest} at HEAD ${head} is ${now ?? 'without a version'}, not ${of.name} ${state.version}, so it cannot be built again from HEAD`,
      );
    }
  }

  if (at.building && head !== at.built && !at.rebuild) {
    refuse(
      of,
      `HEAD ${head} is not ${at.built}, which ${of.name} ${state.version} is built from, and a stage before publish is left: the stages build from it`,
    );
  }

  if (at.publishing) {
    level(release, of, state, head);
    foreignTag(release, of, state, at.built);
  }

  // A path a later stage records again (sign over compile's macOS
  // binaries) holds by the later stage's sum; with that stage cleared to run
  // again, the earlier one's applies, so changing it again starts from the
  // earlier stage.
  const latest = new Map<string, { stage: string; sum: string }>();

  for (const stage of at.kept) {
    for (const [path, sum] of Object.entries(
      state.stages[stage]?.outputs ?? {},
    )) {
      latest.set(path, { stage, sum });
    }
  }

  for (const [path, { stage, sum }] of latest) {
    const file = join(release.root, path);

    if (!existsSync(file)) {
      refuse(
        of,
        `${path}, which ${stage} left, is gone; run ${stage} again with --from ${stage}`,
      );
    }

    const now = sha256(file);

    if (now !== sum) {
      refuse(
        of,
        `${path} is not what ${stage} left: its sha256 is ${now}, the state recorded ${sum}; run ${stage} again with --from ${stage}`,
      );
    }
  }
}

/**
 * The state's branch checked out and level with origin, or, with the
 * version commit made and not pushed, origin at its parent.
 */
function level(
  release: Release,
  of: ReleasePackage,
  state: ReleaseState,
  head: string,
): void {
  const branch = said(
    run(release, 'git', ['symbolic-ref', '--short', 'HEAD']).stdout,
  );

  if (branch !== state.branch) {
    refuse(
      of,
      `${of.name} ${state.version} publishes from ${state.branch}; HEAD is ${branch || head}`,
    );
  }

  git(release, 'fetch', 'origin');

  const origin = git(release, 'rev-parse', `origin/${state.branch}`);
  const commit = state.versionCommit;
  // A version commit made and not recorded pushed: origin before the push,
  // or after one the run did not live to record.
  const want =
    commit?.state === 'made' && commit.sha !== undefined
      ? [git(release, 'rev-parse', `${commit.sha}~1`), commit.sha]
      : [head];

  if (!want.includes(origin)) {
    refuse(
      of,
      `${state.branch} is not level with origin/${state.branch}: ${state.branch} is ${head}, origin/${state.branch} is ${origin}`,
    );
  }
}

/** Where a tag points, here and on origin, peeled to its commit. */
export function tagAt(
  release: Release,
  tag: string,
): { readonly here?: string; readonly origin?: string } {
  const here = run(release, 'git', [
    'rev-parse',
    '-q',
    '--verify',
    `refs/tags/${tag}^{commit}`,
  ]);
  const remote = git(release, 'ls-remote', '--tags', 'origin')
    .split('\n')
    .map((line) => line.split('\t'))
    .filter(
      ([, ref]) => ref === `refs/tags/${tag}` || ref === `refs/tags/${tag}^{}`,
    );
  // An annotated tag lists its object, then the commit it peels to.
  const origin = (remote.find(([, ref]) => ref?.endsWith('^{}')) ??
    remote[0])?.[0];

  return {
    ...(here.status === 0 && said(here.stdout) !== ''
      ? { here: said(here.stdout) }
      : {}),
    ...(origin === undefined ? {} : { origin }),
  };
}

/** A tag of the version the state did not make, or one on another commit, is refused. */
function foreignTag(
  release: Release,
  of: ReleasePackage,
  state: ReleaseState,
  built: string,
): void {
  const tag = of.publish.tag.replaceAll('{version}', state.version);
  const { here, origin } = tagAt(release, tag);
  const found = [here, origin].filter((sha) => sha !== undefined);

  if (found.length === 0) {
    return;
  }

  if (state.tag === undefined) {
    refuse(of, `${tag} is a tag already, which this release did not make`);
  }

  if (found.some((sha) => sha !== built)) {
    refuse(
      of,
      `${tag} is on ${found.find((sha) => sha !== built)}, not on ${built}, which ${of.name} ${state.version} is built from`,
    );
  }
}

/** Whether the draft of `tag` is on GitHub, and its URL. */
export function draftAt(release: Release, tag: string): string | undefined {
  const view = run(release, 'gh', [
    'release',
    'view',
    tag,
    '--json',
    'url',
    '--jq',
    '.url',
  ]);

  return view.status === 0 ? said(view.stdout) : undefined;
}
