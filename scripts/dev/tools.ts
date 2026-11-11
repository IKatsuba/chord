/**
 * The tool runners shared by the dev CLI and the quality package scripts:
 * chord from source, the tests, the checks, formatting and ESLint. Each
 * spawns its tool from the repository's root with the terminal handed over
 * and answers the tool's
 * exit status, which the calling command exits with.
 *
 * ESLint runs as `bun run eslint`, on Bun through bunfig.toml:
 * Bun finds the bin in node_modules/.bin and, by bunfig.toml's
 * `[run] bun = true`, runs it on Bun, when `bun scripts/dev.ts` is started
 * directly (the release) as much as through `bun dev`.
 */
import { spawn as spawnChild, spawnSync } from 'node:child_process';
import { once } from 'node:events';
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

/**
 * Runs `argv` from the root on this terminal, `env` added, to its end and
 * answers its status as `spawn` does, leaving this process free to serve.
 */
export type RunServing = (
  argv: readonly string[],
  env: Readonly<Record<string, string>>,
) => Promise<number>;

export const spawnServing: RunServing = async ([command, ...args], env) => {
  const child = spawnChild(command ?? '', args, {
    cwd: root,
    stdio: 'inherit',
    env: { ...process.env, ...env },
  });
  const [status, signal] = (await once(child, 'exit')) as [
    number | null,
    NodeJS.Signals | null,
  ];

  return signal === null ? (status ?? 1) : 128 + constants.signals[signal];
};

/** A fake provider served while chord runs: its base URL and its stop. */
export interface FakeProvider {
  readonly url: string;
  stop(): Promise<void>;
}

/** Riff's tests' fake Chat Completions server, in this process. */
async function serveFakeProvider(): Promise<FakeProvider> {
  const { serveFakeChat } =
    await import('../../tests/fixtures/riff/fake_chat.ts');

  return serveFakeChat();
}

/**
 * chord from source on riff, `args` after it, with React's production build
 * and fixture resources. Its provider, which also lists riff (CHD-485), is
 * the fake Chat Completions server of its tests, served here
 * while chord runs, whose scenarios answer by the prompt's words
 * (`call read {"path":"a.txt"}` calls a tool).
 */
export async function chordOnRiff(
  args: readonly string[],
  run: RunServing = spawnServing,
  serve: () => Promise<FakeProvider> = serveFakeProvider,
  qa = false,
  state?: string,
): Promise<number> {
  const { FAKE_PROVIDER_ENV } = await import('../../src/riff/start.ts');
  const { QA_ENV } = await import('../../src/riff/qa.ts');
  const kept = stateEnv(state);
  const provider = await serve();

  try {
    return await run(
      [
        process.execPath,
        '--define',
        'process.env.NODE_ENV:"production"',
        '--define',
        'process.env.CHORD_RESOURCE_FIXTURE:"true"',
        'src/main.tsx',
        'riff',
        ...args,
      ],
      {
        [FAKE_PROVIDER_ENV]: provider.url,
        [QA_ENV]: qa ? '1' : '',
        ...kept,
      },
    );
  } finally {
    await provider.stop();
  }
}

/**
 * chord's state kept in `state`, made if missing, instead of the person's
 * own: a fake or QA run writes its records and riff's store there
 * (CHD-616). Nothing given, the child keeps the environment's.
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
): number {
  return run(chordArgv(fake, args, fixtureResources));
}

/**
 * `chord` with riff's fake provider served while it runs, which lists riff
 * and lets it be picked: what `--fake` and `--qa` start (CHD-604c).
 */
export async function chordWithRiff(
  fake: boolean,
  args: readonly string[],
  fixtureResources = false,
  run: RunServing = spawnServing,
  serve: () => Promise<FakeProvider> = serveFakeProvider,
  state?: string,
): Promise<number> {
  const { FAKE_PROVIDER_ENV } = await import('../../src/riff/start.ts');
  const { QA_ENV } = await import('../../src/riff/qa.ts');
  const kept = stateEnv(state);
  const provider = await serve();

  try {
    return await run(chordArgv(fake, args, fixtureResources), {
      [FAKE_PROVIDER_ENV]: provider.url,
      [QA_ENV]: fixtureResources ? '1' : '',
      ...kept,
    });
  } finally {
    await provider.stop();
  }
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

/** ESLint over the tree, `args` passed on. */
export function lint(args: readonly string[], run: Run = spawn): number {
  return run([process.execPath, 'run', 'eslint', '.', ...args]);
}

/**
 * The static checks in order, then the suite unless `only` static; after
 * Bun's type check, that it checked every tracked TypeScript file (`covered.ts`). The
 * step that fails is named through `say`, as one that ends without a word
 * of its own would otherwise leave nothing to read (CHD-467).
 */
export function check(
  only: { static?: boolean },
  run: Run = spawn,
  say: (line: string) => void = (line) => void process.stderr.write(line),
): number {
  const steps: [string, () => number][] = [
    ['types', () => run([process.execPath, 'check'])],
    ['covered', () => run([process.execPath, 'scripts/dev/covered.ts'])],
    ['eslint', () => lint([], run)],
    ['format', () => run([process.execPath, 'fmt', '--check', '.'])],
    ["lint/'s tests", () => run([process.execPath, 'test', 'lint/'])],
    ...(only.static === true
      ? []
      : [['the suite', () => test([], run)] as [string, () => number]]),
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
