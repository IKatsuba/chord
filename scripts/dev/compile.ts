/**
 * Compile chord into standalone binaries with `bun build --compile`.
 *
 *   bun dev compile             this machine's target, into dist/<target>/
 *   bun dev compile --all       every target in scripts/targets.ts
 *   bun dev compile --install   this machine's target, into ~/.local/bin/chord
 */
import { spawnSync } from 'node:child_process';
import { homedir } from 'node:os';
import { join } from 'node:path';
import type { BuildConfig, BunPlugin } from 'bun';
import manifest from '../../package.json' with { type: 'json' };
import { TARGETS } from '../targets.ts';

/** `bun dev compile`'s options. */
export interface CompileOptions {
  readonly all: boolean;
  readonly install: boolean;
}

const root = new URL('../..', import.meta.url).pathname;

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
 * The build of `entry` as chord's binary is built, but for where it goes:
 * `compile`'s, and a test's of the production build (CHD-468).
 */
export function buildOptions(entry: string): BuildConfig & { target: 'bun' } {
  return {
    entrypoints: [entry],
    target: 'bun',
    // @opentui/react imports react-devtools-core, its peer, only when
    // DEV=true. Bundled in, a binary run with DEV=true connects to a devtools
    // server that is not there and never exits after quit; external and split
    // into a chunk, the import stays behind OpenTUI's own lazy import, fails,
    // and OpenTUI warns and carries on (CHD-309).
    external: ['react-devtools-core'],
    splitting: true,
    // Nothing sets NODE_ENV, so React would load its development build, which
    // keeps a performance.measure for every render and a stack on every fiber,
    // never cleared (CHD-344). Defined rather than --production, which also
    // minifies and leaves heap snapshots and stack traces without names.
    define: { 'process.env.NODE_ENV': '"production"' },
    plugins: [jsxDevRuntime],
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

  const host = TARGETS.find(
    (target) => target.os === process.platform && target.cpu === process.arch,
  );
  const targets = args.all ? TARGETS : host ? [host] : [];

  if (targets.length === 0) {
    console.error(
      `No target for ${process.platform}-${process.arch}; pass --all for the release set.`,
    );
    process.exit(1);
  }

  // A binary embeds only the clipboard addon that is installed, which is
  // otherwise the host's alone, so a cross-compiled one could not read it.
  run(['install', '--os=*', '--cpu=*']);

  for (const target of targets) {
    const output = args.install
      ? join(homedir(), '.local', 'bin', 'chord')
      : join(root, 'dist', target.bun, 'chord');

    // The JS API, as the command line takes no plugin.
    const built = await Bun.build({
      ...buildOptions(join(root, 'src', 'main.tsx')),
      compile: { target: target.bun, outfile: output },
    });

    if (!built.success) {
      for (const log of built.logs) {
        console.error(log);
      }

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
