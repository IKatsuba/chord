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
import { mkdirSync, readdirSync, readFileSync, rmSync } from 'node:fs';
import { constants } from 'node:os';
import { join } from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';
import { quote } from 'shell-quote';
import {
  compare,
  fails,
  isTestFile,
  MEASURED,
  readTimings,
  RECORD,
  reportLines,
} from './timings.ts';

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

/** What `test` reads and writes besides the run, so a test can stand in for it. */
export interface SuiteFiles {
  /** A file's text from the root; none when it is not there. */
  read(path: string): string | undefined;
  remove(path: string): void;
  /** Every file under `dir`, by its path from the root. */
  list(dir: string): string[];
  say(line: string): void;
}

/** The repository's files, and stderr. */
export const suiteFiles: SuiteFiles = {
  read: (path) => {
    try {
      return readFileSync(join(root, path), 'utf8');
    } catch {
      return undefined;
    }
  },
  remove: (path) => rmSync(join(root, path), { force: true }),
  list: (dir) =>
    readdirSync(join(root, dir), { recursive: true, withFileTypes: true })
      .filter((entry) => entry.isFile())
      .map((entry) =>
        join(entry.parentPath, entry.name)
          .slice(root.length)
          .replace(/^\//, ''),
      ),
  say: (line) => void process.stderr.write(`${line}\n`),
};

/**
 * The whole suite, a worker per core, `args` passed on to bun test, placed
 * by the times `tests/timings.json` records. A run with no arguments, as
 * `bun dev check` and CI make, measures them again into
 * `tests/timings.measured.json` and fails, naming the files, when one is
 * past its budget, moved far from its record, unrecorded or gone, or when
 * the measurement is missing or unreadable; one with `--update-timings`
 * rewrites the record and is held to the budget only. Any other argument
 * leaves the timings unchecked. The tests' own failure is always the
 * status; the timings' report follows it (CHD-501).
 */
export function test(
  args: readonly string[],
  run: Run = spawn,
  files: SuiteFiles = suiteFiles,
): number {
  const refreshing = args.includes('--update-timings');
  const measuring = args.length === 0;

  if (measuring) {
    files.remove(MEASURED);
  }

  const status = run([
    process.execPath,
    'test',
    '--parallel',
    '--timeout=60000',
    ...(measuring
      ? [`--timings=${MEASURED}`, `--timings=${RECORD}`, '--update-timings']
      : [`--timings=${RECORD}`]),
    './tests/',
    ...args,
  ]);

  if (!measuring && !refreshing) {
    return status;
  }

  let failed: boolean;

  try {
    const report = compare(
      readTimings(RECORD, files.read(RECORD)),
      refreshing
        ? readTimings(RECORD, files.read(RECORD))
        : readTimings(MEASURED, files.read(MEASURED)),
      files.list('tests').filter(isTestFile),
      { refreshing },
    );

    for (const line of reportLines(report)) {
      files.say(line);
    }

    failed = fails(report);
  } catch (error) {
    files.say(error instanceof Error ? error.message : String(error));

    failed = true;
  }

  return status !== 0 ? status : failed ? 1 : 0;
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
  files: SuiteFiles = suiteFiles,
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
      : [['the tests', () => test([], run, files)] as [string, () => number]]),
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
