/**
 * The libfx layout chord's binary embeds, checked before a build so a libfx
 * change fails the build and not the binary (CHD-485, "The build"). The
 * binary imports `fx-core.wasm` and the target's `libfx.node` by their paths
 * inside node_modules and passes them to libfx's `wasm` and `nativeAddon`
 * options, so what libfx documents does not cover these paths: this does.
 */
import { createRequire } from 'node:module';
import { join } from 'node:path';
import { readFileSync } from 'node:fs';
import manifest from '../../package.json' with { type: 'json' };
import { TARGETS, type Target } from '../targets.ts';

/** The libfx API chord's use of it was written against. */
export const LIBFX_API_VERSION = 3;

const root = new URL('../..', import.meta.url).pathname;

/**
 * The platform package that holds `target`'s addon, as libfx's own table of
 * native packages names it: glibc builds alone on Linux.
 */
export function libfxPackage(target: Target): string {
  const libc = target.os === 'linux' ? '-gnu' : '';

  return `@libfx/libfx-${target.os}-${target.cpu}${libc}`;
}

/** Where `target`'s addon is inside `modules`, a node_modules directory. */
export function libfxAddon(
  target: Target,
  modules = join(root, 'node_modules'),
): string {
  return join(modules, libfxPackage(target), 'libfx.node');
}

/** Where libfx's WebAssembly core is inside `modules`. */
export function libfxWasm(modules = join(root, 'node_modules')): string {
  return join(modules, 'libfx', 'fx-core.wasm');
}

interface Manifest {
  version?: string;
  optionalDependencies?: Record<string, string>;
}

/**
 * Every way the libfx installed under `project` differs from the layout the
 * build relies on, one line each naming the package and version; empty when
 * it holds. `pinned` is the version package.json pins.
 */
export function libfxAssetFailures(
  project = root,
  pinned: string = manifest.dependencies.libfx,
): string[] {
  const modules = join(project, 'node_modules');
  const failures: string[] = [];
  const libfx = readManifest(join(modules, 'libfx'));

  if (libfx === undefined) {
    return [`libfx@${pinned} is not installed; run bun install`];
  }

  const version = libfx.version ?? 'unknown';
  const name = `libfx@${version}`;

  if (version !== pinned) {
    failures.push(`${name} is installed, but package.json pins ${pinned}`);
  }

  for (const target of TARGETS) {
    const platform = libfxPackage(target);
    const listed = libfx.optionalDependencies?.[platform];

    if (listed !== version) {
      failures.push(
        listed === undefined
          ? `${name} no longer lists ${platform} for ${target.bun}`
          : `${name} lists ${platform}@${listed}, not ${version}`,
      );
      continue;
    }

    const installed = readManifest(join(modules, platform));

    if (installed?.version !== version) {
      failures.push(
        installed === undefined
          ? `${platform}@${version} is not installed; run bun install --os='*' --cpu='*' --libc='*'`
          : `${platform}@${installed.version} is installed, not ${version}`,
      );
      continue;
    }

    // The package names its addon with new URL('./libfx.node', …); a
    // renamed file would leave the embedded path pointing at nothing.
    const index = readText(join(modules, platform, 'index.js'));

    if (
      !index?.includes("'./libfx.node'") &&
      !index?.includes('"./libfx.node"')
    ) {
      failures.push(
        `${platform}@${version}'s index.js no longer names ./libfx.node`,
      );
    }
  }

  const wasm = readBytes(libfxWasm(modules));

  if (wasm === undefined) {
    failures.push(`${name} has no fx-core.wasm`);
  } else if (!isWasm(wasm)) {
    failures.push(`${name}'s fx-core.wasm is not WebAssembly`);
  }

  const api = apiVersion(project);

  if (api !== LIBFX_API_VERSION) {
    failures.push(
      `${name} has libfxApiVersion ${String(api)}, not ${LIBFX_API_VERSION}`,
    );
  }

  return failures;
}

/** Prints the failures and exits, so `bun dev compile` stops before building. */
export function assertLibfxAssets(project = root): void {
  const failures = libfxAssetFailures(project);

  if (failures.length > 0) {
    for (const failure of failures) {
      console.error(`libfx layout: ${failure}`);
    }

    process.exit(1);
  }
}

function isWasm(bytes: Uint8Array): boolean {
  return (
    bytes.length >= 4 &&
    bytes[0] === 0x00 &&
    bytes[1] === 0x61 &&
    bytes[2] === 0x73 &&
    bytes[3] === 0x6d
  );
}

// libfx's own documented export, loaded as `project` resolves it.
function apiVersion(project: string): unknown {
  try {
    const libfx = createRequire(join(project, 'package.json'))('libfx') as {
      libfxApiVersion?: unknown;
    };

    return libfx.libfxApiVersion;
  } catch (error) {
    return `unloadable (${(error as Error).message})`;
  }
}

function readManifest(dir: string): Manifest | undefined {
  const text = readText(join(dir, 'package.json'));

  return text === undefined ? undefined : (JSON.parse(text) as Manifest);
}

function readText(path: string): string | undefined {
  return readBytes(path)?.toString();
}

function readBytes(path: string): Buffer | undefined {
  try {
    return readFileSync(path);
  } catch {
    return undefined;
  }
}
