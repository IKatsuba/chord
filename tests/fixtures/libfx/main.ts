// Built as chord's binary is, it prints which backend libfx would load with
// chord's options, and with native turned off, from wherever it runs.
import { getBackendInfo } from 'libfx/node';
import { libfxBackend } from '../../../src/platform/libfx.ts';

const options = await libfxBackend();
const native = await getBackendInfo(options);
const wasm = await getBackendInfo({ ...options, nativeAddon: false });

console.log(
  JSON.stringify({
    native: native.backend,
    wasm: wasm.backend,
    attempts: [...native.attempts, ...wasm.attempts],
  }),
);
