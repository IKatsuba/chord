/**
 * A fake OpenAI Chat Completions server on 127.0.0.1 for the binary's
 * `--riff-selftest` (CHD-603): a request without a tool result is answered
 * with a streamed call to `echo` with `{"text":"hi"}`, and one whose tool
 * result is echo's own answer, `ECHOED`, with the text `done`, as CHD-485's
 * gate ran a whole turn. Any other tool result, a failed call's error
 * included, is answered with that result instead of `done`, so a turn whose
 * tool did not run cannot pass. Nothing reaches a real provider.
 */

/** What `echo` answers when it ran on `{"text":"hi"}`. */
export const ECHOED = 'echo: hi';

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
    model: 'selftest',
    choices: [{ index: 0, delta, finish_reason: finish }],
  })}\n\n`;

const toolCall = [
  chunk({
    role: 'assistant',
    tool_calls: [
      {
        index: 0,
        id: 'call_selftest',
        type: 'function',
        function: { name: 'echo', arguments: '{"text":"hi"}' },
      },
    ],
  }),
  chunk({}, 'tool_calls'),
];

const answer = (text: string) => [
  chunk({ role: 'assistant', content: text }),
  chunk({}, 'stop'),
];

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

      const body = (await request.json()) as {
        messages?: { role?: string; content?: unknown }[];
      };
      const result = body.messages?.find((message) => message.role === 'tool');

      return new Response(
        [
          ...(result === undefined
            ? toolCall
            : answer(
                result.content === ECHOED
                  ? 'done'
                  : `echo did not run: ${JSON.stringify(result.content)}`,
              )),
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
