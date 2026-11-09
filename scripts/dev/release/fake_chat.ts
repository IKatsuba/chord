/**
 * A fake OpenAI Chat Completions server on 127.0.0.1 for the binary's riff
 * turn (CHD-604, CHD-604b). By how many tool results a request carries, it
 * calls riff's `search` for the needle, then `read` of the file it is in,
 * then answers the streamed text `done`. Nothing reaches a real provider.
 */

/** What every last answer says. */
export const DONE = 'done';

/** The text the turn searches for, in the file it reads. */
export const NEEDLE = 'selftest-needle';

/** The file in the project that holds the needle. */
export const NEEDLE_FILE = 'needle.txt';

/** A running fake server. */
export interface FakeChat {
  /** The base URL libfx's custom provider takes. */
  readonly url: string;
  /** How many chat completion requests it has answered. */
  requests(): number;
  stop(): Promise<void>;
}

/** The tool calls of a turn, in order, before its answer. */
const CALLS = [
  { name: 'search', arguments: { query: NEEDLE } },
  { name: 'read', arguments: { path: NEEDLE_FILE } },
] as const;

const chunk = (delta: object, finish: string | null = null) =>
  `data: ${JSON.stringify({
    id: 'selftest',
    object: 'chat.completion.chunk',
    created: 0,
    model: 'fake',
    choices: [{ index: 0, delta, finish_reason: finish }],
  })}\n\n`;

/** How many tool results the request's messages carry. */
function toolResults(body: unknown): number {
  const messages = (body as { messages?: { role?: string }[] }).messages;

  return messages?.filter(({ role }) => role === 'tool').length ?? 0;
}

export function serveFakeChat(): FakeChat {
  let requests = 0;
  const server = Bun.serve({
    hostname: '127.0.0.1',
    port: 0,
    async fetch(request) {
      if (!new URL(request.url).pathname.endsWith('/chat/completions')) {
        return new Response('not found', { status: 404 });
      }

      requests++;

      const call = CALLS[toolResults(await request.json().catch(() => ({})))];
      const headers = { 'content-type': 'text/event-stream' };

      if (call !== undefined) {
        return new Response(
          [
            chunk({
              role: 'assistant',
              tool_calls: [
                {
                  index: 0,
                  id: `selftest_${call.name}_${requests}`,
                  type: 'function',
                  function: {
                    name: call.name,
                    arguments: JSON.stringify(call.arguments),
                  },
                },
              ],
            }),
            chunk({}, 'tool_calls'),
            'data: [DONE]\n\n',
          ].join(''),
          { headers },
        );
      }

      return new Response(
        [
          chunk({ role: 'assistant', content: DONE }),
          chunk({}, 'stop'),
          'data: [DONE]\n\n',
        ].join(''),
        { headers },
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
