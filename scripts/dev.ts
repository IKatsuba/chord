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
import chordSteps from '../steps.ts';
import {
  BUMPS,
  isVersionArgument,
  type ReleaseOptions,
  selectStages,
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
  selftest(binary: string, arch: string | undefined): void | Promise<void>;
  /** Releases `name`'s `stages`, at `bump` if given. */
  release(
    name: string,
    stages: readonly string[],
    options: ReleaseOptions,
    bump: string | undefined,
  ): void | Promise<void>;
  /** A run that cannot say what to do: `line` on stderr, status 1. */
  unclear(line: string): void | Promise<void>;
  /** `state` holds chord's state in place of the person's (CHD-616). */
  chord(
    fake: boolean,
    args: readonly string[],
    fixtureResources?: boolean,
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
  selftest: async (binary, arch) => {
    const { dying, release } = await import('./dev/release/lib.ts');
    const { selftest } = await import('./dev/release/selftest.ts');

    await dying(() => selftest(release(), binary, arch));
  },
  release: async (name, stages, options, bump) => {
    const { dying, release } = await import('./dev/release/lib.ts');
    const { runRelease } = await import('./dev/release/stages.ts');
    const each = await found(name);

    await dying(() =>
      runRelease(release(), each, stages, options, process, bump),
    );
  },
  unclear: (line) => {
    process.stderr.write(`${line}\n`);

    process.exitCode = 1;
  },
  chord: async (fake, args, fixtureResources, state) => {
    process.exitCode = (await import('./dev/tools.ts')).chord(
      fake,
      args,
      undefined,
      fixtureResources,
      state,
    );
  },
  qa: async (dir, state) =>
    (await import('./dev/tools.ts')).qaPlace(dir, state),
  test: async (args) => {
    process.exitCode = (await import('./dev/tools.ts')).test(args);
  },
};

const RELEASE = `The release of one package by its steps.ts; chord's runs on the owner's arm64 Mac. With no options it runs every stage of the package in order, and the last line it prints is the published version. With no package it releases nothing. Preflight runs on every run, whatever is skipped. After all eligibility guards, mandatory npm authentication runs for every invocation, including dry runs and runs without publish. A successful npm whoami continues without needing a terminal. If it fails, stdin and stdout must be terminals: the release runs plain npm login once with inherited stdio, then rechecks npm whoami. npm may open a browser and save credentials or registry settings, including during a dry run. Failed, cancelled or signal-terminated login, or a failed recheck, stops before release work. Stage selection cannot skip authentication. A run that publishes, or one at package.json's version, keeps the release's state in .release/<package>/state.json as it goes: each stage done with the sha256 of what it left, each npm name, the tag and the draft. A stopped release goes on from it: the next run does what is left, past guards that refuse a changed tree, a moved HEAD while a stage before publish is left, a changed output, or an npm version or tag the release did not make. Every refusal a state causes names rm -r .release/<package>, which abandons it. The state is removed once everything is done. The publish stage hands the terminal to npm, which asks you to authorise each publish (press Enter, then approve in the browser), and the CLI waits for as long as that takes.

The version is the package's package.json's, or --bump's: package.json's own, an exact version above it, or major, minor, patch or fix (patch) to bump it. A version with a pre-release label cannot be given, and a new version needs the stage that puts it into what is published (chord's compile). Given a new one, the release checks it, writes it into the package's package.json and commits that alone as "chore: <package> v<version>" before any stage. A run that publishes pushes the commit to origin's main first, and its state keeps it if the push or a later stage fails: rerun without --bump. A dry run, or a run without publish that makes a new version, keeps no state and drops the commit at the end, pushing nothing; until then Ctrl+C, SIGTERM and SIGHUP drop it too, and a run killed otherwise may leave it, to be dropped with git reset --keep HEAD~1. --bump is refused while the package's state is unfinished, and so is --dry-run. Publish needs pack done, in this run or the state.

--channel <name> releases a pre-release on that channel: <x.y.z>-<name>.<n>. A bump counts from npm's latest stable version, and an exact version is taken as written; if package.json already holds that channel's pre-release of it, n goes up by one, otherwise it starts at 0. So from 0.67.0, --bump major --channel next gives 1.0.0-next.0, and the same command again 1.0.0-next.1. Without --bump, --channel finishes package.json's version if it is that channel's. The channel is the version's label, and the rest follows from the version whether or not --channel is given: a publishing run needs the branch named after the channel, level with its origin, and pushes there instead of main. Every package is published with --tag <name>, so npm's latest does not move, and the draft GitHub release is marked a pre-release. A dry run on a channel also prints the stages it ran and each package's npm publish arguments, in publish order. A stable version publishes only from main.`;

/** What `bun dev` knows of a package: its name and its stages' names. */
export interface DevPackage {
  readonly name: string;
  readonly stages: readonly string[];
}

/** chord's, as its steps.ts lists them: the default tree's one package. */
const CHORD: DevPackage = {
  name: 'chord',
  stages: chordSteps.release.map((stage) => stage.name),
};

/**
 * `bun dev`'s commands, declared, each running through `actions`; a
 * command that takes `<package>` takes one of `packages`.
 */
export function devCommand(
  actions: DevActions = RUN,
  packages: readonly DevPackage[] = [CHORD],
) {
  const names = packages.map((each) => each.name);
  const stageNames = packages.flatMap((each) => each.stages);
  const width = Math.max(...names.map((name) => name.length));

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
            'On the fake agent in tests/fixtures/fake_agent/ instead of a real one.',
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
          .example("chord's own help", 'bun dev chord -- --help')
          .example(
            'a capture of the fake, in /tmp/chord-qa.tabs',
            'bun dev chord --qa tabs --fake',
          )
          .action(async function ({ fake, qa }, ...args) {
            const given = [...args, ...this.getLiteralArgs()];

            if (qa === undefined) {
              return fake
                ? actions.chord(fake, given, undefined, FAKE_STATE)
                : actions.chord(fake, given);
            }

            const dir = qaDir(qa);

            await actions.qa(dir, qaState(dir));

            return actions.chord(
              fake,
              ['-C', dir, ...given],
              true,
              qaState(dir),
            );
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
          .description(
            `${RELEASE}\n\nStages:\n${packages
              .map(
                (each) =>
                  `  ${each.name.padEnd(width)}  ${each.stages.join(', ')}`,
              )
              .join('\n')}`,
          )
          .type('package', new EnumType(names))
          .type('stage', new EnumType([...new Set(stageNames)]))
          .type('bump', ({ value }) => {
            if (!isVersionArgument(value)) {
              throw new ValidationError(
                `"${value}" is neither an exact version (1.2.3) nor one of ${BUMPS.join(', ')}.`,
              );
            }

            return value;
          })
          // Optional, so a bare run reaches the release's own words.
          .arguments('[package:package]')
          .option(
            '--bump <version:bump>',
            "An exact version above the package's package.json, or major, minor, patch or fix.",
          )
          .option(
            '--channel <name:string>',
            'A pre-release on this channel, from the branch of that name.',
          )
          .option(
            '--dry-run',
            "Every stage but publish, so chord's still submits to Apple. Refused while the package's state is unfinished.",
          )
          .option(
            '--skip <stages:stage[]>',
            "Leave these of the package's stages out (comma-separated).",
          )
          .option(
            '--only <stages:stage[]>',
            "Run only these of the package's stages.",
            { conflicts: ['skip', 'from', 'to'] },
          )
          .option('--from <stage:stage>', 'Start at this stage.')
          .option('--to <stage:stage>', 'Stop after this stage.')
          .example('the whole release', 'bun dev release chord')
          .example(
            'the next minor version',
            'bun dev release chord --bump minor',
          )
          .example('an exact version', 'bun dev release chord --bump 1.0.0')
          .example(
            "the next pre-release on a channel, from that channel's branch",
            'bun dev release chord --bump major --channel next',
          )
          .example(
            'a dry run of the next patch, package.json as it was after',
            'bun dev release chord --bump patch --dry-run --skip notarise',
          )
          .example(
            'without the checks and tests',
            'bun dev release chord --skip install,quality',
          )
          .example(
            'rerun from the self-test',
            'bun dev release chord --from selftest',
          )
          .action(({ bump, ...options }, name) => {
            if (name === undefined) {
              return actions.unclear(
                `release: not clear which package to release: bun dev release <package> (${names.join(', ')})`,
              );
            }

            const stages = selectStages(
              packages.find((each) => each.name === name)!,
              options,
            );

            return actions.release(name, stages, options, bump);
          }),
      )
      // Back to the root, so what a caller chains on applies to the whole tree.
      .reset()
  );
}

if (import.meta.main) {
  try {
    // Every steps file, read before the tree it shapes: a broken one stops
    // every command, naming it.
    const packages = (await findPackages(ROOT)).map((each) => ({
      name: each.name,
      stages: each.steps.release.map((stage) => stage.name),
    }));

    await devCommand(RUN, packages).parse(process.argv.slice(2));
  } catch (error) {
    if (!(error instanceof StepsError)) {
      throw error;
    }

    process.stderr.write(`bun dev: ${error.message}\n`);
    process.exit(1);
  }
}
