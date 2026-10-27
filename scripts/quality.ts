/** Quality package scripts, parsed by the same Cliffy commands as before. */
import { Command } from '@cliffy/command';
import process from 'node:process';
import { check, fmt, lint } from './dev/tools.ts';

/** The tool actions, apart from parsing so tests need not run the tools. */
export interface QualityActions {
  check(options: { static: boolean }): void | Promise<void>;
  fmt(): void | Promise<void>;
  lint(args: readonly string[]): void | Promise<void>;
}

const RUN: QualityActions = {
  check: (options) => {
    process.exitCode = check(options);
  },
  fmt: () => {
    process.exitCode = fmt();
  },
  lint: (args) => {
    process.exitCode = lint(args);
  },
};

/** The package scripts' commands, with argv left to Cliffy. */
export function qualityCommand(actions: QualityActions = RUN) {
  return new Command()
    .name('bun run')
    .description("chord's checks, lint and formatting.")
    .action(function () {
      this.showHelp();
    })
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
        .example('what ESLint can fix, fixed', 'bun lint --fix')
        .action(function (_options, ...args) {
          return actions.lint([...args, ...this.getLiteralArgs()]);
        }),
    )
    .reset();
}

if (import.meta.main) {
  await qualityCommand().parse(process.argv.slice(2));
}
