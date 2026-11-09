/**
 * A fake `chord --riff-agent` for the self-test's tests: an ACP agent on
 * stdio that names its backend on stderr as riff does and, per prompt, plays
 * riff's turn against the fake Chat Completions server: a request each for
 * the search, the read and the answer, the two calls drawn as riff draws
 * them, then `done`; it goes at EOF. No libfx, so the tests need no built
 * binary.
 */
import {
  agent,
  ndJsonStream,
  type ContentBlock,
  type SessionUpdate,
} from '@agentclientprotocol/sdk/unstable';
import process from 'node:process';
import { Readable } from 'node:stream';
import { NEEDLE, NEEDLE_FILE } from '../../scripts/dev/release/fake_chat.ts';
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
    const update = (update: SessionUpdate) =>
      client.notify('session/update', { sessionId: params.sessionId, update });

    for (const [results, call] of [
      [0, { title: `Search ${NEEDLE}`, text: `${NEEDLE_FILE}:1: ${NEEDLE}` }],
      [1, { title: `Read ${NEEDLE_FILE}`, text: NEEDLE }],
      [2, undefined],
    ] as const) {
      await fetch(
        `${process.env['CHORD_RIFF_FAKE_PROVIDER']}/chat/completions`,
        {
          method: 'POST',
          body: JSON.stringify({
            messages: Array.from({ length: results }, () => ({ role: 'tool' })),
          }),
        },
      );

      if (call !== undefined) {
        const toolCallId = `call_${results}`;

        await update({
          sessionUpdate: 'tool_call',
          toolCallId,
          title: call.title,
        });
        await update({
          sessionUpdate: 'tool_call_update',
          toolCallId,
          status: 'completed',
          content: [
            { type: 'content', content: { type: 'text', text: call.text } },
          ],
        });
      }
    }

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
