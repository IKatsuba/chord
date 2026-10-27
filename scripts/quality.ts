/** The aggregate quality gate, leaving Bun's native fmt and check unshadowed. */
import { Command } from '@cliffy/command';
import process from 'node:process';
import { check } from './dev/tools.ts';

/** The quality gate, parsed apart from running its tools for tests. */
export function qualityCommand(
  run: (options: { static: boolean }) => void | Promise<void> = (options) => {
    process.exitCode = check(options);
  },
) {
  return new Command()
    .name('bun quality')
    .description(
      "Bun's type and format checks, coverage of tracked TypeScript, ESLint and lint/'s own tests, then the whole suite. It stops at the first failing step with that step's status.",
    )
    .option('--static', 'Run the static checks without the suite.', {
      default: false,
    })
    .action((options) => run(options));
}

if (import.meta.main) {
  await qualityCommand().parse(process.argv.slice(2));
}
