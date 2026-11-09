/**
 * `chord --riff-agent`: riff's ACP agent on stdin and stdout, until the
 * window closes its stdin.
 */
import { ndJsonStream } from '@agentclientprotocol/sdk/unstable';

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

export async function runRiffAgent(version: string): Promise<void> {
  const riff = connectRiff(
    ndJsonStream(
      outputStream(process.stdout),
      Readable.toWeb(process.stdin) as unknown as ReadableStream<Uint8Array>,
    ),
    {
      version,
      provider: fakeProvider(process.env),
      backend: await libfxBackend(),
      stateDir: chordStateDir(),
    },
  );

  await riff.finished;
  process.exit(0);
}
