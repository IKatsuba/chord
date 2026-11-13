/**
 * Compile chord into standalone binaries with `bun build --compile`.
 *
 *   bun dev compile             this machine's target, into dist/<target>/
 *   bun dev compile --all       every target in scripts/targets.ts
 *   bun dev compile --install   this machine's target, into ~/.local/bin/chord
 */
import { spawnSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';
import type { BuildConfig, BunPlugin } from 'bun';
import manifest from '../../package.json' with { type: 'json' };
import { hostTarget, type Target, TARGETS } from '../targets.ts';
import { assertLibfxAssets, libfxAddon, libfxPackage } from './libfx_assets.ts';

/** `bun dev compile`'s options. */
export interface CompileOptions {
  readonly all: boolean;
  readonly install: boolean;
}

const root = new URL('../..', import.meta.url).pathname;

const MAIN = join(root, 'src', 'main.tsx');

const FFF_WORKER = join(root, 'src', 'platform', 'fff_worker.ts');

/**
 * `entry` with fff's Worker (CHD-485): a binary finds a Worker's script
 * only when it was built as one of its entry points, as Bun documents for
 * `--compile`. Entries named flat put the Worker beside the code that starts
 * it, so its `new URL('./fff_worker.ts', import.meta.url)` holds in the
 * binary as from source.
 */
export function withFffWorker(
  entry: string,
): Pick<BuildConfig, 'entrypoints' | 'naming'> {
  return {
    entrypoints: [entry, FFF_WORKER],
    naming: { entry: '[name].[ext]' },
  };
}

/** The fff library a binary for `target` embeds: its own, glibc's on Linux. */
export function fffLibrary(target: Target): string {
  return target.os === 'linux'
    ? `@ff-labs/fff-bin-linux-${target.cpu}-gnu/libfff_c.so`
    : `@ff-labs/fff-bin-${target.os}-${target.cpu}/libfff_c.dylib`;
}

/**
 * Why a build's inputs do not hold `target`'s fff library and no other,
 * or undefined when they do: search needs it in the binary (CHD-485).
 */
export function fffProblem(
  inputs: readonly string[],
  target: Target,
): string | undefined {
  const embedded = inputs.filter((input) => input.includes('/fff-bin-'));
  const wanted = fffLibrary(target);

  return embedded.length === 1 && embedded[0]!.endsWith(wanted)
    ? undefined
    : `${target.bun} embeds ${JSON.stringify(embedded)}, not ${wanted} alone`;
}

/**
 * The inputs of a build that come from cursor-cloud-acp, its SDK or its
 * keyring: that package runs on Node under npx, and none of it may enter
 * the binary (CHD-622).
 */
export function cursorInputs(inputs: readonly string[]): string[] {
  return inputs.filter((input) =>
    /(^|\/)(packages\/cursor-cloud-acp|@cursor\/sdk|@napi-rs\/keyring)[/-]/.test(
      input,
    ),
  );
}

/**
 * `bun install`'s selection of every platform's optional packages. A compile
 * build keeps every OpenTUI native import, and Bun skips the packages whose
 * `libc` is not the machine's on Linux, whatever `--os` and `--cpu` say.
 */
export const EVERY_PLATFORM = ['--os=*', '--cpu=*', '--libc=*'] as const;

/**
 * OpenTUI's `react/jsx-dev-runtime` imports resolved to
 * `./jsx_dev_runtime.ts`. Its published JS builds elements with `jsxDEV`,
 * its ErrorBoundary's fallback among them, and with NODE_ENV production
 * React 19's `jsx-dev-runtime` exports `jsxDEV` as undefined, so the crash
 * screen itself threw in the binary (CHD-468, the owner's Q75).
 */
const jsxDevRuntime: BunPlugin = {
  name: 'opentui-jsx-dev-runtime',
  setup(build) {
    build.onResolve({ filter: /^react\/jsx-dev-runtime$/ }, ({ importer }) =>
      importer.includes('/node_modules/@opentui/')
        ? { path: join(root, 'scripts', 'dev', 'jsx_dev_runtime.ts') }
        : undefined,
    );
  },
};

/**
 * `chord:libfx-native`, which src/platform/libfx.ts imports only in a
 * compiled binary, resolved to `target`'s libfx addon and embedded as a
 * file. Only that one addon goes into the binary: a plain import of every
 * platform's, or one picked by a define, embeds all four (CHD-485). A
 * missing addon fails the build, naming the package and version.
 */
export function libfxNative(target: Target | undefined): BunPlugin {
  return {
    name: 'libfx-native',
    setup(build) {
      build.onResolve({ filter: /^chord:libfx-native$/ }, () => {
        if (target === undefined) {
          throw new Error(
            `libfx has no addon for ${process.platform}-${process.arch}`,
          );
        }

        const path = libfxAddon(target);

        if (!existsSync(path)) {
          throw new Error(
            `${libfxPackage(target)}@${libfxVersion()} has no libfx.node for ${target.bun}; run bun install ${EVERY_PLATFORM.join(' ')}`,
          );
        }

        return { path, namespace: 'libfx-native' };
      });

      build.onLoad({ filter: /.*/, namespace: 'libfx-native' }, ({ path }) => ({
        contents: readFileSync(path),
        loader: 'file',
      }));
    },
  };
}

function libfxVersion(): string {
  const libfx = JSON.parse(
    readFileSync(join(root, 'node_modules', 'libfx', 'package.json'), 'utf8'),
  ) as { version: string };

  return libfx.version;
}

/**
 * The native package OpenTUI loads on `platform` and `arch`, as its own
 * resolveNativeLibraryPath picks one: on Linux the musl build only when
 * `libc` (OPENTUI_LIBC) says musl.
 */
export function loadedNative(
  platform: string,
  arch: string,
  libc: string | undefined,
): string {
  const musl = platform === 'linux' && libc === 'musl' ? '-musl' : '';

  return `@opentui/core-${platform}-${arch}${musl}`;
}

/**
 * OpenTUI's native packages but `loaded`, this machine's by default. A
 * compile for a target keeps only that target's import, as its platform is
 * fixed; a bundle for this machine keeps them all, and an install may hold
 * only the one it runs on, as CI's does (CHD-468).
 */
export function otherNatives(
  loaded = loadedNative(
    process.platform,
    process.arch,
    process.env.OPENTUI_LIBC,
  ),
): string[] {
  const opentui = JSON.parse(
    readFileSync(
      join(root, 'node_modules', '@opentui', 'core', 'package.json'),
      'utf8',
    ),
  ) as { optionalDependencies?: Record<string, string> };

  return Object.keys(opentui.optionalDependencies ?? {}).filter(
    (name) => name !== loaded,
  );
}

/**
 * The build of `entry` as chord's binary is built, but for where it goes:
 * `compile`'s, and a test's of the production build (CHD-468), which runs
 * the bundle on this machine (`host`) and leaves the other platforms'
 * native packages out.
 */
export function buildOptions(
  entry: string,
  {
    host = false,
    compiled = false,
    target = hostTarget(),
  }: { host?: boolean; compiled?: boolean; target?: Target | undefined } = {},
): BuildConfig & { target: 'bun' } {
  return {
    entrypoints: [entry],
    target: 'bun',
    // @opentui/react imports react-devtools-core, its peer, only when
    // DEV=true. Bundled in, a binary run with DEV=true connects to a devtools
    // server that is not there and never exits after quit; external and split
    // into a chunk, the import stays behind OpenTUI's own lazy import, fails,
    // and OpenTUI warns and carries on (CHD-309).
    external: ['react-devtools-core', ...(host ? otherNatives() : [])],
    splitting: true,
    // Nothing sets NODE_ENV, so React would load its development build, which
    // keeps a performance.measure for every render and a stack on every fiber,
    // never cleared (CHD-344). Defined rather than --production, which also
    // minifies and leaves heap snapshots and stack traces without names.
    define: {
      'process.env.NODE_ENV': '"production"',
      ...(compiled ? { CHORD_RESOURCE_COMPILED: 'true' } : {}),
      // fff picks its Linux library by this at build time and embeds it;
      // without it, it looks for the library at run time (its README).
      ...(target?.os === 'linux' ? { FFF_LIBC: '"gnu"' } : {}),
    },
    plugins: [jsxDevRuntime, libfxNative(target)],
  };
}

export async function compile(args: CompileOptions): Promise<void> {
  // Every build flag below was tried on this range, and nothing older was.
  if (!Bun.semver.satisfies(Bun.version, manifest.engines.bun)) {
    console.error(
      `chord compiles on Bun ${manifest.engines.bun}; this is Bun ${Bun.version}.`,
    );
    process.exit(1);
  }

  const host = hostTarget();
  const targets = args.all ? TARGETS : host ? [host] : [];

  if (targets.length === 0) {
    console.error(
      `No target for ${process.platform}-${process.arch}; pass --all for the release set.`,
    );
    process.exit(1);
  }

  // A binary embeds only the clipboard addon that is installed, which is
  // otherwise the host's alone, so a cross-compiled one could not read it.
  run(['install', ...EVERY_PLATFORM]);
  // A libfx layout change fails here, not in the binary it would break.
  assertLibfxAssets(targets);

  for (const target of targets) {
    const output = args.install
      ? join(homedir(), '.local', 'bin', 'chord')
      : join(root, 'dist', target.bun, 'chord');

    // The JS API, as the command line takes no plugin.
    const built = await Bun.build({
      ...buildOptions(MAIN, { compiled: true, target }),
      ...withFffWorker(MAIN),
      compile: { target: target.bun, outfile: output },
      metafile: true,
    });

    if (!built.success) {
      for (const log of built.logs) {
        console.error(log);
      }

      process.exit(1);
    }

    const inputs = Object.keys(built.metafile?.inputs ?? {});
    const fff = fffProblem(inputs, target);
    const cursor = cursorInputs(inputs);

    if (fff !== undefined) {
      console.error(fff);
      process.exit(1);
    }

    if (cursor.length > 0) {
      console.error(
        `${target.bun} holds cursor-cloud-acp's files: ${cursor.join(', ')}`,
      );
      process.exit(1);
    }

    console.log(output);
  }
}

function run(argv: string[]) {
  const { status } = spawnSync(process.execPath, argv, {
    cwd: root,
    stdio: 'inherit',
  });

  if (status !== 0) {
    process.exit(status ?? 1);
  }
}
