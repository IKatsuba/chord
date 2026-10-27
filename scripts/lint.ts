/** ESLint's package command, retaining the dev command's forwarding boundary. */
import { Command } from '@cliffy/command';
import process from 'node:process';
import { lint } from './dev/tools.ts';

/** Parses the forwarded arguments without rewriting them. */
export function lintCommand(
  run: (args: readonly string[]) => void | Promise<void> = (args) => {
    process.exitCode = lint(args);
  },
) {
  return new Command()
    .name('bun lint')
    .description(
      "Run ESLint over the tree; the rest of the arguments are ESLint's, an empty one only after --.",
    )
    .arguments('[args...:string]')
    .stopEarly()
    .example('what ESLint can fix, fixed', 'bun lint --fix')
    .action(function (_options, ...args) {
      return run([...args, ...this.getLiteralArgs()]);
    });
}

if (import.meta.main) {
  await lintCommand().parse(process.argv.slice(2));
}
