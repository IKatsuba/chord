/**
 * riff in a process of its own for the fake-crash test (CHD-485, T2):
 * `bun crash_child.ts <state dir> <fake url> <ready file>`. Its one host tool,
 * `mark`, publishes the ready file and then never returns, so the test can
 * kill the process with a turn open and a call running.
 */
import { ndJsonStream } from '@agentclientprotocol/sdk/unstable';
import { rename, writeFile } from 'node:fs/promises';
import process from 'node:process';
import { Readable } from 'node:stream';
import { outputStream } from '../../../src/acp/stdio.ts';
import { libfxBackend } from '../../../src/platform/libfx.ts';
import { connectRiff } from '../../../src/riff/adapter.ts';

const [stateDir, baseUrl, ready] = process.argv.slice(2);

if (stateDir === undefined || baseUrl === undefined || ready === undefined) {
  throw new Error('crash_child takes a state dir, a fake url and a ready file');
}

connectRiff(
  ndJsonStream(
    outputStream(process.stdout),
    Readable.toWeb(process.stdin) as unknown as ReadableStream<Uint8Array>,
  ),
  {
    version: '0.0.0',
    provider: { baseUrl },
    backend: await libfxBackend(),
    stateDir,
    tools: [
      {
        name: 'mark',
        description: 'Marks the test.',
        inputSchema: { type: 'object', properties: {} },
        // A tool with effects, as edit, write and shell are: libfx stores
        // the turn before it runs one, so a crash leaves the turn on record.
        idempotent: false,
        writes: true,
        execute: async () => {
          // Published whole, so the test never reads half a file (CHD-589).
          await writeFile(`${ready}.tmp`, `${process.pid}\n`);
          await rename(`${ready}.tmp`, ready);

          return await new Promise<never>(() => {});
        },
      },
    ],
  },
);
