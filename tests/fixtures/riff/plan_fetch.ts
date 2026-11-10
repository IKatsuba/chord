/** Responses and OAuth fixtures: every unlisted URL fails locally. */
import type { FxFetch } from 'libfx/node';

export interface PlanFetch {
  readonly fetch: FxFetch;
  readonly urls: string[];
  readonly tokens: string[];
  responses: number;
  refreshes: number;
}

export function planCredential(plan: 'codex' | 'grok', rotation = 0) {
  const claims =
    plan === 'codex'
      ? {
          'https://api.openai.com/auth': {
            chatgpt_account_id: 'fixture-account',
          },
        }
      : { sub: 'fixture-account' };
  const accessToken = `fixture.${Buffer.from(JSON.stringify(claims)).toString('base64url')}.signature-${rotation}`;

  return {
    accessToken,
    refreshToken: `fixture-refresh-${rotation}`,
    accountId: 'fixture-account',
    expiresAt: Date.now() + 3_600_000,
  };
}

const stream = (items: object[]) =>
  new Response(
    items
      .map((item) => {
        const type = 'type' in item ? item.type : '';

        return `event: ${String(type)}\ndata: ${JSON.stringify(item)}\n\n`;
      })
      .join(''),
    { headers: { 'content-type': 'text/event-stream' } },
  );

export function planFetch(options: {
  readonly plan: 'codex' | 'grok';
  readonly unauthorized?: boolean;
  readonly rejected?: boolean;
  readonly rejectionStatus?: number;
  readonly tools?: boolean;
}): PlanFetch {
  const fixture: PlanFetch = {
    urls: [],
    tokens: [],
    responses: 0,
    refreshes: 0,
    fetch: (url, init) => {
      fixture.urls.push(url);

      const parsed = new URL(url);

      if (url === 'https://x.ai/cli/stable') {
        return Promise.resolve(new Response('1.0.0'));
      }

      if (parsed.hostname === 'registry.npmjs.org') {
        return Promise.resolve(
          Response.json({ version: '1.0.0', 'dist-tags': { latest: '1.0.0' } }),
        );
      }

      if (
        parsed.pathname === '/oauth/token' ||
        parsed.pathname === '/oauth2/token'
      ) {
        fixture.refreshes++;

        if (options.rejected) {
          return Promise.resolve(
            Response.json(
              { error: 'fixture refresh failure' },
              { status: options.rejectionStatus ?? 400 },
            ),
          );
        }

        const next = planCredential(options.plan, fixture.refreshes);

        return Promise.resolve(
          Response.json({
            access_token: next.accessToken,
            refresh_token: next.refreshToken,
            expires_in: 3600,
          }),
        );
      }

      if (parsed.pathname === '/oauth2/userinfo') {
        return Promise.resolve(Response.json({ sub: 'fixture-account' }));
      }

      if (
        parsed.pathname.endsWith('/models') ||
        parsed.pathname === '/v1/language-models'
      ) {
        const model = options.plan === 'codex' ? 'gpt-6.1-sol' : 'grok-4.7';

        return Promise.resolve(
          Response.json({
            models: [
              {
                slug: model,
                id: model,
                display_name: model,
                context_window: 400000,
                supported_in_api: true,
                supported_reasoning_levels: [
                  { effort: 'low', description: 'Low' },
                ],
              },
            ],
            data: [{ id: model, object: 'model' }],
          }),
        );
      }

      if (parsed.pathname.endsWith('/responses')) {
        fixture.responses++;
        fixture.tokens.push(
          new Headers(init?.headers).get('authorization') ?? '',
        );

        if (options.unauthorized && fixture.responses === 1) {
          return Promise.resolve(
            Response.json(
              { error: { message: 'fixture unauthorized' } },
              { status: 401 },
            ),
          );
        }

        const tool =
          options.tools && fixture.responses === (options.unauthorized ? 2 : 1);
        const item = tool
          ? {
              type: 'function_call',
              id: 'fc_fixture',
              call_id: 'call_fixture',
              name: 'mark',
              arguments: '{"value":"fixture"}',
            }
          : {
              type: 'message',
              id: 'msg_fixture',
              role: 'assistant',
              status: 'completed',
              content: [
                {
                  type: 'output_text',
                  text: 'Hello from a fixture plan.',
                  annotations: [],
                },
              ],
            };
        const response = {
          id: `resp_${fixture.responses}`,
          object: 'response',
          status: 'completed',
          output: [
            {
              id: 'reason_fixture',
              type: 'reasoning',
              summary: [{ type: 'summary_text', text: 'Fixture reasoning.' }],
            },
            item,
          ],
          usage: { input_tokens: 10, output_tokens: 5, total_tokens: 15 },
        };
        const events: object[] = [
          {
            type: 'response.created',
            response: { ...response, status: 'in_progress', output: [] },
          },
          {
            type: 'response.output_item.added',
            output_index: 0,
            item: { id: 'reason_fixture', type: 'reasoning', summary: [] },
          },
          {
            type: 'response.reasoning_summary_text.delta',
            item_id: 'reason_fixture',
            output_index: 0,
            summary_index: 0,
            delta: 'Fixture reasoning.',
          },
          {
            type: 'response.output_item.done',
            output_index: 0,
            item: {
              id: 'reason_fixture',
              type: 'reasoning',
              summary: [{ type: 'summary_text', text: 'Fixture reasoning.' }],
            },
          },
          {
            type: 'response.output_item.added',
            output_index: 1,
            item: tool ? { ...item, arguments: '' } : { ...item, content: [] },
          },
          ...(tool
            ? [
                {
                  type: 'response.function_call_arguments.delta',
                  item_id: item.id,
                  output_index: 1,
                  delta: '{"value":"fixture"}',
                },
                {
                  type: 'response.function_call_arguments.done',
                  item_id: item.id,
                  output_index: 1,
                  arguments: '{"value":"fixture"}',
                },
              ]
            : [
                {
                  type: 'response.content_part.added',
                  item_id: item.id,
                  output_index: 1,
                  content_index: 0,
                  part: { type: 'output_text', text: '', annotations: [] },
                },
                {
                  type: 'response.output_text.delta',
                  item_id: item.id,
                  output_index: 1,
                  content_index: 0,
                  delta: 'Hello from a fixture plan.',
                },
                {
                  type: 'response.output_text.done',
                  item_id: item.id,
                  output_index: 1,
                  content_index: 0,
                  text: 'Hello from a fixture plan.',
                },
              ]),
          { type: 'response.output_item.done', output_index: 1, item },
          { type: 'response.completed', response },
        ];

        return Promise.resolve(stream(events));
      }

      return Promise.reject(
        new Error(`Unexpected fixture URL: ${parsed.origin}${parsed.pathname}`),
      );
    },
  };

  return fixture;
}
