import { describe, expect, test } from 'bun:test';
import { spawnSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import { mkdtemp, rename, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { getBackendInfo } from 'libfx/node';
import manifest from '../../package.json' with { type: 'json' };
import { buildOptions, libfxNative } from '../../scripts/dev/compile.ts';
import { libfxAddon, libfxPackage } from '../../scripts/dev/libfx_assets.ts';
import { type Target, TARGETS } from '../../scripts/targets.ts';
import { libfxBackend } from '../../src/platform/libfx.ts';

const FIXTURE = fileURLToPath(
  new URL('../fixtures/libfx/main.ts', import.meta.url),
);
const host = TARGETS.find(
  (target) => target.os === process.platform && target.cpu === process.arch,
);

describe('libfx backend options', () => {
  test('from source, libfx finds its own addon and gets the Wasm bytes', async () => {
    const options = await libfxBackend();

    expect(options.backend).toBe('auto');
    expect(options).not.toHaveProperty('nativeAddon');
    expect([...(options.wasm as Uint8Array).subarray(0, 4)]).toEqual([
      0x00, 0x61, 0x73, 0x6d,
    ]);
    expect((await getBackendInfo(options)).backend).toBe('native');
    expect(
      (await getBackendInfo({ ...options, nativeAddon: false })).backend,
    ).toBe('wasm-jspi');
  });

  test.if(host !== undefined)(
    "compiled, the binary embeds this target's addon alone and loads both backends with no node_modules",
    async () => {
      const directory = await mkdtemp(join(tmpdir(), 'chord-libfx-'));
      const binary = join(directory, 'libfx');

      try {
        const built = await Bun.build({
          ...buildOptions(FIXTURE, { compiled: true }),
          compile: { outfile: binary },
          metafile: true,
        });

        expect(built.success).toBe(true);
        expect(
          Object.keys(built.metafile!.inputs).filter((input) =>
            input.endsWith('libfx.node'),
          ),
        ).toEqual([
          expect.stringContaining(`${libfxPackage(host!)}/libfx.node`),
        ]);

        const run = spawnSync(binary, { cwd: directory, encoding: 'utf8' });

        expect(run.stderr).toBe('');
        expect(JSON.parse(run.stdout)).toMatchObject({
          native: 'native',
          wasm: 'wasm-jspi',
        });
      } finally {
        await rm(directory, { recursive: true, force: true });
      }
    },
    120_000,
  );

  test('a missing addon fails the build, naming the package and version', async () => {
    // No such package: the build must stop rather than embed nothing.
    const missing = { bun: 'bun-linux-x64', os: 'linux', cpu: 'ia32' };
    const built = await Bun.build({
      entrypoints: [FIXTURE],
      target: 'bun',
      define: { CHORD_RESOURCE_COMPILED: 'true' },
      plugins: [libfxNative(missing as unknown as Target)],
      throw: false,
    });

    expect(built.success).toBe(false);
    expect(built.logs.map(String).join('\n')).toContain(
      `@libfx/libfx-linux-ia32-gnu@${manifest.dependencies.libfx} has no libfx.node for bun-linux-x64`,
    );
  });

  test('fff embeds its glibc library on the Linux targets alone', () => {
    for (const target of TARGETS) {
      expect(buildOptions('entry.ts', { target }).define?.FFF_LIBC).toBe(
        target.os === 'linux' ? '"gnu"' : undefined,
      );
    }
  });
});

describe('CHD-603 U3 tester: target isolation and fallback', () => {
  for (const target of TARGETS) {
    test.skipIf(!existsSync(dirname(libfxAddon(target))))(
      `${target.bun} fails when its real platform addon is missing`,
      async () => {
        const addon = libfxAddon(target);
        const held = `${addon}.tester-held`;

        await rename(addon, held);

        try {
          const built = await Bun.build({
            ...buildOptions(FIXTURE, { compiled: true, target }),
            throw: false,
          });

          expect(built.success).toBe(false);
          expect(built.logs.map(String).join('\n')).toContain(
            `${libfxPackage(target)}@${manifest.dependencies.libfx} has no libfx.node for ${target.bun}`,
          );
        } finally {
          await rename(held, addon);
        }
      },
    );
  }

  for (const target of TARGETS) {
    test.skipIf(!existsSync(dirname(libfxAddon(target))))(
      `${target.bun} embeds only its addon in a cross-compiled fixture`,
      async () => {
        const directory = await mkdtemp(join(tmpdir(), 'chord-libfx-target-'));

        try {
          const built = await Bun.build({
            ...buildOptions(FIXTURE, { compiled: true, target }),
            compile: { target: target.bun, outfile: join(directory, 'libfx') },
            metafile: true,
          });

          expect(built.success).toBe(true);
          expect(
            Object.keys(built.metafile!.inputs).filter((input) =>
              input.endsWith('libfx.node'),
            ),
          ).toEqual([
            expect.stringContaining(`${libfxPackage(target)}/libfx.node`),
          ]);
        } finally {
          await rm(directory, { recursive: true, force: true });
        }
      },
      120_000,
    );
  }

  test('auto falls back to Wasm when an addon exists but cannot load', async () => {
    const directory = await mkdtemp(join(tmpdir(), 'chord-libfx-broken-'));
    const addon = join(directory, 'broken.node');

    try {
      await writeFile(addon, 'not a native addon');

      const options = await libfxBackend();

      expect(
        (await getBackendInfo({ ...options, nativeAddon: addon })).backend,
      ).toBe('wasm-jspi');
    } finally {
      await rm(directory, { recursive: true, force: true });
    }
  });
});
