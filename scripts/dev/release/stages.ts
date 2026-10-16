/**
 * `bun run dev release`: the release, on the owner's arm64 Mac, not in CI,
 * as stages run in order, each checked before the next. Build every binary,
 * sign the macOS ones and the native libraries they embed, self-test,
 * notarise, pack, verify the installed copies, and publish to npm: the
 * platform packages, then, once npm answers for each, the main one. The last
 * line printed is the published version, printed only when everything held
 * and the version is tagged.
 */
import { join } from 'node:path';
import { check, compile, install, natives } from './build.ts';
import { die, identity, type Package, type Release, run, said } from './lib.ts';
import { notarise, PROFILE } from './notarise.ts';
import { pack } from './pack.ts';
import { preflight } from './preflight.ts';
import { publish, tarballs } from './publish.ts';
import { selftest } from './selftest.ts';
import { type ReleaseOptions, type Stage } from './select.ts';
import { sign } from './sign.ts';

const ARM = 'dist/bun-darwin-arm64/chord';
const X64 = 'dist/bun-darwin-x64/chord';

/** Runs `stages`, guarded as the owner decided, on `release`. */
export async function runRelease(
  release: Release,
  stages: readonly Stage[],
  options: ReleaseOptions,
  machine: { platform: string; arch: string } = process,
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

  // A clean tree, the version not yet published (or a run stopped between
  // publishes to resume), and the owner's npm login; for a run that
  // publishes, main level with origin's and no tag yet.
  const { mode, version } = preflight(release, {
    dryRun,
    publish: has('publish'),
  });

  // A run stopped between publishes is finished from the packages it built,
  // without building again.
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
