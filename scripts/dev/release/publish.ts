/**
 * The release's last stage, from the package's publish data: the packed
 * tarballs published to npm in its order, then, once npm answers for each,
 * the main one (chord's, whose exact-version optionalDependencies must
 * resolve); then, once npm answers for all, the version tagged in the
 * package's form and the tag pushed, and for chord a draft GitHub release
 * made of it with the source archives. What npm has already is
 * skipped, so a stopped publish is finished by running it again. Never
 * unpublish, and never publish the draft: that is the owner's.
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
  type ReleasePackage,
  run,
  said,
  tagName,
  waitPublished,
} from './lib.ts';
import { draftRelease, fetchedSource } from './source.ts';
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

export interface PublishOptions {
  readonly version: string;
}

/**
 * Publishes what npm does not have yet of `of`'s npm names, the main one
 * last, and tags the version once all answer; then, for a package with a
 * GitHub release, drafts it.
 */
export async function publish(
  release: Release,
  of: ReleasePackage,
  { version }: PublishOptions,
): Promise<void> {
  const main = mainName(of);
  const tag = tagName(of, version);
  // Before anything npm cannot take back.
  const archives = of.publish.githubRelease ? fetchedSource(release) : [];
  let asked = false;

  const publishOne = (name: string) => {
    if (published(release, name, version)) {
      release.out(`already published: ${name}@${version}`);

      return;
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

    const sent = npm(release, publishArguments(version, file), {
      stdio: 'inherit',
    });

    if (sent.status !== 0) {
      die(`npm publish of ${file} failed`);
    }
  };

  for (const name of of.publish.npm.slice(0, -1)) {
    publishOne(name);
  }

  // The main package only once every other answers at the version: chord's,
  // published while a platform package is still in npm's validation,
  // installs with no binary, and `chord upgrade` prunes the old one on the
  // way.
  for (const name of of.publish.npm.slice(0, -1)) {
    if (!(await waitPublished(release, name, version))) {
      die(
        `${name}@${version} did not answer npm view in 15 minutes; ${main} was not published. Rerun \`bun dev release ${of.name}\` once \`npm view ${name}@${version} version\` answers, and it resumes from there`,
      );
    }
  }

  publishOne(main);

  if (!(await waitPublished(release, main, version))) {
    die(
      `${main}@${version} did not answer npm view in 15 minutes; ${tag} was not tagged. Once \`npm view ${main}@${version} version\` answers, tag it with: git tag -a ${tag} -m "${of.name} v${version}" && git push origin ${tag}`,
    );
  }

  tagged(release, tag, `${of.name} v${version}`);

  if (of.publish.githubRelease) {
    draftRelease(release, version, tag, `${of.name} ${tag}`, archives);
  }
}

/** `name` made, annotated with `message`, and pushed to origin. */
function tagged(release: Release, name: string, message: string): void {
  const made = run(release, 'git', ['tag', '-a', name, '-m', message]);

  if (made.status !== 0) {
    die(`git tag -a ${name} failed: ${said(made.stderr)}`);
  }

  const pushed = run(release, 'git', ['push', 'origin', name]);

  if (pushed.status !== 0) {
    die(`git push origin ${name} failed: ${said(pushed.stderr)}`);
  }
}
