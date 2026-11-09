import { afterEach, beforeEach, describe, expect, test } from 'bun:test';
import { ndJsonStream } from '@agentclientprotocol/sdk/unstable';
import { createFxAgent, type FxAgent } from 'libfx/node';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { connectRiff, type Riff, riffInit } from '../../src/riff/adapter.ts';
import { libfxBackend } from '../../src/platform/libfx.ts';
import { clientOverStreams, type AcpClient } from '../fixtures/acp_client.ts';
import {
  type FakeChat,
  HELLO,
  serveFakeChat,
  USAGE,
} from '../fixtures/riff/fake_chat.ts';

let fake: FakeChat;
let client: AcpClient;
let riff: Riff;
let end: () => void;
let stateDir: string;

/** riff in this process, on the fake provider or on none. */
async function open(provider = true): Promise<void> {
  const pair = clientOverStreams();

  client = pair.client;
  end = pair.end;
  riff = connectRiff(ndJsonStream(pair.output, pair.input), {
    version: '1.2.3',
    provider: provider ? { baseUrl: fake.url } : undefined,
    backend: await libfxBackend(),
    stateDir,
  });

  await client.request('initialize', { protocolVersion: 1 });
}

async function newSession(): Promise<string> {
  const answer = await client.request('session/new', {
    cwd: process.cwd(),
    mcpServers: [],
  });

  return answer.result?.['sessionId'] as string;
}

function prompt(sessionId: string, text: string) {
  return client.request('session/prompt', {
    sessionId,
    prompt: [{ type: 'text', text }],
  });
}

beforeEach(async () => {
  fake = serveFakeChat();
  stateDir = await mkdtemp(join(tmpdir(), 'chord-riff-'));
});

afterEach(async () => {
  end();
  await riff.finished;
  await fake.stop();
  await rm(stateDir, { recursive: true, force: true });
});

describe('riff over an in-memory pair', () => {
  test('initialize answers as the design gives it', async () => {
    await open();

    const answer = await client.request('initialize', { protocolVersion: 1 });

    expect(answer.result).toStrictEqual(
      riffInit('1.2.3') as unknown as Record<string, unknown>,
    );
  });

  test('session/new without a provider asks for a sign-in, with the auth methods', async () => {
    await open(false);

    const answer = await client.request('session/new', {
      cwd: process.cwd(),
      mcpServers: [],
    });

    expect(answer.error?.code).toBe(-32000);
    expect(answer.error?.data).toStrictEqual({
      authMethods: riffInit('1.2.3').authMethods,
    });
    expect(fake.requests).toHaveLength(0);
  });

  test('session/new answers its id and the model, effort and mode options', async () => {
    await open();

    const answer = await client.request('session/new', {
      cwd: process.cwd(),
      mcpServers: [],
    });
    const options = answer.result?.['configOptions'] as {
      id: string;
      category: string;
      currentValue: string;
      options: { value: string }[];
    }[];

    expect(answer.result?.['sessionId']).toEqual(expect.any(String));
    expect(
      options.map(({ id, category, currentValue, options: values }) => [
        id,
        category,
        currentValue,
        values.map(({ value }) => value),
      ]),
    ).toStrictEqual([
      ['model', 'model', 'fake', ['fake']],
      [
        'effort',
        'thought_level',
        'default',
        ['default', 'low', 'medium', 'high', 'xhigh'],
      ],
      ['mode', 'mode', 'ask', ['ask', 'auto']],
    ]);
  });

  test('a second session/new is refused: one session per process', async () => {
    await open();
    await newSession();

    const second = await client.request('session/new', {
      cwd: process.cwd(),
      mcpServers: [],
    });

    expect(second.error?.code).toBe(-32600);
    expect(second.error?.message).toContain(
      'riff serves one session per process',
    );
  });

  test('a prompt streams its text, then usage_update, then answers end_turn with usage', async () => {
    await open();

    const sessionId = await newSession();
    const answer = await prompt(sessionId, 'hello');
    const updates = client.updates(sessionId);

    expect(client.said(sessionId)).toBe(HELLO);
    expect(updates.at(-1)).toStrictEqual({
      sessionUpdate: 'usage_update',
      used: USAGE.prompt_tokens + USAGE.completion_tokens,
      size: 128_000,
    });
    expect(answer.result).toStrictEqual({
      stopReason: 'end_turn',
      usage: {
        inputTokens: USAGE.prompt_tokens,
        outputTokens: USAGE.completion_tokens,
        totalTokens: USAGE.prompt_tokens + USAGE.completion_tokens,
      },
    });
  });

  test('reasoning comes as thought chunks', async () => {
    await open();

    const sessionId = await newSession();

    await prompt(sessionId, 'think');

    expect(client.updates(sessionId)[0]).toStrictEqual({
      sessionUpdate: 'agent_thought_chunk',
      content: { type: 'text', text: 'Thinking it over.' },
    });
  });

  test('an effort the model does not offer answers -32603 and resets effort to default', async () => {
    await open();

    const sessionId = await newSession();
    const set = await client.request('session/set_config_option', {
      sessionId,
      configId: 'effort',
      value: 'high',
    });

    expect(set.error).toBeUndefined();

    const answer = await prompt(sessionId, 'hello');
    const reset = client
      .updates(sessionId)
      .find(({ sessionUpdate }) => sessionUpdate === 'config_option_update') as
      { configOptions: { id: string; currentValue: string }[] } | undefined;

    expect(answer.error?.code).toBe(-32603);
    expect(answer.error?.data).toStrictEqual({
      code: 'LIBFX_MODEL_UNSUPPORTED_EFFORT',
    });
    expect(
      reset?.configOptions.find(({ id }) => id === 'effort')?.currentValue,
    ).toBe('default');
  });

  test('set_config_option refuses a value riff does not offer', async () => {
    await open();

    const sessionId = await newSession();
    const answer = await client.request('session/set_config_option', {
      sessionId,
      configId: 'model',
      value: 'gpt-6.1-sol',
    });

    expect(answer.error?.code).toBe(-32602);
  });

  test('session/cancel ends a running turn cancelled', async () => {
    await open();

    const sessionId = await newSession();
    const answer = prompt(sessionId, 'hang');

    await fake.hanging();
    client.notify('session/cancel', { sessionId });

    expect((await answer).result?.['stopReason']).toBe('cancelled');
  });

  test('_session/steering is not offered: chord queues the steer instead', async () => {
    await open();

    const sessionId = await newSession();
    const answer = await client.request('_session/steering', {
      sessionId,
      prompt: [{ type: 'text', text: 'and this' }],
      _meta: { steering: { idleBehavior: 'promptRequired' } },
    });

    expect(answer.error?.code).toBe(-32601);
    expect(riffInit('1.2.3')._meta).toStrictEqual({
      steering: { supported: false },
    });
    expect(fake.requests).toHaveLength(0);
  });

  test('a request for another session is not found', async () => {
    await open();
    await newSession();

    const answer = await prompt('wrun_other', 'hello');

    expect(answer.error?.code).toBe(-32002);
  });

  test('session/close lets the session go', async () => {
    await open();

    const sessionId = await newSession();
    const closed = await client.request('session/close', { sessionId });
    const after = await prompt(sessionId, 'hello');

    expect(closed.result).toStrictEqual({});
    expect(after.error?.code).toBe(-32002);
  });
});

describe('riff owns one session and one prompt', () => {
  test('of two session/new sent together, the second is refused', async () => {
    await open();

    const first = client.answerTo(
      client.send('session/new', { cwd: process.cwd(), mcpServers: [] }),
    );
    const second = client.answerTo(
      client.send('session/new', { cwd: process.cwd(), mcpServers: [] }),
    );

    expect((await first).result?.['sessionId']).toEqual(expect.any(String));
    expect((await second).error?.code).toBe(-32600);
  });

  test('a connection that closes while session/new runs still lets riff finish', async () => {
    await open();
    client.send('session/new', { cwd: process.cwd(), mcpServers: [] });
    end();

    await riff.finished;
  });

  test('a second prompt while one runs is refused, and close cancels the first', async () => {
    await open();

    const sessionId = await newSession();
    const first = prompt(sessionId, 'hang');

    await fake.hanging();

    const second = await prompt(sessionId, 'hello');

    expect(second.error?.code).toBe(-32600);
    expect(second.error?.message).toContain('riff runs one prompt at a time');

    const closed = await client.request('session/close', { sessionId });

    expect(closed.result).toStrictEqual({});
    expect((await first).result?.['stopReason']).toBe('cancelled');
  });
});

describe('a connection that closes while session/new makes the session', () => {
  test('riff finishes only once the agent it was making is closed', async () => {
    const pair = clientOverStreams();
    const entered = Promise.withResolvers<void>();
    const release = Promise.withResolvers<void>();
    const closes: string[] = [];
    let finished = false;

    client = pair.client;
    end = pair.end;
    riff = connectRiff(ndJsonStream(pair.output, pair.input), {
      version: '1.2.3',
      provider: { baseUrl: fake.url },
      backend: await libfxBackend(),
      stateDir,
      createAgent: (options) => {
        const made = createFxAgent(options);

        return Object.assign(Object.create(made) as FxAgent, {
          newSessionId: async () => {
            entered.resolve();
            await release.promise;

            return await made.newSessionId();
          },
          close: async () => {
            closes.push('closed');
            await made.close();
          },
        });
      },
    });

    void riff.finished.then(() => {
      finished = true;
    });

    await client.request('initialize', { protocolVersion: 1 });
    client.send('session/new', { cwd: process.cwd(), mcpServers: [] });
    await entered.promise;
    end();

    try {
      await riff.connection.closed;
      await Bun.sleep(50);

      expect(finished).toBe(false);
      expect(closes).toStrictEqual([]);
    } finally {
      release.resolve();
    }

    await riff.finished;

    expect(closes).toStrictEqual(['closed']);
  });
});

describe("riff's store and resume", () => {
  const sidecar = async (sessionId: string) =>
    JSON.parse(
      await readFile(
        join(stateDir, 'riff', 'sidecars', `${sessionId}.json`),
        'utf8',
      ),
    ) as unknown;

  test('a new session writes its sidecar, and a config change rewrites it', async () => {
    await open();

    const sessionId = await newSession();

    expect(sessionId).toMatch(/^wrun_/);
    expect(await sidecar(sessionId)).toStrictEqual({
      provider: 'fake',
      account: null,
      model: 'fake',
      effort: 'default',
      mode: 'ask',
    });

    await client.request('session/set_config_option', {
      sessionId,
      configId: 'mode',
      value: 'auto',
    });

    expect(await sidecar(sessionId)).toMatchObject({ mode: 'auto' });
  });

  test("resume reopens on the sidecar's options, with the model's history", async () => {
    await open();

    const sessionId = await newSession();

    await client.request('session/set_config_option', {
      sessionId,
      configId: 'mode',
      value: 'auto',
    });
    await prompt(sessionId, 'hello');
    end();
    await riff.finished;

    await open();

    const resumed = await client.request('session/resume', {
      sessionId,
      cwd: process.cwd(),
      mcpServers: [],
    });
    const options = resumed.result?.['configOptions'] as {
      id: string;
      currentValue: string;
    }[];

    expect(options.find(({ id }) => id === 'mode')?.currentValue).toBe('auto');
    expect(client.updates(sessionId)).toStrictEqual([]);

    const answer = await prompt(sessionId, 'again');

    expect(answer.result?.['stopReason']).toBe('end_turn');
    expect(JSON.stringify(fake.requests.at(-1)?.messages)).toContain('hello');
  });

  test('resume of a session riff never had is not found', async () => {
    await open();

    const answer = await client.request('session/resume', {
      sessionId: 'wrun_none',
      cwd: process.cwd(),
      mcpServers: [],
    });

    expect(answer.error?.code).toBe(-32002);
  });

  test('a sidecar is read only for a session id libfx could have given', async () => {
    await open();

    const answer = await client.request('session/resume', {
      sessionId: '../../escape',
      cwd: process.cwd(),
      mcpServers: [],
    });

    expect(answer.error?.code).toBe(-32002);
  });
});

describe('tester: riff turn recovery and isolation', () => {
  test('cancel after a streamed chunk allows a fresh turn in the same session', async () => {
    await open();

    const sessionId = await newSession();
    const first = prompt(sessionId, 'hang');

    await fake.hanging();
    await client.until(
      (message) =>
        message.method === 'session/update' &&
        client.said(sessionId) === 'Wait',
    );
    client.notify('session/cancel', { sessionId });

    expect((await first).result?.['stopReason']).toBe('cancelled');
    expect((await prompt(sessionId, 'hello')).result?.['stopReason']).toBe(
      'end_turn',
    );
    expect(client.said(sessionId)).toBe(`Wait${HELLO}`);
    expect(fake.requests).toHaveLength(2);
  });

  test('steering during a running turn is refused without another provider request', async () => {
    await open();

    const sessionId = await newSession();
    const first = prompt(sessionId, 'hang');

    await fake.hanging();

    try {
      const steer = await client.request('_session/steering', {
        sessionId,
        prompt: [{ type: 'text', text: 'hello' }],
        _meta: { steering: { idleBehavior: 'promptRequired' } },
      });

      expect(steer.error?.code).toBe(-32601);
      expect(fake.requests).toHaveLength(1);
    } finally {
      client.notify('session/cancel', { sessionId });
      await first;
    }
  });

  test('an unsupported effort resets the next turn to a working default', async () => {
    await open();

    const sessionId = await newSession();

    await client.request('session/set_config_option', {
      sessionId,
      configId: 'effort',
      value: 'xhigh',
    });

    expect((await prompt(sessionId, 'hello')).error?.code).toBe(-32603);
    expect(fake.requests).toHaveLength(0);
    expect((await prompt(sessionId, 'hello')).result?.['stopReason']).toBe(
      'end_turn',
    );
    expect(fake.requests).toHaveLength(1);
    expect(fake.requests[0]?.reasoning_effort).toBeUndefined();
    expect(client.said(sessionId)).toBe(HELLO);
  });

  test('a provider 400 maps to refusal and leaves the session usable', async () => {
    await open();

    const sessionId = await newSession();
    const failed = await prompt(sessionId, 'fail');

    expect(failed.result).toStrictEqual({ stopReason: 'refusal' });
    expect(fake.requests).toHaveLength(1);
    expect((await prompt(sessionId, 'hello')).result?.['stopReason']).toBe(
      'end_turn',
    );
    expect(fake.requests).toHaveLength(2);
  });

  test('the custom provider output limit maps libfx OutputTruncated to internal error', async () => {
    await open();

    const sessionId = await newSession();
    const answer = await prompt(sessionId, 'long');

    expect(answer.error).toStrictEqual({
      code: -32603,
      message: 'OutputTruncated',
      data: { code: null },
    });
    expect(client.said(sessionId)).toBe('Cut');
  });
});
