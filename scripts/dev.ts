/**
 * The workspace's TypeScript tooling as one command, run from the tree:
 *
 *   bun dev <command>   see `bun dev --help`
 */
import { Command, EnumType, ValidationError } from '@cliffy/command';
import process from 'node:process';
import { fileURLToPath } from 'node:url';
import { packages as findPackages, StepsError } from './dev/steps.ts';
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
  /** Releases `name`'s `stages`, at `bump` if given. */
  release(
    name: string,
    stages: readonly string[],
    options: ReleaseOptions,
    bump: string | undefined,
  ): void | Promise<void>;
  /** A run that cannot say what to do: `line` on stderr, status 1. */
  unclear(line: string): void | Promise<void>;
}

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
};

const RELEASE = `The release of one package by its steps.ts; chord's runs on the owner's arm64 Mac. With no options it runs every stage of the package in order, and the last line it prints is the published version. With no package it releases nothing. Preflight runs on every run, whatever is skipped. After all eligibility guards, mandatory npm authentication runs for every invocation, including dry runs and runs without publish. A successful npm whoami continues without needing a terminal. If it fails, stdin and stdout must be terminals: the release runs plain npm login once with inherited stdio, then rechecks npm whoami. npm may open a browser and save credentials or registry settings, including during a dry run. Failed, cancelled or signal-terminated login, or a failed recheck, stops before release work. Stage selection cannot skip authentication. A run that publishes, or one at package.json's version, keeps the release's state in .release/<package>/state.json as it goes: each stage done with the sha256 of what it left, each npm name, the tag and the draft. A stopped release goes on from it: the next run does what is left, past guards that refuse a changed tree, a moved HEAD while a stage before publish is left, a changed output, or an npm version or tag the release did not make. Every refusal a state causes names rm -r .release/<package>, which abandons it. The state is removed once everything is done. The publish stage hands the terminal to npm, which asks you to authorise each publish (press Enter, then approve in the browser), and the CLI waits for as long as that takes.

The version is the package's package.json's, or --bump's: package.json's own, an exact version above it, or major, minor, patch or fix (patch) to bump it. A version with a pre-release label cannot be given, and a new version needs the stage that puts it into what is published (chord's compile). Given a new one, the release checks it, writes it into the package's package.json and commits that alone as "chore: <package> v<version>" before any stage. A run that publishes pushes the commit to origin's main first, and its state keeps it if the push or a later stage fails: rerun without --bump. A dry run, or a run without publish that makes a new version, keeps no state and drops the commit at the end, pushing nothing; until then Ctrl+C, SIGTERM and SIGHUP drop it too, and a run killed otherwise may leave it, to be dropped with git reset --keep HEAD~1. --bump is refused while the package's state is unfinished, and so is --dry-run. Publish needs pack done, in this run or the state.

--channel <name> releases a pre-release on that channel: <x.y.z>-<name>.<n>. A bump counts from npm's latest stable version, and an exact version is taken as written; if package.json already holds that channel's pre-release of it, n goes up by one, otherwise it starts at 0. So from 0.67.0, --bump major --channel next gives 1.0.0-next.0, and the same command again 1.0.0-next.1. Without --bump, --channel finishes package.json's version if it is that channel's. The channel is the version's label, and the rest follows from the version whether or not --channel is given: a publishing run needs the branch named after the channel, level with its origin, and pushes there instead of main. Every package is published with --tag <name>, so npm's latest does not move, and the draft GitHub release is marked a pre-release. A dry run on a channel also prints the stages it ran and each package's npm publish arguments, in publish order. A stable version publishes only from main.`;

/** What `bun dev` knows of a package: its name and its stages' names. */
export interface DevPackage {
  readonly name: string;
  readonly stages: readonly string[];
}

/**
 * `bun dev`'s commands, declared, each running through `actions`; a
 * command that takes `<package>` takes one of `packages`.
 */
export function devCommand(
  actions: DevActions,
  packages: readonly DevPackage[],
) {
  const names = packages.map((each) => each.name);
  const stageNames = packages.flatMap((each) => each.stages);
  const width = Math.max(...names.map((name) => name.length));

  return (
    new Command()
      .name('bun dev')
      .description(
        `The workspace's TypeScript tooling: quality, lint and release. A command that takes <package> runs that package's steps from its steps.ts and nothing else: ${names.join(' or ')}, its npm name without the scope.`,
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
          .example(
            "cursor-cloud-acp's static checks",
            'bun dev quality cursor-cloud-acp --static',
          )
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
          .example(
            'what ESLint can fix, fixed',
            'bun dev lint cursor-cloud-acp --fix',
          )
          .action(function (_options, name, ...args) {
            return actions.lint(name, [...args, ...this.getLiteralArgs()]);
          }),
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
          .example('the whole release', 'bun dev release cursor-cloud-acp')
          .example(
            'the next minor version',
            'bun dev release cursor-cloud-acp --bump minor',
          )
          .example(
            'an exact version',
            'bun dev release cursor-cloud-acp --bump 1.0.0',
          )
          .example(
            "the next pre-release on a channel, from that channel's branch",
            'bun dev release cursor-cloud-acp --bump major --channel next',
          )
          .example(
            'a dry run of the next patch, package.json as it was after',
            'bun dev release cursor-cloud-acp --bump patch --dry-run',
          )
          .example(
            'without the checks and tests',
            'bun dev release cursor-cloud-acp --skip install,quality',
          )
          .example(
            'rerun from the build',
            'bun dev release cursor-cloud-acp --from build',
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
