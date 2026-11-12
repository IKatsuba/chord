/**
 * The release's last stage, from the package's publish data: the packed
 * tarballs published to npm in its order, then, once npm answers for each,
 * the main one (chord's, whose exact-version optionalDependencies must
 * resolve); then, once npm answers for all, the built commit tagged in the
 * package's form and the tag pushed, and for chord a draft GitHub release
 * made of it with the source archives. Each act is recorded in the
 * release's state, so a stopped publish is finished from what it recorded.
 * Never unpublish, and never publish the draft: that is the owner's.
 *
 * npm asks the owner to authorise each publish in the terminal and the
 * browser, so each `npm publish` gets the terminal and is waited on however
 * long that takes.
 */
import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { channelOf } from '../../../src/channel.ts';
import {
  die,
  mainName,
  npm,
  published,
  type Release,
  ReleaseError,
  type ReleasePackage,
  run,
  said,
  tagName,
  waitPublished,
} from './lib.ts';
import { draftRelease, fetchedSource } from './source.ts';
import { draftAt, tagAt } from './continue.ts';
import { abandon, type ReleaseState } from './state.ts';
import { checkSum } from './sums.ts';

/** Where `folder`'s package leaves its packed tarballs and their SHA256SUMS. */
export function tarballs(release: Release, folder: string): string {
  return join(release.root, folder, 'dist', 'release', 'tgz');
}

/** The tarball of the npm package `name` at `version`, as npm pack names it. */
export function tarball(
  release: Release,
  folder: string,
  name: string,
  version: string,
): string {
  return join(
    tarballs(release, folder),
    `${name.replace(/^@/, '').replace('/', '-')}-${version}.tgz`,
  );
}

/**
 * npm's arguments to publish `file` at `version`. The tag comes from the
 * version and nowhere else, as npm moves latest for a publish with no tag: a
 * pre-release cannot reach here without its channel's.
 */
export function publishArguments(version: string, file: string): string[] {
  const channel = channelOf(version);
  const args = ['publish', '--access', 'public', file];

  return channel === null ? args : [...args, '--tag', channel];
}

/**
 * The release's state as publish reads and writes it: before and after
 * every act npm, git or GitHub cannot take back (CHD-623).
 */
export interface Recorded {
  readonly state: () => ReleaseState;
  readonly record: (change: (state: ReleaseState) => ReleaseState) => void;
}

export interface PublishOptions {
  readonly version: string;
  readonly recorded: Recorded;
}

/**
 * Publishes `of`'s npm names the state does not have answered, the main one
 * last, each recorded pending before `npm publish`, sent once npm exits 0
 * and answered once `npm view` has it; then tags the state's built commit,
 * and for a package with a GitHub release drafts it, each recorded too.
 */
export async function publish(
  release: Release,
  of: ReleasePackage,
  { version, recorded }: PublishOptions,
): Promise<void> {
  const main = mainName(of);
  const tag = tagName(of, version);
  const draft = of.publish.githubRelease === true;
  const npmState = (name: string) => recorded.state().npm[name];
  const npmRecord = (name: string, to: 'pending' | 'sent' | 'answered') =>
    recorded.record((state) => ({
      ...state,
      npm: { ...state.npm, [name]: to },
    }));
  // Before anything npm cannot take back.
  const archives =
    draft && recorded.state().draft?.state !== 'made'
      ? fetchedSource(release)
      : [];
  let asked = false;

  const publishOne = (name: string) => {
    // One a killed run left pending: npm's answer settles it, as npm
    // refuses one version twice.
    if (npmState(name) === 'pending' && published(release, name, version)) {
      npmRecord(name, 'answered');
    }

    if (npmState(name) !== undefined && npmState(name) !== 'pending') {
      return;
    }

    // Not started by this release, so npm having it is someone else's.
    if (npmState(name) === undefined && published(release, name, version)) {
      die(
        `npm has ${name}@${version}, which this release did not publish; ${abandon(of.name)}`,
      );
    }

    const file = tarball(release, of.folder, name, version);

    if (!existsSync(file)) {
      die(`no ${file} to publish; nothing of this run is left to resume from`);
    }

    checkSum(file);

    if (!asked) {
      if (!release.tty) {
        die(
          'npm publish asks in the terminal to authorise each publish; run this with stdin and stdout on a terminal',
        );
      }

      release.out(
        'npm will ask to authorise each publish: press Enter when it asks, then approve in the browser',
      );

      asked = true;
    }

    npmRecord(name, 'pending');

    const sent = npm(release, publishArguments(version, file), {
      stdio: 'inherit',
    });

    if (sent.status !== 0) {
      die(`npm publish of ${file} failed`);
    }

    npmRecord(name, 'sent');
  };

  const answered = async (name: string) => {
    if (npmState(name) === 'answered') {
      return true;
    }

    if (!(await waitPublished(release, name, version))) {
      return false;
    }

    npmRecord(name, 'answered');

    return true;
  };

  for (const name of of.publish.npm.slice(0, -1)) {
    publishOne(name);
  }

  // The main package only once every other answers at the version: chord's,
  // published while a platform package is still in npm's validation,
  // installs with no binary, and `chord upgrade` prunes the old one on the
  // way.
  for (const name of of.publish.npm.slice(0, -1)) {
    if (!(await answered(name))) {
      die(
        `${name}@${version} did not answer npm view in 15 minutes; ${main} was not published. Rerun \`bun dev release ${of.name}\` once \`npm view ${name}@${version} version\` answers, and it resumes from there`,
      );
    }
  }

  publishOne(main);

  if (!(await answered(main))) {
    die(
      `${main}@${version} did not answer npm view in 15 minutes; ${tag} was not tagged. Once \`npm view ${main}@${version} version\` answers, tag it with: git tag -a ${tag} -m "${of.name} v${version}" ${recorded.state().built} && git push origin ${tag}, or run \`bun dev release ${of.name}\` to continue`,
    );
  }

  tagged(release, recorded, tag, `${of.name} v${version}`);

  if (draft && recorded.state().draft?.state !== 'made') {
    // A draft a killed run left pending may be on GitHub already.
    let url =
      recorded.state().draft?.state === 'pending'
        ? draftAt(release, tag)
        : undefined;

    recorded.record((state) => ({ ...state, draft: { state: 'pending' } }));

    if (url === undefined) {
      try {
        url = draftRelease(
          release,
          version,
          tag,
          `${of.name} ${tag}`,
          archives,
        );
      } catch (error) {
        if (!(error instanceof ReleaseError)) {
          throw error;
        }

        die(
          `${error.message}\nor run \`bun dev release ${of.name}\` to continue`,
        );
      }
    }

    const made = url;

    recorded.record((state) => ({
      ...state,
      draft: { state: 'made', url: made },
    }));
  }
}

/**
 * `name` made on the state's built commit, annotated with `message`, and
 * pushed to origin, each recorded.
 */
function tagged(
  release: Release,
  recorded: Recorded,
  name: string,
  message: string,
): void {
  const tag = (to: 'pending' | 'made' | 'pushed') =>
    recorded.record((state) => ({ ...state, tag: { state: to } }));

  if (recorded.state().tag?.state === 'pushed') {
    return;
  }

  // One a killed run left pending: where the tag is settles it.
  if (recorded.state().tag?.state === 'pending') {
    const built = recorded.state().built;
    const at = tagAt(release, name);
    const elsewhere = [at.here, at.origin].find(
      (sha) => sha !== undefined && sha !== built,
    );

    if (elsewhere !== undefined) {
      die(
        `${name} is on ${elsewhere}, not on ${built}, which the release built`,
      );
    }

    if (at.origin === built) {
      tag('pushed');

      return;
    }

    if (at.here === built) {
      tag('made');
    }
  }

  if (recorded.state().tag?.state !== 'made') {
    tag('pending');

    const made = run(release, 'git', [
      'tag',
      '-a',
      name,
      '-m',
      message,
      recorded.state().built,
    ]);

    if (made.status !== 0) {
      die(`git tag -a ${name} failed: ${said(made.stderr)}`);
    }

    tag('made');
  }

  const pushed = run(release, 'git', ['push', 'origin', name]);

  if (pushed.status !== 0) {
    die(`git push origin ${name} failed: ${said(pushed.stderr)}`);
  }

  tag('pushed');
}
