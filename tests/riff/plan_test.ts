import { afterEach, describe, expect, test } from 'bun:test';
import { ndJsonStream } from '@agentclientprotocol/sdk/unstable';
import { z } from '@zod/zod';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import {
  memorySecrets,
  secrets,
  type Secrets,
} from '../../src/platform/secrets.ts';
import { libfxBackend } from '../../src/platform/libfx.ts';
import { connectRiff, type Riff } from '../../src/riff/adapter.ts';
import { riffStore } from '../../src/riff/store.ts';
import { clientOverStreams, type AcpClient } from '../fixtures/acp_client.ts';
import {
  planCredential,
  planFetch,
  type PlanFetch,
} from '../fixtures/riff/plan_fetch.ts';

let root: string | undefined;
let riff: Riff | undefined;
let end: (() => void) | undefined;

async function open(
  plan: 'codex' | 'grok',
  fixture: PlanFetch,
  store?: Secrets,
) {
  root ??= await mkdtemp(join(tmpdir(), 'chord-plan-test-'));

  const pair = clientOverStreams();
  const values =
    store ?? memorySecrets({ [plan]: JSON.stringify(planCredential(plan)) });

  end = pair.end;
  riff = connectRiff(ndJsonStream(pair.output, pair.input), {
    version: 'fixture',
    stateDir: root,
    provider: undefined,
    secrets: values,
    fetch: fixture.fetch,
    backend: await libfxBackend(),
    tools: [
      {
        name: 'mark',
        description: 'Fixture tool.',
        idempotent: true,
        inputSchema: z.toJSONSchema(z.object({ value: z.string() })),
        execute: () => Promise.resolve('fixture tool result'),
      },
    ],
  });

  await pair.client.request('initialize', { protocolVersion: 1 });

  return { client: pair.client, store: values };
}

const start = (client: AcpClient) =>
  client.request('session/new', { cwd: process.cwd(), mcpServers: [] });
const prompt = (client: AcpClient, id: string) =>
  client.request('session/prompt', {
    sessionId: id,
    prompt: [{ type: 'text', text: 'fixture' }],
  });

afterEach(async () => {
  end?.();
  await riff?.finished;

  if (root !== undefined) {
    await rm(root, { recursive: true, force: true });
  }

  root = undefined;
  riff = undefined;
  end = undefined;
});

describe('riff plans on an injected fetch', () => {
  for (const plan of ['codex', 'grok'] as const) {
    test(`${plan}: Responses reasoning and tool calls, plus sidecar identity`, async () => {
      const fixture = planFetch({ plan, tools: true });
      const { client } = await open(plan, fixture);
      const created = await start(client);
      const id = created.result?.['sessionId'] as string;

      expect(created.error).toBeUndefined();

      const answer = await prompt(client, id);

      expect(answer.error, JSON.stringify(fixture.urls)).toBeUndefined();
      expect(answer.result?.['stopReason'], JSON.stringify(fixture.urls)).toBe(
        'end_turn',
      );
      expect(fixture.responses).toBe(2);
      expect(
        fixture.urls.some((url) => url.includes('/models')),
        JSON.stringify(fixture.urls),
      ).toBe(true);
      expect(
        fixture.urls.some((url) =>
          plan === 'codex'
            ? url.startsWith('https://registry.npmjs.org/')
            : url === 'https://x.ai/cli/stable',
        ),
      ).toBe(true);
      expect(client.lines.join('\n')).toContain('Hello from a fixture plan.');
      expect(client.lines.join('\n')).toContain('agent_thought_chunk');
      expect(client.lines.join('\n')).toContain('tool_call');
      expect(await riffStore(root ?? '').read(id)).toMatchObject({
        provider: plan,
        account: 'fixture-account',
      });
    });

    test(`${plan}: 401 refreshes once, saves the rotation and retries`, async () => {
      const fixture = planFetch({ plan, unauthorized: true });
      const { client, store } = await open(plan, fixture);
      const created = await start(client);
      const answer = await prompt(
        client,
        created.result?.['sessionId'] as string,
      );

      expect(answer.error).toBeUndefined();
      expect(answer.result?.['stopReason']).toBe('end_turn');
      expect(fixture.refreshes).toBe(1);
      expect(fixture.responses).toBe(2);
      expect(JSON.parse((await store.get(plan)) ?? '{}')).toMatchObject({
        refreshToken: 'fixture-refresh-1',
      });
      expect(client.lines.join('\n')).toContain('_chord/credentials');
      expect(client.lines.join('\n')).toContain('saved');
    });

    test(`${plan}: rejected refresh clears the entry and fails authentication`, async () => {
      const fixture = planFetch({ plan, unauthorized: true, rejected: true });
      const { client, store } = await open(plan, fixture);
      const created = await start(client);
      const answer = await prompt(
        client,
        created.result?.['sessionId'] as string,
      );

      expect(answer.error?.code).toBe(-32000);
      expect(fixture.refreshes).toBe(1);
      expect(await store.get(plan)).toBeNull();
    });

    test(`${plan}: an unsaved rotation survives and retries at the next credential lock`, async () => {
      const fixture = planFetch({ plan, unauthorized: true });
      const backing = memorySecrets({
        [plan]: JSON.stringify(planCredential(plan)),
      });
      let failing = true;
      const store: Secrets = {
        ...backing,
        set: (provider, value) =>
          failing
            ? Promise.reject(new Error('fixture persistence failed'))
            : backing.set(provider, value),
      };
      const { client } = await open(plan, fixture, store);
      const created = await start(client);
      const id = created.result?.['sessionId'] as string;

      expect((await prompt(client, id)).result?.['stopReason']).toBe(
        'end_turn',
      );
      expect(client.lines.join('\n')).toContain('unsaved');
      expect(JSON.parse((await backing.get(plan)) ?? '{}')).toMatchObject({
        refreshToken: 'fixture-refresh-0',
      });

      failing = false;

      expect((await prompt(client, id)).result?.['stopReason']).toBe(
        'end_turn',
      );
      expect(JSON.parse((await backing.get(plan)) ?? '{}')).toMatchObject({
        refreshToken: 'fixture-refresh-1',
      });
      expect(fixture.refreshes).toBe(1);
      expect(client.lines.join('\n')).toContain('saved');
    });

    test.each(['removed', 'replaced'])(
      `${plan}: L2 refuses %s credentials before fetch`,
      async (changed) => {
        const fixture = planFetch({ plan });
        const { client, store } = await open(plan, fixture);
        const created = await start(client);
        const id = created.result?.['sessionId'] as string;

        if (changed === 'removed') {
          await store.delete(plan);
        } else {
          await store.set(
            plan,
            JSON.stringify({
              ...planCredential(plan),
              accountId: 'another-account',
            }),
          );
        }

        expect((await prompt(client, id)).error?.code).toBe(-32000);
        expect(fixture.urls).toEqual([]);
      },
    );
  }

  test('resume takes its sidecar provider even with both plans saved', async () => {
    const fixture = planFetch({ plan: 'grok' });
    const { client, store } = await open('grok', fixture);
    const created = await start(client);
    const id = created.result?.['sessionId'] as string;

    end?.();
    await riff?.finished;
    await store.set('codex', JSON.stringify(planCredential('codex')));

    const resumed = await open('codex', fixture, store);
    const answer = await resumed.client.request('session/resume', {
      sessionId: id,
      cwd: process.cwd(),
      mcpServers: [],
    });

    expect(answer.error).toBeUndefined();
    expect(answer.result?.['configOptions']).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ id: 'model', currentValue: 'grok-4.7' }),
      ]),
    );
    expect((await prompt(resumed.client, id)).result?.['stopReason']).toBe(
      'end_turn',
    );
    expect(fixture.responses).toBe(1);
  });

  test('no credential returns both methods; no store returns C1 words', async () => {
    const fixture = planFetch({ plan: 'codex' });
    const missing = memorySecrets();
    const { client } = await open('codex', fixture, missing);

    expect((await start(client)).error).toMatchObject({
      code: -32000,
      data: { authMethods: [{ id: 'chatgpt' }, { id: 'grok' }] },
    });
    end?.();
    await riff?.finished;

    const unavailable = secrets(
      {
        get: () => Promise.reject(new Error('fixture no store')),
        set: () => Promise.resolve(),
        delete: () => Promise.resolve(false),
      },
      'Secret Service',
    );
    const next = await open('codex', fixture, unavailable);

    expect((await start(next.client)).error?.message).toContain(
      'no Secret Service (gnome-keyring or KeePassXC). Start one and try again.',
    );
    expect(fixture.urls).toEqual([]);
  });
});
