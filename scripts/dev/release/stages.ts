/**
 * `bun dev release <package>`: one package's release, not in CI, as the
 * stages of its steps.ts run in order, each checked before the next.
 * chord's, on the owner's arm64 Mac, builds every binary, signs the macOS
 * ones and the native libraries they embed, self-tests, notarises, packs,
 * verifies the installed copies, and publishes to npm: the platform
 * packages, then, once npm answers for each, the main one. The last line
 * printed is the published version, printed only when everything held and
 * the version is tagged.
 */
import { join } from 'node:path';
import { authenticate } from './authenticate.ts';
import { compile, install, natives, quality } from './build.ts';
import { commitVersion, holdVersion, pushVersion } from './bump.ts';
import { channelOf } from '../../../src/channel.ts';
import {
  die,
  identity,
  mainName,
  npm,
  type Release,
  type ReleasePackage,
  run,
  said,
} from './lib.ts';
import { notarise, PROFILE } from './notarise.ts';
import { pack } from './pack.ts';
import { packageVersion, preflight } from './preflight.ts';
import { publish, publishArguments, tarball, tarballs } from './publish.ts';
import { selftest } from './selftest.ts';
import type { ReleaseOptions } from './select.ts';
import { type FoundPackage, isPublish, type Stage } from '../steps.ts';
import { sign } from './sign.ts';
import { releaseVersion, VersionError } from './version.ts';

const ARM = 'dist/bun-darwin-arm64/chord';
const X64 = 'dist/bun-darwin-x64/chord';

/**
 * chord's stages and what they need ready, each on a release, which chord's
 * steps.ts imports lazily so parsing `bun dev` loads no release module.
 */
export const chord = {
  install: (release: Release) => install(release),
  quality: (release: Release) => quality(release, 'chord'),
  natives: (release: Release) => natives(release),
  compile: (release: Release) => compile(release),
  sign: (release: Release) => sign(release, [ARM, X64]),
  selftest: async (release: Release) => {
    await selftest(release, ARM);
    await selftest(release, X64, 'x86_64');
  },
  // One zip notarised; Apple's log must list a ticket for each.
  notarise: (release: Release) =>
    notarise(release, join(release.root, 'dist', 'release'), [ARM, X64]),
  pack: (release: Release) => pack(release),
  /** The one signing identity, found before the build. */
  identity: (release: Release) => void identity(release),
  /** Apple's credentials, found before the build. */
  notary: (release: Release) => notary(release),
};

/** Whether notarytool reads Apple's credentials from the keychain profile. */
function notary(release: Release): void {
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

/**
 * Runs `stages` of `found`'s release, guarded as the owner decided, on
 * `release`, at `wanted`: a version or a bump of package.json's, or
 * package.json's own if none.
 */
export async function runRelease(
  release: Release,
  found: FoundPackage,
  stages: readonly string[],
  options: ReleaseOptions,
  machine: { platform: string; arch: string } = process,
  wanted?: string,
): Promise<void> {
  const has = (stage: string) => stages.includes(stage);
  const dryRun = options.dryRun ?? false;
  const list = found.steps.release;
  const of = releasePackage(found);
  const main = mainName(of);
  const selected = list.filter((stage) => has(stage.name));
  const built = selected.filter((stage): stage is Stage => !isPublish(stage));

  // A stage that needs another machine (chord's signing: this Mac's keychain
  // and Rosetta) is refused at once anywhere else, only when selected.
  for (const stage of built) {
    if (
      stage.machine !== undefined &&
      !(
        machine.platform === stage.machine.platform &&
        machine.arch === stage.machine.arch
      )
    ) {
      const bound = list.filter(
        (each): each is Stage =>
          !isPublish(each) &&
          each.machine?.platform === stage.machine!.platform &&
          each.machine.arch === stage.machine!.arch,
      );

      die(
        `${listed(bound.map((each) => each.name))} ${bound.length === 1 ? 'runs' : 'run'} only on ${machineName(stage.machine)}; this is ${machine.platform}-${machine.arch}`,
      );
    }
  }

  // Eligibility is checked before npm may hand over the terminal or save
  // credentials; publishing also requires the version's branch level with
  // origin and no tag.
  const current = packageVersion(release, of.folder);
  const next = target(release, main, current, wanted, options.channel);
  const versioned = list
    .filter(
      (stage): stage is Stage => !isPublish(stage) && stage.versioned === true,
    )
    .map((stage) => stage.name);

  // The version enters what is published at a versioned stage (chord's
  // compile): a run without it would pack or publish what was built at
  // package.json's.
  if (next !== current && !versioned.some(has)) {
    die(
      `a new version needs the ${listed(versioned, 'or')} stage: ${next} is not package.json's ${current}`,
    );
  }

  const { mode, version } = preflight(release, of, {
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
      `resuming ${version}: a package before ${main} is published, ${main} is not`,
    );
    await published(release, of, version);

    return;
  }

  // The package's own preflight (chord's agent pins, CHD-622).
  await found.steps.preflight?.(release, version);

  // What the selected stages need, found before the build, each once.
  for (const ready of new Set(built.flatMap((stage) => stage.ready ?? []))) {
    await ready(release);
  }

  // A new version is written and committed before any stage reads it; a
  // run that publishes keeps the commit on origin once pushed, any other
  // drops it.
  const held =
    version === current
      ? undefined
      : holdVersion(release, commitVersion(release, of, version));

  try {
    if (held !== undefined && has('publish')) {
      pushVersion(release, of, version, held);
    }

    for (const stage of selected) {
      await (isPublish(stage)
        ? published(release, of, version)
        : stage.run(release, version));
    }

    if (dryRun) {
      // A channel's run shows what would publish, so a dry run from its
      // branch proves the tags before the owner's first real publish.
      if (channelOf(version) !== null) {
        release.out(`dry run: ran ${stages.join(', ')}`);

        for (const name of of.publish.npm) {
          release.out(
            `dry run: npm ${publishArguments(version, tarball(release, of.folder, name, version)).join(' ')}`,
          );
        }
      }

      release.out(
        has('pack')
          ? `dry run: ${main} ${version} is packed in ${tarballs(release, of.folder)}, not published`
          : `dry run: ${main} ${version}, ran ${stages.join(', ')}; not published`,
      );
    }
  } finally {
    // Kept once pushed, so only an unpushed commit is dropped.
    held?.drop();
  }
}

/** `a`, `a and b`, `a, b and c`. */
function listed(names: readonly string[], and = 'and'): string {
  return names.length < 2
    ? names.join('')
    : `${names.slice(0, -1).join(', ')} ${and} ${names.at(-1)}`;
}

/** How a refusal names a machine: chord's is "an arm64 Mac". */
function machineName({ platform, arch }: NonNullable<Stage['machine']>) {
  return platform === 'darwin' ? `an ${arch} Mac` : `${platform}-${arch}`;
}

/**
 * The version `wanted` makes of `current`, or the release dies saying why.
 * Its channel is asked here too, so a label no channel can have, in a
 * package.json edited by hand, stops before the guards that follow it.
 */
function target(
  release: Release,
  main: string,
  current: string,
  wanted: string | undefined,
  channel: string | undefined,
): string {
  try {
    const version = releaseVersion(current, wanted, channel, () =>
      latestStable(release, main),
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

/**
 * npm's latest stable version of the package's main npm name, which a bump
 * on a channel counts from.
 */
function latestStable(release: Release, main: string): string {
  const view = npm(release, ['view', main, 'dist-tags.latest']);

  if (view.status !== 0) {
    die(`npm view ${main} dist-tags.latest failed: ${said(view.stderr)}`);
  }

  return said(view.stdout);
}

/** Publishes, and prints the version last once it is tagged. */
async function published(
  release: Release,
  of: ReleasePackage,
  version: string,
): Promise<void> {
  await publish(release, of, { version });
  release.out(version);
}

/** What the release reads of a found package: its name, folder and publish data. */
function releasePackage(found: FoundPackage): ReleasePackage {
  return {
    name: found.name,
    folder: found.folder,
    publish: found.steps.release.find(isPublish)!,
  };
}
