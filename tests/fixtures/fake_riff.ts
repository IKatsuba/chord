/**
 * A fake `chord --riff-agent` for the self-test's tests: an ACP agent on
 * stdio that names its backend on stderr as riff does, makes one request to
 * the fake Chat Completions server per prompt and answers `done`, then goes
 * at EOF. No libfx, so the tests need no built binary.
 */
import {
  agent,
  ndJsonStream,
  type ContentBlock,
} from '@agentclientprotocol/sdk/unstable';
import process from 'node:process';
import { Readable } from 'node:stream';
import { outputStream } from '../../src/acp/stdio.ts';

process.stderr.write(
  `riff: backend ${process.env['CHORD_RIFF_BACKEND'] === 'wasm' ? 'wasm-jspi' : 'native'}\n`,
);

const connection = agent({ name: 'riff' })
  .onRequest('initialize', () => ({
    protocolVersion: 1,
    agentCapabilities: {},
    authMethods: [],
  }))
  .onRequest('session/new', () => ({ sessionId: 'fake' }))
  .onRequest('session/prompt', async ({ params, client }) => {
    await fetch(`${process.env['CHORD_RIFF_FAKE_PROVIDER']}/chat/completions`, {
      method: 'POST',
      body: '{}',
    });

    const content: ContentBlock = { type: 'text', text: 'done' };

    await client.notify('session/update', {
      sessionId: params.sessionId,
      update: { sessionUpdate: 'agent_message_chunk', content },
    });

    return { stopReason: 'end_turn' };
  })
  .connect(
    ndJsonStream(
      outputStream(process.stdout),
      Readable.toWeb(process.stdin) as unknown as ReadableStream<Uint8Array>,
    ),
  );

await connection.closed;
process.exit(0);
