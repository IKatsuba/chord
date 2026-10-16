/**
 * chord's own tooling as one command, run from the tree:
 *
 *   bun run dev <command>   see `bun run dev --help`
 */
import { Command } from '@cliffy/command';
import process from 'node:process';
import type { CompileOptions } from './dev/compile.ts';
import type { MemoryOptions } from './dev/memory.ts';

/**
 * What each command does once its arguments are parsed. Apart from the
 * declarations, so a test parses argv through the very tree `bun run dev`
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
};

/** `bun run dev`'s commands, declared, each running through `actions`. */
export function devCommand(actions: DevActions = RUN) {
  return (
    new Command()
      .name('bun run dev')
      .description("chord's build, release and maintenance tools.")
      .action(function () {
        this.showHelp();
      })
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
            'bun run dev selftest dist/bun-darwin-x64/chord --arch x86_64',
          )
          .action(({ arch }, binary) => actions.selftest(binary, arch)),
      )
      // Back to the root, so what a caller chains on applies to the whole tree.
      .reset()
  );
}

if (import.meta.main) {
  await devCommand().parse(process.argv.slice(2));
}
