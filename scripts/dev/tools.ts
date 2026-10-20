/**
 * The commands that were package.json scripts (CHD-411): chord from source,
 * the tests, the checks, Prettier and ESLint. Each spawns its tool from the
 * repository's root with the terminal handed over and answers the tool's
 * exit status, which `bun dev` exits with.
 *
 * tsc, ESLint and Prettier run as `bun run <bin>`, as the scripts ran them:
 * Bun finds the bin in node_modules/.bin and, by bunfig.toml's
 * `[run] bun = true`, runs it on Bun, when `bun scripts/dev.ts` is started
 * directly (the release) as much as through `bun dev`.
 */
import { spawnSync } from 'node:child_process';
import { mkdirSync, rmSync } from 'node:fs';
import { constants } from 'node:os';
import { join } from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';
import { quote } from 'shell-quote';

/** Runs one command to its end and answers its exit status. */
export type Run = (argv: readonly string[]) => number;

// A file path, not the URL's percent-encoded one, for a checkout under a name with a space.
const root = fileURLToPath(new URL('../..', import.meta.url));

/** `argv` from the root, on this terminal; a signal is 128 + its number. */
export const spawn: Run = ([command, ...args]) => {
  const child = spawnSync(command ?? '', args, {
    cwd: root,
    stdio: 'inherit',
  });

  if (child.error !== undefined) {
    throw child.error;
  }

  return child.signal === null
    ? (child.status ?? 1)
    : 128 + constants.signals[child.signal];
};

/** chord from source with React's production build, on the fake agent if `fake`. */
export function chord(
  fake: boolean,
  args: readonly string[],
  run: Run = spawn,
): number {
  const agent = quote([
    process.execPath,
    join(root, 'tests', 'fixtures', 'fake_agent', 'main.ts'),
  ]);

  return run([
    process.execPath,
    '--define',
    'process.env.NODE_ENV:"production"',
    'src/main.tsx',
    ...(fake ? ['fake', '--agent-command', agent] : []),
    ...args,
  ]);
}

/** `dir`, a capture's directory, made afresh: emptied if it was there. */
export function qaPlace(dir: string): void {
  rmSync(dir, { recursive: true, force: true });
  mkdirSync(dir, { recursive: true });
}

/** The whole suite, a worker per core, `args` passed on to bun test. */
export function test(args: readonly string[], run: Run = spawn): number {
  return run([
    process.execPath,
    'test',
    '--parallel',
    '--timeout=60000',
    '--timings=tests/timings.json',
    './tests/',
    ...args,
  ]);
}

/** ESLint over the tree, `args` passed on. */
export function lint(args: readonly string[], run: Run = spawn): number {
  return run([process.execPath, 'run', 'eslint', '.', ...args]);
}

/** Prettier's layout written over the tree. */
export function fmt(run: Run = spawn): number {
  return run([process.execPath, 'run', 'prettier', '--write', '.']);
}

/**
 * The static checks in order, then the suite unless `only` static; after
 * tsc, that it checked every tracked TypeScript file (`covered.ts`). The
 * step that fails is named through `say`, as one that ends without a word
 * of its own would otherwise leave nothing to read (CHD-467).
 */
export function check(
  only: { static?: boolean },
  run: Run = spawn,
  say: (line: string) => void = (line) => void process.stderr.write(line),
): number {
  const steps: [string, () => number][] = [
    ['tsc', () => run([process.execPath, 'run', 'tsc'])],
    ['covered', () => run([process.execPath, 'scripts/dev/covered.ts'])],
    ['eslint', () => lint([], run)],
    [
      'prettier',
      () => run([process.execPath, 'run', 'prettier', '--check', '.']),
    ],
    ["lint/'s tests", () => run([process.execPath, 'test', 'lint/'])],
    ...(only.static === true
      ? []
      : [['the tests', () => test([], run)] as [string, () => number]]),
  ];

  for (const [name, step] of steps) {
    const status = step();

    if (status !== 0) {
      say(`check: ${name} failed with status ${status}\n`);

      return status;
    }
  }

  return 0;
}
