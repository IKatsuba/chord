/**
 * A fake OpenAI Chat Completions server on localhost for riff's tests,
 * through libfx's custom provider (CHD-485, "Tests"). The last user message
 * picks the scenario: one naming `hang` streams a word and then nothing until
 * the request is dropped, `long` ends cut at the output limit, `fail` is
 * refused with a 400, `think` reasons before it answers, `tool` calls the
 * host tool `mark` once and answers once it has its result, `call <tool>
 * <json>` calls that tool with those arguments once and answers with what
 * the tool returned; anything else is
 * answered `Hello from riff.` Every answer reports usage. Nothing reaches a
 * real provider.
 */

/** What every plain answer says. */
export const HELLO = 'Hello from riff.';

/** The usage each answer reports, as the Chat Completions API counts it. */
export const USAGE = { prompt_tokens: 1200, completion_tokens: 34 };

/** One request the server took, as far as tests read it. */
export interface ChatRequest {
  readonly model?: string;
  readonly reasoning_effort?: string;
  readonly messages?: readonly { role?: string; content?: unknown }[];
  readonly tools?: readonly { function?: { name?: string } }[];
}

/** A running fake server. */
export interface FakeChat {
  /** The base URL libfx's custom provider takes. */
  readonly url: string;
  /** Every chat completion request it has taken, in order. */
  readonly requests: readonly ChatRequest[];
  /** Settles once a `hang` request is streaming. */
  hanging(): Promise<void>;
  stop(): Promise<void>;
}

const chunk = (delta: object, finish: string | null = null) =>
  `data: ${JSON.stringify({
    id: 'riff',
    object: 'chat.completion.chunk',
    created: 0,
    model: 'fake',
    choices: [{ index: 0, delta, finish_reason: finish }],
  })}\n\n`;

const usage = `data: ${JSON.stringify({
  id: 'riff',
  object: 'chat.completion.chunk',
  created: 0,
  model: 'fake',
  choices: [],
  usage: {
    ...USAGE,
    total_tokens: USAGE.prompt_tokens + USAGE.completion_tokens,
  },
})}\n\n`;

const answer = (text: string, finish = 'stop') =>
  [
    chunk({ role: 'assistant', content: text }),
    chunk({}, finish),
    usage,
    'data: [DONE]\n\n',
  ].join('');

function lastUser(request: ChatRequest): string {
  const said = request.messages?.findLast(({ role }) => role === 'user');

  return typeof said?.content === 'string'
    ? said.content
    : JSON.stringify(said?.content ?? '');
}

export function serveFakeChat(): FakeChat {
  const requests: ChatRequest[] = [];
  let calls = 0;
  let reviews = 0;
  let hung = Promise.withResolvers<void>();
  const server = Bun.serve({
    hostname: '127.0.0.1',
    port: 0,
    idleTimeout: 0,
    async fetch(request) {
      if (!new URL(request.url).pathname.endsWith('/chat/completions')) {
        return new Response('not found', { status: 404 });
      }

      const body = (await request.json()) as ChatRequest;
      const said = lastUser(body);

      requests.push(body);

      const headers = { 'content-type': 'text/event-stream' };

      if (
        body.tools?.some(
          (tool) => tool.function?.name === 'permission_decision',
        )
      ) {
        // Only the pending action selects the fixture verdict. Requests and
        // untrusted prior output cannot change this deterministic test seam.
        const pending =
          said
            .split('<normalized_action>')[1]
            ?.split('</normalized_action>')[0] ?? '';

        if (pending.includes('[review:failed]')) {
          return new Response(
            answer('Fixture reviewer returned no decision.'),
            { headers },
          );
        }

        const decision = pending.includes('[review:clear]')
          ? 'clear'
          : 'caution';

        return new Response(
          [
            chunk({
              role: 'assistant',
              tool_calls: [
                {
                  index: 0,
                  id: `review_${++reviews}`,
                  type: 'function',
                  function: {
                    name: 'permission_decision',
                    arguments: JSON.stringify({
                      decision,
                      rationale: 'Fixture safety review: caution.',
                    }),
                  },
                },
              ],
            }),
            chunk({}, 'tool_calls'),
            usage,
            'data: [DONE]\n\n',
          ].join(''),
          { headers },
        );
      }

      // First, so a path or a query that names another scenario is only an
      // argument.
      const call = /call (\w+) (\{.*\})/.exec(said);

      if (call !== null) {
        // The tool has answered when its result is the last message.
        const result = body.messages?.at(-1);

        if (result?.role === 'tool') {
          return new Response(answer(String(result.content)), { headers });
        }

        return new Response(
          [
            chunk({
              role: 'assistant',
              tool_calls: [
                {
                  index: 0,
                  // Unique in the server's life, as a provider's ids are.
                  id: `call_${call[1]}_${++calls}`,
                  type: 'function',
                  function: { name: call[1], arguments: call[2] },
                },
              ],
            }),
            chunk({}, 'tool_calls'),
            usage,
            'data: [DONE]\n\n',
          ].join(''),
          { headers },
        );
      }

      if (said.includes('fail')) {
        return Response.json(
          { error: { message: 'the fake refuses', type: 'invalid_request' } },
          { status: 400 },
        );
      }

      if (said.includes('hang')) {
        const encoder = new TextEncoder();

        return new Response(
          new ReadableStream<Uint8Array>({
            start(controller) {
              controller.enqueue(
                encoder.encode(chunk({ role: 'assistant', content: 'Wait' })),
              );
              hung.resolve();
            },
          }),
          { headers },
        );
      }

      if (
        said.includes('tool') &&
        !body.messages?.some(({ role }) => role === 'tool')
      ) {
        return new Response(
          [
            chunk({
              role: 'assistant',
              tool_calls: [
                {
                  index: 0,
                  id: 'call_mark',
                  type: 'function',
                  function: { name: 'mark', arguments: '{}' },
                },
              ],
            }),
            chunk({}, 'tool_calls'),
            usage,
            'data: [DONE]\n\n',
          ].join(''),
          { headers },
        );
      }

      if (said.includes('long')) {
        return new Response(answer('Cut', 'length'), { headers });
      }

      if (said.includes('think')) {
        return new Response(
          chunk({ role: 'assistant', reasoning_content: 'Thinking it over.' }) +
            answer(HELLO),
          { headers },
        );
      }

      return new Response(answer(HELLO), { headers });
    },
  });

  return {
    // libfx takes plain HTTP only on localhost.
    url: `http://localhost:${server.port}/v1`,
    requests,
    hanging: async () => {
      await hung.promise;

      hung = Promise.withResolvers<void>();
    },
    stop: () => server.stop(true),
  };
}
