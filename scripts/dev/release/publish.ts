/**
 * The release's last stage: the packed tarballs published to npm, the
 * platform packages first, then, once npm answers for each, the main one,
 * whose exact-version optionalDependencies must resolve; then, once npm
 * answers for all five, the version tagged and the tag pushed. What npm has
 * already is skipped, so a stopped publish is finished by running it again.
 * Never unpublish.
 *
 * npm asks the owner to authorise each publish in the terminal and the
 * browser, so each `npm publish` gets the terminal and is waited on however
 * long that takes.
 */
import { existsSync } from 'node:fs';
import { join } from 'node:path';
import {
  die,
  npm,
  type Package,
  PACKAGES,
  PLATFORMS,
  published,
  type Release,
  run,
  said,
  waitPublished,
} from './lib.ts';
import { checkSum } from './sums.ts';

/** Where the packed tarballs and their SHA256SUMS are. */
export function tarballs(release: Release): string {
  return join(release.root, 'dist', 'release', 'tgz');
}

export interface PublishOptions {
  readonly version: string;
  /** Only this package; every one when absent. */
  readonly only?: Package | undefined;
}

/**
 * Publishes what npm does not have yet and tags the version once all five
 * answer. Answers whether it tagged: a single platform package published
 * while another is still missing leaves the tag to a later run.
 */
export async function publish(
  release: Release,
  { version, only }: PublishOptions,
): Promise<boolean> {
  let asked = false;

  const publishOne = (name: Package) => {
    if (published(release, name, version)) {
      release.out(`already published: @chorded/${name}@${version}`);

      return;
    }

    const tarball = join(tarballs(release), `chorded-${name}-${version}.tgz`);

    if (!existsSync(tarball)) {
      die(
        `no ${tarball} to publish; nothing of this run is left to resume from`,
      );
    }

    checkSum(tarball);

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

    const sent = npm(release, ['publish', '--access', 'public', tarball], {
      stdio: 'inherit',
    });

    if (sent.status !== 0) {
      die(`npm publish of ${tarball} failed`);
    }
  };

  // The main package only once every platform package answers at the
  // version: published while one is still in npm's validation, it installs
  // with no binary, and `chord upgrade` prunes the old one on the way.
  const publishMain = async () => {
    for (const name of PLATFORMS) {
      if (!(await waitPublished(release, name, version))) {
        die(
          `@chorded/${name}@${version} did not answer npm view in 15 minutes; @chorded/chord was not published. Rerun \`bun dev release\` once \`npm view @chorded/${name}@${version} version\` answers, and it resumes from there`,
        );
      }
    }

    publishOne('chord');

    if (!(await waitPublished(release, 'chord', version))) {
      die(
        `@chorded/chord@${version} did not answer npm view in 15 minutes; v${version} was not tagged. Once \`npm view @chorded/chord@${version} version\` answers, tag it with: git tag -a v${version} -m "chord v${version}" && git push origin v${version}`,
      );
    }
  };

  if (only === undefined) {
    for (const name of PLATFORMS) {
      publishOne(name);
    }

    await publishMain();
  } else if (only === 'chord') {
    await publishMain();
  } else {
    publishOne(only);

    const missing = PACKAGES.find((name) => !published(release, name, version));

    if (missing !== undefined) {
      release.err(
        `not tagged: @chorded/${missing}@${version} does not answer npm view yet; v${version} is tagged by the run that publishes the last of the five`,
      );

      return false;
    }
  }

  tag(release, version);

  return true;
}

/** The version tagged, annotated, and the tag pushed to origin. */
function tag(release: Release, version: string): void {
  const name = `v${version}`;
  const tagged = run(release, 'git', [
    'tag',
    '-a',
    name,
    '-m',
    `chord ${name}`,
  ]);

  if (tagged.status !== 0) {
    die(`git tag -a ${name} failed: ${said(tagged.stderr)}`);
  }

  const pushed = run(release, 'git', ['push', 'origin', name]);

  if (pushed.status !== 0) {
    die(`git push origin ${name} failed: ${said(pushed.stderr)}`);
  }
}
