import { expect, test } from 'bun:test';
import type { FxFetch } from 'libfx/node';
import { libfxBackend } from '../../../src/platform/libfx.ts';
import { reviewer } from '../../../src/riff/review/engine.ts';
import { planCredential, planFetch } from '../../fixtures/riff/plan_fetch.ts';

for (const plan of ['codex', 'grok'] as const) {
  test(`isolated ${plan} reviewer cancels its decision before a second model request`, async () => {
    const fixture = planFetch({ plan, tools: true });
    const bodies: string[] = [];
    const model = plan === 'codex' ? 'gpt-6-luna' : 'grok-4.5';
    const original = plan === 'codex' ? 'gpt-6.1-sol' : 'grok-4.7';
    const fetch: FxFetch = async (url, init) => {
      if (url.endsWith('/responses')) {
        bodies.push(String(init.body));
      }

      const response = await fixture.fetch(url, init);
      const text = (await response.text())
        .replaceAll(original, model)
        .replaceAll('"mark"', '"permission_decision"')
        .replaceAll('\\"value\\":\\"fixture\\"', '\\"decision\\":\\"clear\\"');

      return new Response(text, {
        status: response.status,
        headers: response.headers,
      });
    };

    const run = reviewer({
      configuration: {
        ...(await libfxBackend()),
        ...(plan === 'codex'
          ? { provider: 'codex' as const }
          : { provider: 'grok' as const }),
        model,
        credentials: () => planCredential(plan),
        fetch,
      },
    });

    expect(
      await run(
        '<review_data>pending</review_data>',
        new AbortController().signal,
      ),
    ).toEqual({ outcome: 'clear' });
    expect(fixture.responses).toBe(1);
    expect(bodies[0]).toContain(model);
    expect(bodies[0]).toContain('permission_decision');
    expect(bodies[0]).not.toContain('"name":"shell"');
  });
}

test('text-only review creates a new conversation for its one format retry', async () => {
  const fixture = planFetch({ plan: 'codex' });
  const run = reviewer({
    configuration: {
      ...(await libfxBackend()),
      provider: 'codex',
      model: 'gpt-6-luna',
      credentials: () => planCredential('codex'),
      fetch: fixture.fetch,
    },
  });

  expect((await run('pending', new AbortController().signal)).outcome).toBe(
    'unavailable',
  );
  expect(fixture.responses).toBe(2);
});

test('a model response proposing two decisions is malformed even when cancellation stops the second tool', async () => {
  const fixture = planFetch({ plan: 'codex', tools: true });
  const fetch: FxFetch = async (url, init) => {
    const response = await fixture.fetch(url, init);
    let text = (await response.text())
      .replaceAll('"mark"', '"permission_decision"')
      .replaceAll('\\"value\\":\\"fixture\\"', '\\"decision\\":\\"clear\\"');

    if (url.endsWith('/responses') && fixture.responses === 1) {
      text = text
        .split('\n\n')
        .flatMap((frame) => {
          if (!frame.includes('fc_fixture')) {
            return [frame];
          }

          if (frame.startsWith('event: response.completed')) {
            const data = frame.split('\ndata: ')[1];
            const item = JSON.parse(data ?? '{}') as {
              response: { output: object[] };
            };
            const call = item.response.output[1];

            item.response.output.push(
              JSON.parse(
                JSON.stringify(call)
                  .replaceAll('fc_fixture', 'fc_second')
                  .replaceAll('call_fixture', 'call_second'),
              ) as object,
            );

            return [`event: response.completed\ndata: ${JSON.stringify(item)}`];
          }

          return [
            frame,
            frame
              .replaceAll('fc_fixture', 'fc_second')
              .replaceAll('call_fixture', 'call_second')
              .replaceAll('"output_index":1', '"output_index":2'),
          ];
        })
        .join('\n\n');
    }

    return new Response(text, {
      status: response.status,
      headers: response.headers,
    });
  };

  const run = reviewer({
    configuration: {
      ...(await libfxBackend()),
      provider: 'codex',
      model: 'gpt-6-luna',
      credentials: () => planCredential('codex'),
      fetch,
    },
  });

  expect((await run('pending', new AbortController().signal)).outcome).toBe(
    'unavailable',
  );
  expect(fixture.responses).toBe(2);
});
