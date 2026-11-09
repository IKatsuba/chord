// In lint/ so the static job runs it: a libfx layout change fails CI before
// any binary is built from it.
import { afterEach, describe, expect, test } from 'bun:test';
import {
  mkdirSync,
  mkdtempSync,
  readdirSync,
  readFileSync,
  rmSync,
  symlinkSync,
  writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import manifest from '../package.json' with { type: 'json' };
import {
  libfxAssetFailures,
  libfxPackage,
} from '../scripts/dev/libfx_assets.ts';
import { TARGETS } from '../scripts/targets.ts';

const modules = join(import.meta.dir, '..', 'node_modules');
const pinned = manifest.dependencies.libfx;
const darwinArm = libfxPackage(TARGETS[0]!);
const projects: string[] = [];

/**
 * A project whose node_modules links to the installed libfx and its platform
 * packages, but for the files `change` gives: a string replaces a file's
 * text, null leaves it out. Linking keeps the copies cheap; libfx itself
 * still loads from the installed tree.
 */
function project(
  change: Record<string, Record<string, string | null> | null> = {},
): string {
  const dir = mkdtempSync(join(tmpdir(), 'chord-libfx-'));

  projects.push(dir);
  writeFileSync(join(dir, 'package.json'), '{}');

  for (const name of ['libfx', ...TARGETS.map(libfxPackage)]) {
    const files = change[name];
    const target = join(dir, 'node_modules', name);

    mkdirSync(join(target, '..'), { recursive: true });

    if (files === null) {
      continue;
    }

    if (files === undefined) {
      symlinkSync(join(modules, name), target);
      continue;
    }

    mkdirSync(target);

    for (const entry of readdirSync(join(modules, name))) {
      if (!(entry in files)) {
        symlinkSync(join(modules, name, entry), join(target, entry));
      }
    }

    for (const [entry, text] of Object.entries(files)) {
      if (text !== null) {
        writeFileSync(join(target, entry), text);
      }
    }
  }

  return dir;
}

afterEach(() => {
  for (const dir of projects.splice(0)) {
    rmSync(dir, { recursive: true, force: true });
  }
});

describe('libfx assets', () => {
  test('the installed tree holds', () => {
    expect(libfxAssetFailures()).toEqual([]);
  });

  test('the linked copy holds', () => {
    expect(libfxAssetFailures(project(), pinned)).toEqual([]);
  });

  test('a renamed addon fails, naming the package and version', () => {
    const dir = project({
      [darwinArm]: {
        'index.js': 'export default new URL("./fx.node", import.meta.url);\n',
        'libfx.node': null,
      },
    });

    expect(libfxAssetFailures(dir, pinned)).toEqual([
      `${darwinArm}@${pinned}'s index.js no longer names ./libfx.node`,
    ]);
  });

  test('a removed platform package fails', () => {
    const dir = project({ [darwinArm]: null });

    expect(libfxAssetFailures(dir, pinned)).toEqual([
      `${darwinArm}@${pinned} is not installed; run bun install --os='*' --cpu='*' --libc='*'`,
    ]);
  });

  test('a platform package dropped from optionalDependencies fails', () => {
    const libfx = { ...manifestOf('libfx') };
    const optional = { ...libfx.optionalDependencies };

    delete optional[darwinArm];

    const dir = project({
      libfx: {
        'package.json': JSON.stringify({
          ...libfx,
          optionalDependencies: optional,
        }),
      },
    });

    expect(libfxAssetFailures(dir, pinned)).toEqual([
      `libfx@${pinned} no longer lists ${darwinArm} for bun-darwin-arm64`,
    ]);
  });

  test('a missing Wasm fails', () => {
    const dir = project({ libfx: { 'fx-core.wasm': null } });

    expect(libfxAssetFailures(dir, pinned)).toEqual([
      `libfx@${pinned} has no fx-core.wasm`,
    ]);
  });

  test('a Wasm that is not WebAssembly fails', () => {
    const dir = project({ libfx: { 'fx-core.wasm': 'not wasm' } });

    expect(libfxAssetFailures(dir, pinned)).toEqual([
      `libfx@${pinned}'s fx-core.wasm is not WebAssembly`,
    ]);
  });

  test('a version off the pin fails', () => {
    expect(libfxAssetFailures(project(), '0.0.15')).toEqual([
      `libfx@${pinned} is installed, but package.json pins 0.0.15`,
    ]);
  });

  test('a platform package at another version fails', () => {
    const dir = project({
      [darwinArm]: {
        'package.json': JSON.stringify({
          ...manifestOf(darwinArm),
          version: '0.0.15',
        }),
      },
    });

    expect(libfxAssetFailures(dir, pinned)).toEqual([
      `${darwinArm}@0.0.15 is installed, not ${pinned}`,
    ]);
  });

  test('no libfx at all fails', () => {
    const dir = project({ libfx: null });

    expect(libfxAssetFailures(dir, pinned)[0]).toBe(
      `libfx@${pinned} is not installed; run bun install`,
    );
  });
});

function manifestOf(name: string): {
  version: string;
  optionalDependencies?: Record<string, string>;
} {
  return JSON.parse(
    readFileSync(join(modules, name, 'package.json'), 'utf8'),
  ) as { version: string; optionalDependencies?: Record<string, string> };
}
