/**
 * `chord --riff-agent`: riff's ACP agent on stdin and stdout, until the
 * window closes its stdin.
 */
import { ndJsonStream } from '@agentclientprotocol/sdk/unstable';
import { type FxNodeBackendOptions, getBackendInfo } from 'libfx/node';
import process from 'node:process';
import { Readable } from 'node:stream';
import { xdgConfig } from 'xdg-basedir';
import { outputStream } from '../acp/stdio.ts';
import { libfxBackend } from '../platform/libfx.ts';
import { chordStateDir } from '../session/state_dir.ts';
import { connectRiff } from './adapter.ts';
import { riffAccess } from './qa.ts';

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

export async function runRiffAgent(
  version: string,
  access = riffAccess(process.env),
): Promise<void> {
  const { provider, secrets } = access;

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
      provider,
      secrets,
      fetch: access.fetch,
      backend,
      stateDir: chordStateDir(),
      ...(xdgConfig === undefined ? {} : { configHome: xdgConfig }),
    },
  );

  await riff.finished;
  process.exit(0);
}
