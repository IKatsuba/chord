/**
 * A fake OpenAI Chat Completions server on 127.0.0.1 for the binary's riff
 * turn (CHD-604): every request is answered with the streamed text `done`,
 * as riff has no tools before CHD-604b. Nothing reaches a real provider.
 */

/** What every answer says. */
export const DONE = 'done';

/** A running fake server. */
export interface FakeChat {
  /** The base URL libfx's custom provider takes. */
  readonly url: string;
  /** How many chat completion requests it has answered. */
  requests(): number;
  stop(): Promise<void>;
}

const chunk = (delta: object, finish: string | null = null) =>
  `data: ${JSON.stringify({
    id: 'selftest',
    object: 'chat.completion.chunk',
    created: 0,
    model: 'fake',
    choices: [{ index: 0, delta, finish_reason: finish }],
  })}\n\n`;

export function serveFakeChat(): FakeChat {
  let requests = 0;
  const server = Bun.serve({
    hostname: '127.0.0.1',
    port: 0,
    fetch(request) {
      if (!new URL(request.url).pathname.endsWith('/chat/completions')) {
        return new Response('not found', { status: 404 });
      }

      requests++;

      return new Response(
        [
          chunk({ role: 'assistant', content: DONE }),
          chunk({}, 'stop'),
          'data: [DONE]\n\n',
        ].join(''),
        { headers: { 'content-type': 'text/event-stream' } },
      );
    },
  });

  return {
    // libfx takes plain HTTP only on localhost.
    url: `http://localhost:${server.port}/v1`,
    requests: () => requests,
    stop: () => server.stop(true),
  };
}
