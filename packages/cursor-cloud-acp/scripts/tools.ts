/**
 * cursor-cloud-acp's own tooling, run by `bun dev` through its steps.ts: the
 * build, the Node smoke and the release's stages. Bun's tooling, never
 * shipped and outside the package's Node project.
 */
import { spawn, type SpawnSyncOptions } from 'node:child_process';
import { once } from 'node:events';
import { mkdirSync, mkdtempSync, readdirSync, rmSync } from 'node:fs';
import { rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { isAbsolute, join, relative, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { install, quality } from '../../../scripts/dev/release/build.ts';
import {
  die,
  notBun,
  npm,
  type Release,
  ReleaseError,
} from '../../../scripts/dev/release/lib.ts';
import { tarball, tarballs } from '../../../scripts/dev/release/publish.ts';
import { recordSums } from '../../../scripts/dev/release/sums.ts';
import type { StepContext } from '../../../scripts/dev/steps.ts';

/** The package's folder. */
export const here = fileURLToPath(new URL('..', import.meta.url));
const NAME = '@chorded/cursor-cloud-acp';
const FOLDER = 'packages/cursor-cloud-acp';
/** What its tarball holds, and nothing else: no steps.ts, scripts or tests. */
export const PACKED = [
  'LICENSE',
  'README.md',
  'dist/bin.js',
  'dist/main.js',
  'package.json',
];

/**
 * The inputs of a build that are not the package's own source: a
 * dependency bundled in, which `--packages=external` should never allow.
 * `inputs` are the metafile's paths, relative to `cwd`.
 */
export function foreign(
  inputs: readonly string[],
  cwd: string,
  folder = here,
): string[] {
  const source = join(folder, 'src') + sep;

  return inputs.filter((input) => {
    const path = isAbsolute(input) ? input : join(cwd, input);

    return !path.startsWith(source);
  });
}

/**
 * `src/bin.ts` built for Node into `dist/`: JavaScript, as Node 22.13 runs
 * no TypeScript, with every package left an import. Split, so `bin.js`
 * checks Node's version before `main`'s chunk imports a dependency.
 */
export async function build(
  context: Pick<StepContext, 'output'>,
  outdir = join(here, 'dist'),
): Promise<number> {
  await rm(outdir, { recursive: true, force: true });

  const built = await Bun.build({
    entrypoints: [join(here, 'src', 'bin.ts')],
    outdir,
    target: 'node',
    packages: 'external',
    splitting: true,
    naming: { chunk: '[name].[ext]' },
    metafile: true,
  });

  if (!built.success) {
    for (const log of built.logs) {
      context.output(String(log));
    }

    return 1;
  }

  const bundled = foreign(
    Object.keys(built.metafile?.inputs ?? {}),
    process.cwd(),
  );

  if (bundled.length > 0) {
    context.output(
      `build: dist/ bundles files outside src/: ${bundled.map((input) => relative(here, input)).join(', ')}`,
    );

    return 1;
  }

  return 0;
}

/** Why `version` (`v22.12.0`) is below the Node the package needs, if it is. */
export function tooOld(version: string): string | undefined {
  const [major = 0, minor = 0] = version
    .replace(/^v/, '')
    .split('.')
    .map(Number);

  return major > 22 || (major === 22 && minor >= 13)
    ? undefined
    : `the smoke needs Node 22.13 or newer; ${version} is the first node past Bun's on PATH`;
}

/**
 * The tarball installed by Node's npm in a scratch project, then its
 * command served one `initialize` and one `session/new` in a directory
 * outside git: the answer is git's refusal, which comes before any key,
 * keychain or Cursor call, so nothing but npm's install reaches the
 * network. Throws a ReleaseError naming what failed.
 */
export async function smokeTarball(
  release: Release,
  file: string,
): Promise<void> {
  const node = notBun(release, 'node');
  const version = npmLess(release, node, ['--version']);
  const old = tooOld(version);

  if (old !== undefined) {
    die(old);
  }

  const scratch = mkdtempSync(join(tmpdir(), 'cursor-cloud-acp-smoke-'));
  const outside = join(scratch, 'outside');

  mkdirSync(outside);

  try {
    const quiet: SpawnSyncOptions = {
      cwd: scratch,
      stdio: ['ignore', 'ignore', 'inherit'],
    };

    if (
      npm(release, ['init', '-y'], quiet).status !== 0 ||
      npm(release, ['install', '--no-audit', '--no-fund', file], quiet)
        .status !== 0
    ) {
      die(`npm could not install ${file}`);
    }

    const bin = join(scratch, 'node_modules', NAME, 'dist', 'bin.js');
    const answers = await serveOnce([node, bin], outside, release.env);
    const [initialized, refused] = answers;

    if (
      (initialized as { result?: { agentInfo?: { name?: string } } }).result
        ?.agentInfo?.name !== NAME
    ) {
      die(`${NAME} did not answer initialize: ${JSON.stringify(initialized)}`);
    }

    const error = (refused as { error?: { code?: number; message?: string } })
      .error;

    if (
      error?.code !== -32602 ||
      error.message !==
        `${outside} is not in a git work tree. A cloud agent starts from a pushed branch: start chord in a repository, then start again.`
    ) {
      die(
        `session/new outside git was not git's refusal: ${JSON.stringify(refused)}`,
      );
    }
  } finally {
    rmSync(scratch, { recursive: true, force: true });
  }
}

/** `node args`'s stdout, trimmed. */
function npmLess(release: Release, node: string, args: string[]): string {
  const child = Bun.spawnSync([node, ...args], { env: release.env });

  return child.stdout.toString().trim();
}

/** A JSON-RPC 2.0 message, as ACP sends them. */
function isRpc(value: unknown): value is { readonly id?: number } {
  return (
    typeof value === 'object' &&
    value !== null &&
    (value as { jsonrpc?: unknown }).jsonrpc === '2.0'
  );
}

/**
 * Runs `argv` in `cwd`, asks it initialize then session/new there, and
 * answers both. Every stdout line must be a JSON-RPC message, with nothing
 * left unended, and the process must end within 1.5 s of stdin ending. On
 * any failure the child is killed and reaped before the error goes up.
 */
export async function serveOnce(
  argv: readonly string[],
  cwd: string,
  env: NodeJS.ProcessEnv,
  bound = 30_000,
): Promise<unknown[]> {
  const [command = '', ...args] = argv;
  const child = spawn(command, args, {
    cwd,
    // No key from the environment: the refusal must come first regardless.
    env: { ...env, CURSOR_API_KEY: '' },
    stdio: ['pipe', 'pipe', 'inherit'],
  });
  const exited = once(child, 'exit');
  const answers = new Map<number, unknown>();
  const waiting = new Map<number, () => void>();
  let pending = '';
  let notRpc: string | undefined;

  child.stdout.setEncoding('utf8').on('data', (chunk: string) => {
    pending += chunk;

    const lines = pending.split('\n');

    pending = lines.pop() ?? '';

    for (const each of lines) {
      let message: unknown;

      try {
        message = JSON.parse(each);
      } catch {
        message = undefined;
      }

      if (!isRpc(message)) {
        notRpc ??= each;

        continue;
      }

      if (message.id !== undefined) {
        answers.set(message.id, message);
        waiting.get(message.id)?.();
      }
    }
  });

  const deadline = AbortSignal.timeout(bound);
  /** Sends a request and waits for its answer, as a client does. */
  const ask = (id: number, method: string, params: unknown) =>
    Promise.race([
      new Promise<void>((resolve) => {
        waiting.set(id, resolve);
        child.stdin.write(
          `${JSON.stringify({ jsonrpc: '2.0', id, method, params })}\n`,
        );
      }),
      once(deadline, 'abort').then(() =>
        die(`the adapter did not answer ${method} within ${bound / 1000} s`),
      ),
      exited.then(() => die(`the adapter exited before answering ${method}`)),
    ]);

  try {
    await ask(1, 'initialize', { protocolVersion: 1, clientCapabilities: {} });
    await ask(2, 'session/new', { cwd, mcpServers: [] });

    const ended = performance.now();

    child.stdin.end();
    await Promise.race([
      exited,
      once(AbortSignal.timeout(5000), 'abort').then(() =>
        die('the adapter did not exit after stdin ended'),
      ),
    ]);

    if (performance.now() - ended > 1500) {
      die('the adapter took more than 1.5 s to exit after stdin ended');
    }

    if (notRpc !== undefined) {
      die(`a stdout line is not JSON-RPC: ${notRpc}`);
    }

    if (pending !== '') {
      die(`stdout ended inside a line: ${pending}`);
    }

    return [answers.get(1), answers.get(2)];
  } finally {
    if (child.exitCode === null && child.signalCode === null) {
      child.kill('SIGKILL');
      await exited;
    }
  }
}

/** `npm pack` of the package into `destination`; answers the tarball's path. */
function packInto(release: Release, destination: string): string {
  mkdirSync(destination, { recursive: true });

  const packed = npm(
    release,
    ['pack', '--json', '--pack-destination', destination],
    {
      cwd: join(release.root, FOLDER),
      stdio: ['ignore', 'pipe', 'inherit'],
    },
  );

  if (packed.status !== 0) {
    die(`npm pack of ${NAME} failed`);
  }

  const [listing] = JSON.parse(packed.stdout) as {
    filename: string;
    files: { path: string }[];
  }[];
  const files = (listing?.files ?? []).map((each) => each.path).toSorted();

  if (JSON.stringify(files) !== JSON.stringify(PACKED)) {
    die(
      `${NAME}'s tarball holds ${files.join(', ')}, not ${PACKED.join(', ')}`,
    );
  }

  return join(destination, listing!.filename);
}

/** The smoke as a check: the package packed into a scratch folder, then smoked. */
export async function smoke(context: StepContext): Promise<number> {
  const scratch = mkdtempSync(join(tmpdir(), 'cursor-cloud-acp-pack-'));
  const release: Release = {
    root: context.root,
    env: context.env,
    sleep: (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
    out: context.output,
    err: context.output,
    tty: false,
  };

  try {
    await smokeTarball(release, packInto(release, scratch));

    return 0;
  } catch (error) {
    context.output(
      `smoke: ${error instanceof Error ? error.message : String(error)}`,
    );

    return 1;
  } finally {
    rmSync(scratch, { recursive: true, force: true });
  }
}

/** The release's stages (CHD-623), each dying with what it read. */
export const stages = {
  install: (release: Release) => install(release),
  quality: (release: Release) => quality(release, 'cursor-cloud-acp'),
  build: async (release: Release) => {
    if ((await build({ output: release.err })) !== 0) {
      die(`the build of ${NAME} failed`);
    }
  },
  /** The tarball, its sum beside it, installed by Node and run. */
  pack: async (release: Release, version: string) => {
    const destination = tarballs(release, FOLDER);

    rmSync(destination, { recursive: true, force: true });

    const file = packInto(release, destination);

    if (file !== tarball(release, FOLDER, NAME, version)) {
      die(`npm packed ${file}, not version ${version}`);
    }

    recordSums(destination, readdirSync(destination));
    await smokeTarball(release, file);
  },
};

export { ReleaseError };
