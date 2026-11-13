/**
 * The dev CLI's tool runners: chord from source and the tests. Each spawns
 * its tool from the repository's root with the terminal handed over and
 * answers the tool's exit status, which the calling command exits with.
 */
import { spawnSync } from 'node:child_process';
import { mkdirSync, rmSync } from 'node:fs';
import { constants } from 'node:os';
import { join } from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';
import { quote } from 'shell-quote';

/** Runs one command, `env` added, to its end and answers its exit status. */
export type Run = (
  argv: readonly string[],
  env?: Readonly<Record<string, string>>,
) => number;

// A file path, not the URL's percent-encoded one, for a checkout under a name with a space.
const root = fileURLToPath(new URL('../..', import.meta.url));

/** `argv` from the root, on this terminal; a signal is 128 + its number. */
export const spawn: Run = ([command, ...args], env) => {
  const child = spawnSync(command ?? '', args, {
    cwd: root,
    stdio: 'inherit',
    ...(env === undefined ? {} : { env: { ...process.env, ...env } }),
  });

  if (child.error !== undefined) {
    throw child.error;
  }

  return child.signal === null
    ? (child.status ?? 1)
    : 128 + constants.signals[child.signal];
};

/**
 * chord's state kept in `state`, made if missing, instead of the person's
 * own: a fake or QA run writes its records there (CHD-616). Nothing given,
 * the child keeps the environment's.
 */
function stateEnv(state: string | undefined): Record<string, string> {
  if (state === undefined) {
    return {};
  }

  mkdirSync(state, { recursive: true });

  return { XDG_STATE_HOME: state };
}

/** chord from source with React's production build, on the fake agent if `fake`. */
export function chord(
  fake: boolean,
  args: readonly string[],
  run: Run = spawn,
  fixtureResources = false,
  state?: string,
): number {
  return run(chordArgv(fake, args, fixtureResources), stateEnv(state));
}

function chordArgv(
  fake: boolean,
  args: readonly string[],
  fixtureResources: boolean,
): string[] {
  const agent = quote([
    process.execPath,
    join(root, 'tests', 'fixtures', 'fake_agent', 'main.ts'),
  ]);

  return [
    process.execPath,
    '--define',
    'process.env.NODE_ENV:"production"',
    ...(fake || fixtureResources
      ? ['--define', 'process.env.CHORD_RESOURCE_FIXTURE:"true"']
      : []),
    'src/main.tsx',
    ...(fake ? ['fake', '--agent-command', agent] : []),
    ...args,
  ];
}

/** A capture's places, its directory and its state, made afresh: emptied if there. */
export function qaPlace(...dirs: readonly string[]): void {
  for (const dir of dirs) {
    rmSync(dir, { recursive: true, force: true });
    mkdirSync(dir, { recursive: true });
  }
}

/**
 * The whole suite, a worker per core, `args` passed on to bun test. Bun
 * starts each worker's slowest files first, and balances `--shard`, by
 * the times in `tests/timings.json`; nothing here checks or rewrites them
 * (CHD-513).
 */
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
