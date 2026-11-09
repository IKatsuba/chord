/**
 * `chord --riff-agent`: riff's ACP agent on stdin and stdout, until the
 * window closes its stdin.
 */
import { ndJsonStream } from '@agentclientprotocol/sdk/unstable';
import { type FxNodeBackendOptions, getBackendInfo } from 'libfx/node';
import process from 'node:process';
import { Readable } from 'node:stream';
import { outputStream } from '../acp/stdio.ts';
import { libfxBackend } from '../platform/libfx.ts';
import { chordStateDir } from '../session/state_dir.ts';
import { connectRiff, type FakeProvider } from './adapter.ts';

/**
 * The fake Chat Completions server's base URL. Only tests, selftest, --fake
 * and --qa set it, never settings: it is the one provider riff has until it
 * can sign in (CHD-485 part 4).
 */
export const FAKE_PROVIDER_ENV = 'CHORD_RIFF_FAKE_PROVIDER';

export function fakeProvider(
  env: Readonly<Record<string, string | undefined>>,
): FakeProvider | undefined {
  const baseUrl = env[FAKE_PROVIDER_ENV];

  return baseUrl === undefined || baseUrl === '' ? undefined : { baseUrl };
}

/**
 * `wasm` turns libfx's native addon off. Only tests and selftest set it,
 * never settings: selftest proves the binary's WebAssembly core loads.
 */
export const BACKEND_ENV = 'CHORD_RIFF_BACKEND';

/** The backend options chord's libfx takes, as `env` may narrow them. */
export function riffBackend(
  base: FxNodeBackendOptions,
  env: Readonly<Record<string, string | undefined>>,
): FxNodeBackendOptions {
  return env[BACKEND_ENV] === 'wasm' ? { ...base, nativeAddon: false } : base;
}

export async function runRiffAgent(version: string): Promise<void> {
  const backend = riffBackend(await libfxBackend(), process.env);

  const info = await getBackendInfo(backend);

  // Neither libfx core loads: riff does not start, and says why.
  if (info.backend === 'unavailable') {
    process.stderr.write(
      `riff: no libfx backend loads: ${info.attempts
        .map((attempt) => attempt.reason?.message ?? attempt.backend)
        .join('; ')}\n`,
    );
    process.exit(1);
  }

  // What selftest reads to know which backend each turn ran on.
  process.stderr.write(`riff: backend ${info.backend}\n`);

  const riff = connectRiff(
    ndJsonStream(
      outputStream(process.stdout),
      Readable.toWeb(process.stdin) as unknown as ReadableStream<Uint8Array>,
    ),
    {
      version,
      provider: fakeProvider(process.env),
      backend,
      stateDir: chordStateDir(),
    },
  );

  await riff.finished;
  process.exit(0);
}
