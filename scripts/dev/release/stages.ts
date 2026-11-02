/**
 * `bun dev release`: the release, on the owner's arm64 Mac, not in CI,
 * as stages run in order, each checked before the next. Build every binary,
 * sign the macOS ones and the native libraries they embed, self-test,
 * notarise, pack, verify the installed copies, and publish to npm: the
 * platform packages, then, once npm answers for each, the main one. The last
 * line printed is the published version, printed only when everything held
 * and the version is tagged.
 */
import { join } from 'node:path';
import { authenticate } from './authenticate.ts';
import { check, compile, install, natives } from './build.ts';
import { commitVersion, holdVersion, pushVersion } from './bump.ts';
import { channelOf } from '../../../src/channel.ts';
import {
  die,
  identity,
  npm,
  type Package,
  type Release,
  run,
  said,
} from './lib.ts';
import { notarise, PROFILE } from './notarise.ts';
import { pack } from './pack.ts';
import { packageVersion, preflight } from './preflight.ts';
import { publish, tarballs } from './publish.ts';
import { selftest } from './selftest.ts';
import { type ReleaseOptions, type Stage } from './select.ts';
import { sign } from './sign.ts';
import { releaseVersion, VersionError } from './version.ts';

const ARM = 'dist/bun-darwin-arm64/chord';
const X64 = 'dist/bun-darwin-x64/chord';

/**
 * Runs `stages`, guarded as the owner decided, on `release`, at `wanted`:
 * a version or a bump of package.json's, or package.json's own if none.
 */
export async function runRelease(
  release: Release,
  stages: readonly Stage[],
  options: ReleaseOptions,
  machine: { platform: string; arch: string } = process,
  wanted?: string,
): Promise<void> {
  const has = (stage: Stage) => stages.includes(stage);
  const dryRun = options.dryRun ?? false;

  // Signing and notarisation need this Mac's keychain and Rosetta: refused
  // at once anywhere else.
  if (
    (has('natives') || has('sign') || has('notarise')) &&
    !(machine.platform === 'darwin' && machine.arch === 'arm64')
  ) {
    die(
      `natives, sign and notarise run only on an arm64 Mac; this is ${machine.platform}-${machine.arch}`,
    );
  }

  // Eligibility is checked before npm may hand over the terminal or save
  // credentials; publishing also requires the version's branch level with
  // origin and no tag.
  const current = packageVersion(release);
  const next = target(release, current, wanted, options.channel);

  // The version enters the binary at compile: a run without it would pack
  // or publish what was built at package.json's.
  if (next !== current && !has('compile')) {
    die(
      `a new version needs the compile stage: ${next} is not package.json's ${current}`,
    );
  }

  const { mode, version } = preflight(release, {
    dryRun,
    publish: has('publish'),
    version: next,
  });

  if (mode === 'resume' && version !== current) {
    die(
      `a stopped publish resumes package.json's version ${current}, not ${version}; run it without a version`,
    );
  }

  authenticate(release);

  // A stopped publish uses its existing packages without building again.
  if (mode === 'resume') {
    release.out(
      `resuming ${version}: a platform package is published, @chorded/chord is not`,
    );
    await published(release, version, options.package);

    return;
  }

  // The signing identity and Apple's credentials, found before the build.
  if (has('natives') || has('sign')) {
    identity(release);
  }

  if (has('notarise')) {
    const history = run(release, 'xcrun', [
      'notarytool',
      'history',
      '--keychain-profile',
      PROFILE,
    ]);

    if (history.status !== 0) {
      die(
        `xcrun notarytool history --keychain-profile ${PROFILE} failed: ${said(history.stdout + history.stderr)}`,
      );
    }
  }

  const out = join(release.root, 'dist', 'release');
  const steps: Record<Stage, () => void | Promise<void>> = {
    install: () => install(release),
    check: () => check(release),
    natives: () => natives(release),
    compile: () => compile(release),
    sign: () => sign(release, [ARM, X64]),
    selftest: async () => {
      await selftest(release, ARM);
      await selftest(release, X64, 'x86_64');
    },
    // One zip notarised; Apple's log must list a ticket for each.
    notarise: () => notarise(release, out, [ARM, X64]),
    pack: () => pack(release),
    publish: () => published(release, version, options.package),
  };

  // A new version is written and committed before any stage reads it; a
  // run that publishes keeps the commit on origin once pushed, any other
  // drops it.
  const held =
    version === current
      ? undefined
      : holdVersion(release, commitVersion(release, version));

  try {
    if (held !== undefined && has('publish')) {
      pushVersion(release, version, held);
    }

    for (const stage of stages) {
      await steps[stage]();
    }

    if (dryRun) {
      release.out(
        has('pack')
          ? `dry run: @chorded/chord ${version} is packed in ${tarballs(release)}, not published`
          : `dry run: @chorded/chord ${version}, ran ${stages.join(', ')}; not published`,
      );
    }
  } finally {
    // Kept once pushed, so only an unpushed commit is dropped.
    held?.drop();
  }
}

/**
 * The version `wanted` makes of `current`, or the release dies saying why.
 * Its channel is asked here too, so a label no channel can have, in a
 * package.json edited by hand, stops before the guards that follow it.
 */
function target(
  release: Release,
  current: string,
  wanted: string | undefined,
  channel: string | undefined,
): string {
  try {
    const version = releaseVersion(current, wanted, channel, () =>
      latestStable(release),
    );

    channelOf(version);

    return version;
  } catch (error) {
    if (error instanceof VersionError) {
      die(error.message);
    }

    throw error;
  }
}

/** npm's latest stable version, which a bump on a channel counts from. */
function latestStable(release: Release): string {
  const view = npm(release, ['view', '@chorded/chord', 'dist-tags.latest']);

  if (view.status !== 0) {
    die(
      `npm view @chorded/chord dist-tags.latest failed: ${said(view.stderr)}`,
    );
  }

  return said(view.stdout);
}

/** Publishes, and prints the version last once it is tagged. */
async function published(
  release: Release,
  version: string,
  only: Package | undefined,
): Promise<void> {
  if (await publish(release, { version, only })) {
    release.out(version);
  }
}
