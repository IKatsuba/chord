/**
 * `chord --riff-agent`: riff's ACP agent on stdin and stdout, until the
 * window closes its stdin.
 */
import { ndJsonStream } from '@agentclientprotocol/sdk/unstable';
import process from 'node:process';
import { Readable } from 'node:stream';
import { outputStream } from '../acp/stdio.ts';
import { connectRiff } from './adapter.ts';

export async function runRiffAgent(version: string): Promise<void> {
  const connection = connectRiff(
    ndJsonStream(
      outputStream(process.stdout),
      Readable.toWeb(process.stdin) as unknown as ReadableStream<Uint8Array>,
    ),
    { version },
  );

  await connection.closed;
  process.exit(0);
}
