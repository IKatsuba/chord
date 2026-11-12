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
import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { authenticate } from './authenticate.ts';
import { compile, install, natives, quality } from './build.ts';
import { commitVersion, type Held, holdVersion, pushVersion } from './bump.ts';
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
import { holdRelease } from './lock.ts';
import { pack } from './pack.ts';
import { packageVersion, preflight } from './preflight.ts';
import {
  publish,
  publishArguments,
  type Recorded,
  tarball,
  tarballs,
} from './publish.ts';
import { selftest } from './selftest.ts';
import type { ReleaseOptions } from './select.ts';
import {
  type FoundPackage,
  isPublish,
  type Publish,
  type Stage,
} from '../steps.ts';
import { sign } from './sign.ts';
import { guarded, versionCommit } from './continue.ts';
import { ghReady } from './source.ts';
import {
  cleared,
  clearState,
  finished,
  FORMAT,
  left,
  readState,
  type ReleaseState,
  writeState,
} from './state.ts';
import { sha256 } from './sums.ts';
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
  // One release per checkout, held from before any guard to the end.
  const unlock = await holdRelease(release);

  try {
    await locked(release, found, stages, options, machine, wanted);
  } finally {
    await unlock();
  }
}

/** The release `runRelease` runs once it holds the checkout's lock. */
async function locked(
  release: Release,
  found: FoundPackage,
  stages: readonly string[],
  options: ReleaseOptions,
  machine: { platform: string; arch: string },
  wanted: string | undefined,
): Promise<void> {
  const has = (stage: string) => stages.includes(stage);
  const dryRun = options.dryRun ?? false;
  const list = found.steps.release;
  const of = releasePackage(found);
  const main = mainName(of);
  const selected = list.filter((stage) => has(stage.name));
  const built = selected.filter((stage): stage is Stage => !isPublish(stage));

  // A state an earlier run left: a finished one is cleared, and the run goes
  // on without it; the run goes on from an unfinished one.
  const earlier = readState(release.root, of.name);

  if (earlier !== undefined) {
    if (!finished(earlier, of.publish.npm, of.publish.githubRelease === true)) {
      return continued(
        release,
        found,
        of,
        earlier,
        stages,
        options,
        machine,
        wanted,
      );
    }

    release.out(`${of.name} ${earlier.version} is released`);
    clearState(release.root, of.name);
  }

  onMachine(list, stages, machine);

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

  const { version } = preflight(release, of, {
    publish: has('publish'),
    version: next,
  });

  // The package's own preflight (chord's agent pins, CHD-622), after the
  // release's and before npm may hand over the terminal or save credentials.
  await found.steps.preflight?.(release, version);

  authenticate(release);

  // What the selected stages need, found before the build, each once.
  for (const ready of new Set(built.flatMap((stage) => stage.ready ?? []))) {
    await ready(release);
  }

  // What publish sends is what the stage before it left (pack's tarballs),
  // recorded in the state as it runs: never bytes no run recorded. Refused
  // here, before the first change to the world.
  const before = list.at(-2)?.name;

  if (has('publish') && before !== undefined && !has(before)) {
    die(
      `publish needs ${before}'s output; ${before} is not done in ${of.name} ${version}`,
    );
  }

  // The first change to the world: a run that publishes, or one at
  // package.json's version (`--to pack`, to publish later), keeps a state
  // from here; a dry run, or a run without publish that makes a new
  // version, keeps none.
  const base = head(release);
  const recorded =
    !dryRun && (has('publish') || version === current)
      ? record(release, {
          format: FORMAT,
          package: of.name,
          version,
          channel: channelOf(version),
          branch: channelOf(version) ?? 'main',
          base,
          built: base,
          stages: {},
          npm: {},
        })
      : undefined;

  // A new version is written and committed before any stage reads it. With
  // a state the commit stays, pushed when publishing, and a stopped run
  // goes on from it; without one it is dropped at the end, or on a signal.
  let held: Held | undefined;

  if (version !== current) {
    if (recorded === undefined) {
      held = holdVersion(release, commitVersion(release, of, version));
    } else {
      recorded.record((state) => ({
        ...state,
        versionCommit: { state: 'pending' },
      }));
      commitVersion(release, of, version, (files) =>
        recorded.record((state) => ({
          ...state,
          versionCommit: { state: 'pending', files },
        })),
      );

      const sha = head(release);

      recorded.record((state) => ({
        ...state,
        versionCommit: { state: 'made', sha },
        built: sha,
      }));

      if (has('publish')) {
        pushVersion(release, of, version);
        recorded.record((state) => ({
          ...state,
          versionCommit: { state: 'pushed', sha },
        }));
      }
    }
  }

  try {
    await ran(release, of, selected, version, recorded);

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
    held?.drop();
  }
}

/**
 * `selected` in order on `version`, each done stage recorded with its
 * outputs' sums; publish last, after which the state is removed and the
 * version printed last.
 */
async function ran(
  release: Release,
  of: ReleasePackage,
  selected: readonly (Stage | Publish)[],
  version: string,
  recorded: Recorded | undefined,
): Promise<void> {
  for (const stage of selected) {
    if (isPublish(stage)) {
      await publish(release, of, { version, recorded: recorded! });
      clearState(release.root, of.name);
      release.out(version);

      continue;
    }

    await stage.run(release, version);
    recorded?.record((state) => ({
      ...state,
      stages: {
        ...state.stages,
        [stage.name]: {
          at: new Date().toISOString(),
          outputs: sums(release, stage, version),
        },
      },
    }));
  }
}

/**
 * A run that goes on from `state`: what is left of it under the options,
 * past the guards, the version commit a killed run left settled, then the
 * stages left and what is left of publish.
 */
async function continued(
  release: Release,
  found: FoundPackage,
  of: ReleasePackage,
  state: ReleaseState,
  stages: readonly string[],
  options: ReleaseOptions,
  machine: { platform: string; arch: string },
  wanted: string | undefined,
): Promise<void> {
  const list = found.steps.release;
  const plan = left(state, {
    stages: list.map((stage) => stage.name),
    selected: stages,
    named: options.only !== undefined || options.from !== undefined,
    dryRun: options.dryRun ?? false,
    bump: wanted,
    channel: options.channel,
    npm: of.publish.npm,
    githubRelease: of.publish.githubRelease === true,
  });

  onMachine(list, plan.stages, machine);

  const commit = versionCommit(release, of, state);
  const at = head(release);
  // The state as the guards judge it: a pending version commit found made
  // is made, and the stages build from it.
  const settled: ReleaseState =
    commit.at === 'made'
      ? {
          ...state,
          versionCommit: { state: 'made', sha: commit.sha },
          built: commit.sha,
        }
      : state;
  // Nothing of the release is out yet: --from its first stage may build
  // again from HEAD, after a merge, say.
  const rebuild =
    options.from === list[0]?.name &&
    settled.versionCommit?.state !== 'pushed' &&
    Object.keys(state.npm).length === 0 &&
    state.tag === undefined;

  guarded(release, of, settled, {
    built: settled.built,
    building: plan.stages.length > 0,
    publishing: plan.publish !== undefined,
    kept: list
      .map((stage) => stage.name)
      .filter(
        (stage) => stage in state.stages && !plan.cleared.includes(stage),
      ),
    rebuild,
  });

  if (plan.publish?.draft === true) {
    ghReady(release);
  }

  await found.steps.preflight?.(release, state.version);
  authenticate(release);

  const selected = list.filter(
    (stage) =>
      plan.stages.includes(stage.name) ||
      (isPublish(stage) && plan.publish !== undefined),
  );

  for (const ready of new Set(
    selected.flatMap((stage) => (isPublish(stage) ? [] : (stage.ready ?? []))),
  )) {
    await ready(release);
  }

  const recorded = record(release, state);

  if (commit.at === 'base') {
    commitVersion(release, of, state.version, (files) =>
      recorded.record((now) => ({
        ...now,
        versionCommit: { state: 'pending', files },
      })),
    );
  }

  if (commit.at !== 'none') {
    const sha = commit.at === 'made' ? commit.sha : head(release);

    recorded.record((now) => ({
      ...now,
      versionCommit: { state: 'made', sha },
      built: sha,
    }));
  }

  if (rebuild && at !== settled.built) {
    recorded.record((now) => ({ ...now, built: at }));
  }

  const made = recorded.state().versionCommit;

  if (plan.publish !== undefined && made?.state === 'made') {
    pushVersion(release, of, state.version);
    recorded.record((now) => ({
      ...now,
      versionCommit: { state: 'pushed', sha: made.sha! },
    }));
  }

  if (plan.cleared.length > 0) {
    recorded.record((now) => cleared(now, plan.cleared));
  }

  await ran(release, of, selected, state.version, recorded);
}

/**
 * A stage that needs another machine (chord's signing: this Mac's keychain
 * and Rosetta) is refused at once anywhere else, only when it runs.
 */
function onMachine(
  list: readonly (Stage | Publish)[],
  names: readonly string[],
  machine: { platform: string; arch: string },
): void {
  for (const stage of list) {
    if (
      isPublish(stage) ||
      !names.includes(stage.name) ||
      stage.machine === undefined ||
      (machine.platform === stage.machine.platform &&
        machine.arch === stage.machine.arch)
    ) {
      continue;
    }

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

/** HEAD's sha. */
function head(release: Release): string {
  const at = run(release, 'git', ['rev-parse', 'HEAD']);

  if (at.status !== 0) {
    die(`git rev-parse HEAD failed: ${said(at.stderr)}`);
  }

  return said(at.stdout);
}

/** A state written now, then again at every change recorded. */
function record(release: Release, first: ReleaseState): Recorded {
  let state = first;

  writeState(release.root, state);

  return {
    state: () => state,
    record: (change) => {
      state = change(state);

      writeState(release.root, state);
    },
  };
}

/**
 * The sha256 of what `stage` left for later ones, by path from the root;
 * an output it names and did not leave stops the release.
 */
function sums(
  release: Release,
  stage: Stage,
  version: string,
): Record<string, string> {
  return Object.fromEntries(
    (stage.outputs?.(release, version) ?? []).map((path) => {
      const file = join(release.root, path);

      if (!existsSync(file)) {
        die(`${stage.name} did not leave ${path}`);
      }

      return [path, sha256(file)];
    }),
  );
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

/** What the release reads of a found package: its name, folder and publish data. */
function releasePackage(found: FoundPackage): ReleasePackage {
  return {
    name: found.name,
    folder: found.folder,
    publish: found.steps.release.find(isPublish)!,
  };
}
