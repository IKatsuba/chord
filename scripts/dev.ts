/**
 * chord's own tooling as one command, run from the tree:
 *
 *   bun dev <command>   see `bun dev --help`
 */
import { Command, EnumType, ValidationError } from '@cliffy/command';
import process from 'node:process';
import { fileURLToPath } from 'node:url';
import type { CompileOptions } from './dev/compile.ts';
import type { MemoryOptions } from './dev/memory.ts';
import { packages as findPackages, StepsError } from './dev/steps.ts';
import { PACKAGES } from './dev/release/lib.ts';
import {
  BUMPS,
  isVersionArgument,
  type ReleaseOptions,
  selectStages,
  type Stage,
  STAGES,
} from './dev/release/select.ts';

/**
 * What each command does once its arguments are parsed. Apart from the
 * declarations, so a test parses argv through the very tree `bun dev`
 * runs on with nothing run; each module is imported only when its command
 * runs, so parsing loads none of them.
 */
export interface DevActions {
  /** `name`'s checks from its steps.ts, only the static ones if `only`. */
  quality(name: string, only: boolean): void | Promise<void>;
  /** ESLint with `name`'s argv, `args` after it. */
  lint(name: string, args: readonly string[]): void | Promise<void>;
  compile(options: CompileOptions): void | Promise<void>;
  npm(): void | Promise<void>;
  registry(): void | Promise<void>;
  mark(): void | Promise<void>;
  screenshots(names: readonly string[]): void | Promise<void>;
  social(): void | Promise<void>;
  memory(options: MemoryOptions): void | Promise<void>;
  /** The owner's live check of riff's model list for `plan`. */
  riffModels(plan: 'codex' | 'grok', out: string): void | Promise<void>;
  selftest(binary: string, arch: string | undefined): void | Promise<void>;
  release(
    stages: readonly Stage[],
    options: ReleaseOptions,
    version: string | undefined,
  ): void | Promise<void>;
  /** `state` holds chord's state in place of the person's (CHD-616). */
  chord(
    fake: boolean,
    args: readonly string[],
    fixtureResources?: boolean,
    state?: string,
  ): void | Promise<void>;
  /**
   * chord on riff and its fake provider, `args` chord's after the agent:
   * `bun dev chord --fake riff`.
   */
  riff(
    args: readonly string[],
    qa?: boolean,
    state?: string,
  ): void | Promise<void>;
  /** Makes `dir` and `state`, a capture's places for `chord --qa`, afresh. */
  qa(dir: string, state: string): void | Promise<void>;
  test(args: readonly string[]): void | Promise<void>;
}

/**
 * Where `chord --qa [name]` runs: a fixed place under /tmp, named by the
 * capture, never the per-user temp directory, whose path names the machine
 * (CHD-427); `/tmp/chord-qa` for a bare `--qa`, which the parser gives as
 * `true`. A name that is not a plain word is refused.
 */
export function qaDir(name: string | true): string {
  if (name === true) {
    return '/tmp/chord-qa';
  }

  if (!/^[A-Za-z0-9._-]+$/.test(name) || /^\.+$/.test(name)) {
    throw new ValidationError(
      `--qa takes letters, digits, . _ and -, not ${JSON.stringify(name)}`,
    );
  }

  return `/tmp/chord-qa.${name}`;
}

/**
 * Where a `--qa` run keeps chord's state: beside its directory, made afresh
 * with it, never the person's own; not in it, where the @ file picker would
 * list it in captures (CHD-616).
 */
export function qaState(dir: string): string {
  return `${dir}.state`;
}

/**
 * Where a `--fake` run without `--qa` keeps chord's state: one fixed place,
 * kept from run to run, never the person's own (CHD-616).
 */
export const FAKE_STATE = '/tmp/chord-fake';

// The checkout this file is in, every package's steps run from.
const ROOT = fileURLToPath(new URL('..', import.meta.url));

/** The found package `name`: Cliffy's enum lets no other through. */
async function found(name: string) {
  const all = await findPackages(ROOT);

  return all.find((each) => each.name === name)!;
}

const RUN: DevActions = {
  quality: async (name, only) => {
    const { run, stepContext } = await import('./dev/steps.ts');

    process.exitCode = await run(await found(name), stepContext(ROOT), {
      static: only,
    });
  },
  lint: async (name, args) => {
    const { lint, stepContext } = await import('./dev/steps.ts');

    process.exitCode = await lint(await found(name), args, stepContext(ROOT));
  },
  compile: async (options) =>
    (await import('./dev/compile.ts')).compile(options),
  npm: async () => (await import('./dev/npm.ts')).npm(),
  registry: async () => (await import('./dev/registry.ts')).registry(),
  mark: async () => (await import('./dev/mark.ts')).mark(),
  screenshots: async (names) =>
    (await import('./dev/screenshots.ts')).screenshots(names),
  social: async () => (await import('./dev/social.ts')).social(),
  memory: async (options) => (await import('./dev/memory.ts')).memory(options),
  riffModels: async (plan, out) => {
    const { riffModels } = await import('./dev/riff_models.ts');
    const { systemSecrets } = await import('../src/platform/secrets.ts');
    const { libfxBackend } = await import('../src/platform/libfx.ts');
    const { chordStateDir } = await import('../src/session/state_dir.ts');

    await riffModels({
      plan,
      // The owner's own sign-in: this command is never run by a test.
      secrets: systemSecrets(),
      fetch: globalThis.fetch,
      backend: await libfxBackend(),
      stateDir: chordStateDir(),
      out,
      say: (line) => process.stdout.write(`${line}\n`),
    });
  },
  selftest: async (binary, arch) => {
    const { dying, release } = await import('./dev/release/lib.ts');
    const { selftest } = await import('./dev/release/selftest.ts');

    await dying(() => selftest(release(), binary, arch));
  },
  release: async (stages, options, version) => {
    const { dying, release } = await import('./dev/release/lib.ts');
    const { runRelease } = await import('./dev/release/stages.ts');

    await dying(() => runRelease(release(), stages, options, process, version));
  },
  chord: async (fake, args, fixtureResources, state) => {
    const tools = await import('./dev/tools.ts');

    process.exitCode =
      fake || fixtureResources === true
        ? await tools.chordWithRiff(
            fake,
            args,
            fixtureResources,
            undefined,
            undefined,
            state,
          )
        : tools.chord(fake, args, undefined, fixtureResources);
  },
  riff: async (args, qa, state) => {
    process.exitCode = await (
      await import('./dev/tools.ts')
    ).chordOnRiff(args, undefined, undefined, qa, state);
  },
  qa: async (dir, state) =>
    (await import('./dev/tools.ts')).qaPlace(dir, state),
  test: async (args) => {
    process.exitCode = (await import('./dev/tools.ts')).test(args);
  },
};

const RELEASE = `The release, on the owner's arm64 Mac. With no options it runs every stage in order, step for step as scripts/release.sh did, and the last line it prints is the published version. Preflight runs on every run, whatever is skipped. After all eligibility guards, mandatory npm authentication runs for every invocation, including dry runs and runs without publish. A successful npm whoami continues without needing a terminal. If it fails, stdin and stdout must be terminals: the release runs plain npm login once with inherited stdio, then rechecks npm whoami. npm may open a browser and save credentials or registry settings, including during a dry run. Failed, cancelled or signal-terminated login, or a failed recheck, stops before release work. Stage selection cannot skip authentication. If a run stopped between publishes, the next run resumes it: it publishes what is missing from the tarballs already packed and builds nothing. The publish stage hands the terminal to npm, which asks you to authorise each publish (press Enter, then approve in the browser), and the CLI waits for as long as that takes.

The version is package.json's, or the one given: package.json's own, an exact version above it, or major, minor, patch or fix (patch) to bump it. A version with a pre-release label cannot be given, and a new version needs the compile stage. Given a new one, the release checks it, writes it into package.json and commits that alone as "chore: chord v<version>" before any stage. A run that publishes pushes the commit to origin's main first, and it stays there if a later stage fails: rerun with no version, or that one. If the push fails, the commit is dropped and the release stops. A dry run, or a run without publish, drops the commit at the end and pushes nothing. Until the commit is pushed or dropped, Ctrl+C, SIGTERM and SIGHUP drop it too; a run killed otherwise may leave it, to be dropped with git reset --keep HEAD~1. A stopped publish resumes only package.json's version.

--channel <name> releases a pre-release on that channel: <x.y.z>-<name>.<n>. A bump counts from npm's latest stable version, and an exact version is taken as written; if package.json already holds that channel's pre-release of it, n goes up by one, otherwise it starts at 0. So from 0.67.0, major --channel next gives 1.0.0-next.0, and the same command again 1.0.0-next.1. With no version, --channel finishes package.json's version if it is that channel's. The channel is the version's label, and the rest follows from the version whether or not --channel is given: a publishing run needs the branch named after the channel, level with its origin, and pushes there instead of main. Every package is published with --tag <name>, so npm's latest does not move, and the draft GitHub release is marked a pre-release. A dry run on a channel also prints the stages it ran and each package's npm publish arguments, in publish order. A stable version publishes only from main.

Stages:
  install    bun install --frozen-lockfile
  check      bun dev quality chord
  natives    every platform's packages installed; the macOS native libraries signed
  compile    bun dev compile --all; each binary's kind checked with file(1)
  sign       both macOS binaries signed, verified and their entitlements compared
  selftest   each macOS binary run on the fake agent, the window in tmux (the x64 one under Rosetta)
  notarise   one zip submitted to Apple; each binary's cdhash found in Apple's log
  pack       the five packages laid out and packed, their sha256 recorded, the tarballs installed and checked
  publish    the four platform packages, a wait until npm answers for each, then @chorded/chord, then the tag`;

/** What `bun dev` knows of a package: its name, for `<package>`. */
export interface DevPackage {
  readonly name: string;
}

/**
 * `bun dev`'s commands, declared, each running through `actions`; a
 * command that takes `<package>` takes one of `packages`.
 */
export function devCommand(
  actions: DevActions = RUN,
  packages: readonly DevPackage[] = [{ name: 'chord' }],
) {
  const names = packages.map((each) => each.name);

  return (
    new Command()
      .name('bun dev')
      .description(
        `chord's build, release and maintenance tools. A command that takes <package> runs that package's steps from its steps.ts and nothing else: ${names.join(' or ')}, its npm name without the scope.`,
      )
      .action(function () {
        this.showHelp();
      })
      .command(
        'quality',
        new Command()
          .description(
            "A package's checks in its steps.ts's order, stopping at the first that fails.",
          )
          .type('package', new EnumType(names))
          .arguments('<package:package>')
          .option('--static', 'Only the checks marked static.', {
            default: false,
          })
          .example("chord's static checks", 'bun dev quality chord --static')
          .action(({ static: only }, name) => actions.quality(name, only)),
      )
      .command(
        'lint',
        new Command()
          .description(
            "ESLint with a package's config over its files; the rest of the arguments are ESLint's, an empty one only after --.",
          )
          .type('package', new EnumType(names))
          .arguments('<package:package> [args...:string]')
          .stopEarly()
          .example('what ESLint can fix, fixed', 'bun dev lint chord --fix')
          .action(function (_options, name, ...args) {
            return actions.lint(name, [...args, ...this.getLiteralArgs()]);
          }),
      )
      .command(
        'chord',
        new Command()
          .description(
            "Run chord from source with React's production build; the rest of the arguments are chord's, an empty one only after --.",
          )
          .option(
            '--fake',
            "On the fake agent in tests/fixtures/fake_agent/ instead of a real one; with riff as the agent, riff on its tests' fake provider.",
            { default: false },
          )
          .option(
            '--qa [name:string]',
            "In /tmp/chord-qa.<name>, made afresh, as its directory: a capture's neutral place, never the per-user temp one (letters, digits, . _ -); with no name, /tmp/chord-qa. An empty name, as --qa '' or --qa=, is dropped by the parser: chord then runs where it is, as with no --qa.",
          )
          .arguments('[args...:string]')
          // Everything from chord's first word or option on is chord's.
          .stopEarly()
          .example('an agent', 'bun dev chord codex')
          .example('the fake agent, one prompt', 'bun dev chord --fake -p hi')
          .example(
            'riff on its fake provider, a read by the prompt',
            'bun dev chord --fake riff',
          )
          .example("chord's own help", 'bun dev chord -- --help')
          .example(
            'a capture of the fake, in /tmp/chord-qa.tabs',
            'bun dev chord --qa tabs --fake',
          )
          .action(async function ({ fake, qa }, ...args) {
            const given = [...args, ...this.getLiteralArgs()];
            // riff has no agent command to stand in for: it runs as itself,
            // on a fake provider in place of a plan.
            const riff = fake && given[0] === 'riff';

            if (qa === undefined) {
              return riff
                ? actions.riff(given.slice(1), false, FAKE_STATE)
                : fake
                  ? actions.chord(fake, given, undefined, FAKE_STATE)
                  : actions.chord(fake, given);
            }

            const dir = qaDir(qa);

            await actions.qa(dir, qaState(dir));

            return riff
              ? actions.riff(['-C', dir, ...given.slice(1)], true, qaState(dir))
              : actions.chord(fake, ['-C', dir, ...given], true, qaState(dir));
          }),
      )
      .command(
        'test',
        new Command()
          .description(
            "Run the whole suite with bun test, a worker per core, the slowest files first by the times in tests/timings.json; the rest of the arguments are bun test's, an empty one only after --. Its status is the tests'.",
          )
          .arguments('[args...:string]')
          .stopEarly()
          .example('only the uncommitted changes', 'bun dev test --changed')
          .example('an empty pattern, after --', "bun dev test -- -t ''")
          .action(function (_options, ...args) {
            return actions.test([...args, ...this.getLiteralArgs()]);
          }),
      )
      .command(
        'compile',
        new Command()
          .description(
            "Compile chord with bun build --compile: this machine's binary into dist/<target>/chord.",
          )
          .option('--all', 'Every release target in scripts/targets.ts.', {
            default: false,
          })
          .option('--install', 'Into ~/.local/bin/chord instead of dist/.', {
            default: false,
          })
          .action(({ all, install }) => actions.compile({ all, install })),
      )
      .command(
        'npm',
        new Command()
          .description('Lay out npm/ from the binaries in dist/.')
          .action(() => actions.npm()),
      )
      .command(
        'registry',
        new Command()
          .description('Refetch the ACP Registry into src/registry.ts.')
          .action(() => actions.registry()),
      )
      .command(
        'mark',
        new Command()
          .description('Rasterise scripts/mark.svg into src/ui/header/mark.ts.')
          .action(() => actions.mark()),
      )
      .command(
        'screenshots',
        new Command()
          .description(
            'Retake docs/images/ from chord on the fake agent, or only the shots named.',
          )
          .arguments('[names...:string]')
          .action((_options, ...names) => actions.screenshots(names)),
      )
      .command(
        'riff-models',
        new Command()
          .description(
            "The owner's live check of riff's model list: one turn of 'Reply with the word ok.' on the stored ChatGPT (codex) or Grok (grok) sign-in, as chord riff made it, printing each model the plan's endpoint lists, with its context window and reasoning levels, as libfx's engine fetched them. It spends the plan; never run by a test.",
          )
          .type('plan', new EnumType(['codex', 'grok']))
          .arguments('<plan:plan>')
          .option(
            '--out <file:string>',
            'Where the raw responses are written.',
            {
              default: 'dist/riff-models-<plan>.json',
            },
          )
          .example('ChatGPT', 'bun dev riff-models codex')
          .action(({ out }, plan) =>
            actions.riffModels(
              plan as 'codex' | 'grok',
              out.replace('<plan>', plan),
            ),
          ),
      )
      .command(
        'social',
        new Command()
          .description(
            "Lay out GitHub's social preview from docs/images into dist/social-preview.png.",
          )
          .action(() => actions.social()),
      )
      .command(
        'memory',
        new Command()
          .description(
            "The long-run memory check: chord's window on the fake agent's soak, its memory sampled and its heap compared.",
          )
          .option('--minutes <minutes:number>', 'How long the run lasts.', {
            default: 10,
          })
          .option(
            '--sample-seconds <seconds:number>',
            'Seconds between samples.',
            { default: 10 },
          )
          .option(
            '--snapshots <count:number>',
            'Heap snapshots over the run, at least 2.',
            { default: 4 },
          )
          .option(
            '--step-ms <ms:number>',
            "The fake agent's delay between streamed steps.",
            { default: 5 },
          )
          .option('--binary <path:string>', 'Run this binary, not the source.')
          .option('--development', "React's development build, from source.", {
            default: false,
          })
          .action((options) => actions.memory(options)),
      )
      .command(
        'selftest',
        new Command()
          .description(
            "What the release's self-test does: --version must say package.json's version, -p must answer, and the window must open, answer a prompt and read the clipboard in a tmux of its own.",
          )
          .arguments('<binary:string>')
          .option(
            '--arch <arch:string>',
            'Run it all under `arch -<arch>` (x86_64: Rosetta).',
          )
          .example(
            'The x64 binary under Rosetta',
            'bun dev selftest dist/bun-darwin-x64/chord --arch x86_64',
          )
          .action(({ arch }, binary) => actions.selftest(binary, arch)),
      )
      .command(
        'release',
        new Command()
          .description(RELEASE)
          .type('stage', new EnumType(STAGES))
          .type('package', new EnumType(PACKAGES))
          .type('version', ({ value }) => {
            if (!isVersionArgument(value)) {
              throw new ValidationError(
                `"${value}" is neither an exact version (1.2.3) nor one of ${BUMPS.join(', ')}.`,
              );
            }

            return value;
          })
          .arguments('[version:version]')
          .option(
            '--dry-run',
            'Every stage but publish, so it still submits to Apple. It never resumes a stopped publish.',
          )
          .option(
            '--skip <stages:stage[]>',
            'Leave these stages out (comma-separated). Any stage may be skipped, check and install included.',
          )
          .option(
            '--only <stages:stage[]>',
            'Run only these stages (comma-separated).',
            { conflicts: ['skip', 'from', 'to'] },
          )
          .option('--from <stage:stage>', 'Start at this stage.')
          .option('--to <stage:stage>', 'Stop after this stage.')
          .option(
            '--channel <name:string>',
            'Release a pre-release on this channel, from the branch of that name.',
          )
          .option(
            '--package <name:package>',
            'Publish only this package: chord-darwin-arm64, chord-darwin-x64, chord-linux-arm64, chord-linux-x64 or chord.',
            { conflicts: ['dry-run'] },
          )
          .example('the whole release', 'bun dev release')
          .example('the next minor version', 'bun dev release minor')
          .example('an exact version', 'bun dev release 1.0.0')
          .example(
            "the next pre-release on a channel, from that channel's branch",
            'bun dev release major --channel next',
          )
          .example(
            'a pre-release of an exact version',
            'bun dev release 1.0.0 --channel next',
          )
          .example(
            'a dry run of the next patch, package.json as it was after',
            'bun dev release patch --dry-run --skip notarise',
          )
          .example('everything up to npm publish', 'bun dev release --dry-run')
          .example(
            'no Apple submission',
            'bun dev release --dry-run --skip notarise',
          )
          .example(
            'without the checks and tests',
            'bun dev release --skip install,check',
          )
          .example(
            "publish a dry run's tarballs",
            'bun dev release --only publish',
          )
          .example(
            'rerun from the self-test',
            'bun dev release --from selftest',
          )
          .example(
            'one package',
            'bun dev release --only publish --package chord-linux-x64',
          )
          .action((options, version) =>
            actions.release(selectStages(options), options, version),
          ),
      )
      // Back to the root, so what a caller chains on applies to the whole tree.
      .reset()
  );
}

if (import.meta.main) {
  try {
    // Every steps file, read before the tree it shapes: a broken one stops
    // every command, naming it.
    const packages = await findPackages(ROOT);

    await devCommand(RUN, packages).parse(process.argv.slice(2));
  } catch (error) {
    if (!(error instanceof StepsError)) {
      throw error;
    }

    process.stderr.write(`bun dev: ${error.message}\n`);
    process.exit(1);
  }
}
