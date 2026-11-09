/**
 * The backend options chord gives libfx. libfx finds its addon and Wasm with
 * `new URL('./…', import.meta.url)`, which Bun's bundler does not follow, so
 * a compiled binary held neither (CHD-485's gate). The binary embeds both
 * here and passes them through libfx's documented `nativeAddon` and `wasm`;
 * with `backend: 'auto'`, an addon that cannot load falls back to Wasm.
 */
import { readFile } from 'node:fs/promises';
import type { FxNodeBackendOptions } from 'libfx/node';
// The owner's allowed reach past libfx's exports (CHD-485, "Two rules"): it
// exports neither asset, so the import names the file in node_modules. The
// lint rule is for modules; this is a file Bun embeds.
// eslint-disable-next-line no-restricted-syntax
import wasmPath from '../../node_modules/libfx/fx-core.wasm' with { type: 'file' };

declare const CHORD_RESOURCE_COMPILED: boolean;

/** What every libfx engine chord creates is given to load its backend. */
export async function libfxBackend(): Promise<FxNodeBackendOptions> {
  const compiled =
    typeof CHORD_RESOURCE_COMPILED !== 'undefined' && CHORD_RESOURCE_COMPILED;
  const wasm = await readFile(wasmPath);

  if (!compiled) {
    // From source, compile.ts's plugin does not run, and libfx loads its
    // own platform package from node_modules.
    return { backend: 'auto', wasm };
  }

  // Resolved by compile.ts's plugin to this target's addon alone.
  const addon = await import('chord:libfx-native', { with: { type: 'file' } });

  return { backend: 'auto', nativeAddon: addon.default, wasm };
}
