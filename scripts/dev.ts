/**
 * chord's own tooling as one command, run from the tree:
 *
 *   bun dev <command>   see `bun dev --help`
 */
import { Command, EnumType, ValidationError } from '@cliffy/command';
import process from 'node:process';
import type { CompileOptions } from './dev/compile.ts';
import type { MemoryOptions } from './dev/memory.ts';
import { PACKAGES } from './dev/release/lib.ts';
import {
  type ReleaseOptions,
  selectStages,
  type Stage,
  STAGES,
} from './dev/release/select.ts';
import { BUMPS, isVersionArgument } from './dev/release/version.ts';

/**
 * What each command does once its arguments are parsed. Apart from the
 * declarations, so a test parses argv through the very tree `bun dev`
 * runs on with nothing run; each module is imported only when its command
 * runs, so parsing loads none of them.
 */
export interface DevActions {
  compile(options: CompileOptions): void | Promise<void>;
  npm(): void | Promise<void>;
  registry(): void | Promise<void>;
  mark(): void | Promise<void>;
  screenshots(names: readonly string[]): void | Promise<void>;
  memory(options: MemoryOptions): void | Promise<void>;
  selftest(binary: string, arch: string | undefined): void | Promise<void>;
  release(
    stages: readonly Stage[],
    options: ReleaseOptions,
    version: string | undefined,
  ): void | Promise<void>;
  chord(fake: boolean, args: readonly string[]): void | Promise<void>;
  /** Makes `dir`, a capture's directory for `chord --qa`, afresh. */
  qa(dir: string): void | Promise<void>;
  test(args: readonly string[]): void | Promise<void>;
  check(options: { static: boolean }): void | Promise<void>;
  fmt(): void | Promise<void>;
  lint(args: readonly string[]): void | Promise<void>;
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

const RUN: DevActions = {
  compile: async (options) =>
    (await import('./dev/compile.ts')).compile(options),
  npm: async () => (await import('./dev/npm.ts')).npm(),
  registry: async () => (await import('./dev/registry.ts')).registry(),
  mark: async () => (await import('./dev/mark.ts')).mark(),
  screenshots: async (names) =>
    (await import('./dev/screenshots.ts')).screenshots(names),
  memory: async (options) => (await import('./dev/memory.ts')).memory(options),
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
  chord: async (fake, args) => {
    process.exitCode = (await import('./dev/tools.ts')).chord(fake, args);
  },
  qa: async (dir) => (await import('./dev/tools.ts')).qaPlace(dir),
  test: async (args) => {
    process.exitCode = (await import('./dev/tools.ts')).test(args);
  },
  check: async (options) => {
    process.exitCode = (await import('./dev/tools.ts')).check(options);
  },
  fmt: async () => {
    process.exitCode = (await import('./dev/tools.ts')).fmt();
  },
  lint: async (args) => {
    process.exitCode = (await import('./dev/tools.ts')).lint(args);
  },
};

const RELEASE = `The release, on the owner's arm64 Mac. With no options it runs every stage in order, step for step as scripts/release.sh did, and the last line it prints is the published version. Preflight runs on every run, whatever is skipped. If a run stopped between publishes, the next run resumes it: it publishes what is missing from the tarballs already packed and builds nothing. The publish stage hands the terminal to npm, which asks you to authorise each publish (press Enter, then approve in the browser), and the CLI waits for as long as that takes.

The version is package.json's, or the one given: package.json's own, an exact version above it, or major, minor, patch or fix (patch) to bump it. Pre-releases are refused, and a new version needs the compile stage. Given a new one, the release checks it, writes it into package.json and commits that alone as "chore: chord v<version>" before any stage. A run that publishes pushes the commit to origin's main first, and it stays there if a later stage fails: rerun with no version, or that one. If the push fails, the commit is dropped and the release stops. A dry run, or a run without publish, drops the commit at the end and pushes nothing. Until the commit is pushed or dropped, Ctrl+C, SIGTERM and SIGHUP drop it too; a run killed otherwise may leave it, to be dropped with git reset --keep HEAD~1. A stopped publish resumes only package.json's version.

Stages:
  install    bun install --frozen-lockfile
  check      bun dev check
  natives    every platform's packages installed; the macOS native libraries signed
  compile    bun dev compile --all; each binary's kind checked with file(1)
  sign       both macOS binaries signed, verified and their entitlements compared
  selftest   each macOS binary run on the fake agent, the window in tmux (the x64 one under Rosetta)
  notarise   one zip submitted to Apple; each binary's cdhash found in Apple's log
  pack       the five packages laid out and packed, their sha256 recorded, the tarballs installed and checked
  publish    the four platform packages, a wait until npm answers for each, then @chorded/chord, then the tag`;

/** `bun dev`'s commands, declared, each running through `actions`. */
export function devCommand(actions: DevActions = RUN) {
  return (
    new Command()
      .name('bun dev')
      .description("chord's build, release and maintenance tools.")
      .action(function () {
        this.showHelp();
      })
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
              return actions.chord(fake, given);
            }

            const dir = qaDir(qa);

            await actions.qa(dir);

            return actions.chord(fake, ['-C', dir, ...given]);
          }),
      )
      .command(
        'test',
        new Command()
          .description(
            "Run the whole suite with bun test, a worker per core, on the timings in tests/timings.json; the rest of the arguments are bun test's, an empty one only after --. With no arguments, as bun dev check and CI run it, it measures each file again into tests/timings.measured.json and fails, naming them, on a file over 90 s, one slower than the record by 35% and 20 s (a faster one never fails), one unrecorded or one gone; any argument leaves the timings unchecked. --update-timings rewrites tests/timings.json, held to the 90 s only: rerun with it after a file is added, split or changes its time, and commit the record.",
          )
          .arguments('[args...:string]')
          .stopEarly()
          .example('the timings rewritten', 'bun dev test --update-timings')
          .example('only the uncommitted changes', 'bun dev test --changed')
          .example('an empty pattern, after --', "bun dev test -- -t ''")
          .action(function (_options, ...args) {
            return actions.test([...args, ...this.getLiteralArgs()]);
          }),
      )
      .command(
        'check',
        new Command()
          .description(
            "The full validation: tsc, ESLint, Prettier and lint/'s own test, then the whole suite. It stops at the first step that fails, with that step's exit status.",
          )
          .option(
            '--static',
            "Only tsc, ESLint, Prettier and lint/'s own test, not the suite.",
            { default: false },
          )
          .action((options) => actions.check(options)),
      )
      .command(
        'fmt',
        new Command()
          .description("Lay the tree out with Prettier's --write.")
          .action(() => actions.fmt()),
      )
      .command(
        'lint',
        new Command()
          .description(
            "Run ESLint over the tree; the rest of the arguments are ESLint's, an empty one only after --.",
          )
          .arguments('[args...:string]')
          .stopEarly()
          .example('what ESLint can fix, fixed', 'bun dev lint --fix')
          .action(function (_options, ...args) {
            return actions.lint([...args, ...this.getLiteralArgs()]);
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
            '--package <name:package>',
            'Publish only this package: chord-darwin-arm64, chord-darwin-x64, chord-linux-arm64, chord-linux-x64 or chord.',
            { conflicts: ['dry-run'] },
          )
          .example('the whole release', 'bun dev release')
          .example('the next minor version', 'bun dev release minor')
          .example('an exact version', 'bun dev release 1.0.0')
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
  await devCommand().parse(process.argv.slice(2));
}
