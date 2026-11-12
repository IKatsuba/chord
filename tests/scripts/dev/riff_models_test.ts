import { afterEach, beforeEach, describe, expect, test } from 'bun:test';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import {
  copying,
  isCatalog,
  listed,
  PROMPT,
  riffModels,
} from '../../../scripts/dev/riff_models.ts';
import { libfxBackend } from '../../../src/platform/libfx.ts';
import { memorySecrets } from '../../../src/platform/secrets.ts';
import { planCredential, planFetch } from '../../../src/riff/qa_provider.ts';

let dir: string;

beforeEach(async () => {
  dir = await mkdtemp(join(tmpdir(), 'chord-riff-models-'));
});

afterEach(async () => {
  await rm(dir, { recursive: true, force: true });
});

describe('riff-models on a fake plan', () => {
  test.each(['codex', 'grok'] as const)(
    '%s: says what it sends, sends one turn, prints the listed models and writes the raw responses',
    async (plan) => {
      const said: string[] = [];
      const fake = planFetch({ plan });
      const out = join(dir, 'out', `${plan}.json`);
      const found = await riffModels({
        plan,
        secrets: memorySecrets({
          [plan]: JSON.stringify(planCredential(plan)),
        }),
        fetch: fake.fetch,
        backend: await libfxBackend(),
        stateDir: dir,
        out,
        say: (line) => said.push(line),
      });

      expect(said.slice(0, 4)).toEqual([
        `plan:   ${plan}`,
        expect.stringMatching(
          /^model: {2}\S+ \(riff's default for the plan\)$/u,
        ),
        `prompt: ${PROMPT}`,
        'Sending one turn.',
      ]);
      expect(fake.responses).toBe(1);
      expect(found.caught.length).toBeGreaterThan(0);

      expect(said).toContain(
        plan === 'codex'
          ? '  gpt-6.1-sol  window 500000  levels low medium high xhigh max ultra  default ?'
          : '  grok-4.7  window 256000  levels low medium high xhigh  default ?',
      );

      const written = JSON.parse(await readFile(out, 'utf8')) as {
        plan: string;
        prompt: string;
        responses: { url: string }[];
      };

      expect(written).toMatchObject({ plan, prompt: PROMPT });
      expect(written.responses.length).toBe(found.caught.length);
      expect(said.at(-1)).toBe(`The raw responses are in ${out}.`);
    },
  );

  test('a plan with no sign-in stops before anything is sent', async () => {
    const fake = planFetch({ plan: 'codex' });

    await expect(
      riffModels({
        plan: 'codex',
        secrets: memorySecrets(),
        fetch: fake.fetch,
        backend: await libfxBackend(),
        stateDir: dir,
        out: join(dir, 'never.json'),
        say: () => {},
      }),
    ).rejects.toThrow();
    expect(fake.urls).toEqual([]);
  });
});

describe('riff-models copying', () => {
  test('the engine gets the very response; only models bodies are copied', async () => {
    const caught: { url: string; status: number; body: unknown }[] = [];
    const answers = new Map<string, Response>();
    const fetch = copying((url) => {
      const response = Response.json({ models: [{ slug: 'm' }] });

      answers.set(url, response);

      return Promise.resolve(response);
    }, caught);
    const models =
      'https://chatgpt.com/backend-api/codex/models?client_version=1';
    const turn = 'https://chatgpt.com/backend-api/codex/responses';

    expect(await fetch(models, {})).toBe(answers.get(models)!);
    expect(await fetch(turn, {})).toBe(answers.get(turn)!);
    expect(caught).toEqual([
      { url: models, status: 200, body: { models: [{ slug: 'm' }] } },
    ]);
    // The engine can still read the body it was given.
    expect(await answers.get(models)!.json()).toEqual({
      models: [{ slug: 'm' }],
    });
  });

  test('which URLs are model lists', () => {
    expect(isCatalog('https://chatgpt.com/backend-api/codex/models')).toBe(
      true,
    );
    expect(isCatalog('https://cli-chat-proxy.grok.com/v1/models')).toBe(true);
    expect(isCatalog('https://api.x.ai/v1/language-models')).toBe(true);
    expect(isCatalog('https://chatgpt.com/backend-api/codex/responses')).toBe(
      false,
    );
  });

  test('entries read as far as they say, ? for the rest', () => {
    expect(
      listed({
        models: [
          {
            slug: 'a',
            context_window: 1,
            supported_reasoning_levels: [{ effort: 'low' }, { effort: 'high' }],
            default_reasoning_level: 'low',
          },
        ],
      }),
    ).toEqual([{ id: 'a', window: '1', levels: 'low high', default: 'low' }]);
    expect(listed({ data: [{ id: 'b' }] })).toEqual([
      { id: 'b', window: '?', levels: '?', default: '?' },
    ]);
    expect(listed('not json')).toEqual([]);
  });
});

describe('CHD-611 tester: model evidence boundaries', () => {
  test('a non-JSON catalog keeps status and text without copying request credentials', async () => {
    const caught: { url: string; status: number; body: unknown }[] = [];
    const url = 'https://fixture.invalid/v1/models';
    const init = { headers: { Authorization: 'Bearer fixture-secret-marker' } };
    const response = new Response('catalog temporarily unavailable', {
      status: 503,
      headers: { 'x-fixture': 'unchanged' },
    });
    const fetch = copying((givenUrl, givenInit) => {
      expect(givenUrl).toBe(url);
      expect(givenInit).toBe(init);

      return Promise.resolve(response);
    }, caught);

    expect(await fetch(url, init)).toBe(response);
    expect(response.bodyUsed).toBe(false);
    expect(response.headers.get('x-fixture')).toBe('unchanged');
    expect(caught).toEqual([
      { url, status: 503, body: 'catalog temporarily unavailable' },
    ]);
    expect(JSON.stringify(caught)).not.toContain('fixture-secret-marker');
    expect(await response.text()).toBe('catalog temporarily unavailable');
  });

  test('turn responses stay unread and absent from catalog evidence', async () => {
    const caught: { url: string; status: number; body: unknown }[] = [];
    const response = new Response('fixture turn stream');
    const fetch = copying(() => Promise.resolve(response), caught);

    expect(await fetch('https://fixture.invalid/v1/responses', {})).toBe(
      response,
    );
    expect(response.bodyUsed).toBe(false);
    expect(caught).toEqual([]);
    expect(await response.text()).toBe('fixture turn stream');
  });

  test('a rejected fetch preserves its error and adds no evidence', async () => {
    const failure = new Error('fixture network failure');
    const caught: { url: string; status: number; body: unknown }[] = [];
    const fetch = copying(() => Promise.reject(failure), caught);

    await expect(fetch('https://fixture.invalid/v1/models', {})).rejects.toBe(
      failure,
    );
    expect(caught).toEqual([]);
  });

  test('an unsigned Grok fixture creates no raw file and sends no request', async () => {
    let calls = 0;
    const out = join(dir, 'no-sign-in.json');

    await expect(
      riffModels({
        plan: 'grok',
        secrets: memorySecrets(),
        fetch: () => {
          calls++;

          return Promise.reject(new Error('Unexpected fixture fetch.'));
        },
        backend: await libfxBackend(),
        stateDir: dir,
        out,
        say: () => {},
      }),
    ).rejects.toThrow();
    expect(calls).toBe(0);
    await expect(readFile(out, 'utf8')).rejects.toThrow('ENOENT');
  });
});
