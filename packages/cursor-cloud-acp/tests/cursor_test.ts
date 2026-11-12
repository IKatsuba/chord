import { describe, expect, test } from 'bun:test';
import * as sdk from '@cursor/sdk';
import { cursorPort, normalise } from '../src/cursor.ts';
import { CursorError } from '../src/errors.ts';

describe('normalise tells the SDK errors apart by class and code', () => {
  test.each([
    ['auth', new sdk.AuthenticationError('Invalid API key')],
    ['rate-limit', new sdk.RateLimitError('Too many requests')],
    ['busy', new sdk.AgentBusyError('Agent has an active run')],
    ['not-found', new sdk.AgentNotFoundError('No such agent')],
    ['network', new sdk.NetworkError('Service unavailable')],
    [
      'archived',
      new sdk.ConfigurationError('Agent is archived', {
        code: 'agent_archived',
      }),
    ],
    [
      'other',
      new sdk.ConfigurationError('Invalid model', { code: 'invalid_model' }),
    ],
    ['other', new sdk.UnknownAgentError('Something broke')],
  ] as const)('%s', (kind, error) => {
    const normalised = normalise(error);

    expect(normalised).toBeInstanceOf(CursorError);
    expect(normalised).toMatchObject({
      kind,
      message: error.message,
      sdkClass: error.name,
      cause: error,
    });
  });

  test('integration keeps its help link, though it is a ConfigurationError', () => {
    const error = new sdk.IntegrationNotConnectedError('Connect GitHub', {
      helpUrl: 'https://cursor.com/integrations',
      provider: 'github',
      code: 'integration_not_connected',
      requestId: 'req-2',
    });

    expect(normalise(error)).toMatchObject({
      kind: 'integration',
      message: 'Connect GitHub',
      helpUrl: 'https://cursor.com/integrations',
      code: 'integration_not_connected',
      requestId: 'req-2',
    });
  });

  test('anything not an SDK error is passed on as it came', () => {
    const error = new Error('spawn ENOENT');

    expect(normalise(error)).toBe(error);
    expect(normalise('x')).toBe('x');
  });
});

/** A run whose every call fails with `error`, its stream after one message. */
function failingRun(error: Error): sdk.Run {
  return {
    id: 'run-1',
    agentId: 'bc-1',
    supports: () => true,
    async *stream() {
      yield { type: 'status', status: 'RUNNING' } as unknown as sdk.SDKMessage;

      throw error;
    },
    wait: () => Promise.reject(error),
    cancel: () => Promise.reject(error),
    conversation: () => Promise.reject(error),
  } as unknown as sdk.Run;
}

/** The SDK with its Agent and Cursor replaced, its error classes real. */
function fakeSdk(error: Error, run = failingRun(error)): typeof sdk {
  let model: sdk.ModelSelection | undefined;
  const agent = {
    agentId: 'bc-1',
    get model() {
      return model;
    },
    close: () => undefined,
    listArtifacts: () => Promise.reject(error),
    send: (_message: unknown, options?: sdk.SendOptions) => {
      model = options?.model;

      return Promise.resolve(run);
    },
  };

  return {
    ...sdk,
    Agent: {
      create: () => Promise.resolve(agent),
      resume: () => Promise.reject(error),
      list: () => Promise.reject(error),
      listRuns: () => Promise.resolve({ items: [run], nextCursor: 'c2' }),
    },
    Cursor: {
      me: () => Promise.reject(error),
      models: { list: () => Promise.reject(error) },
      auth: {
        login: () => Promise.reject(error),
        logout: () => Promise.reject(error),
        status: () => Promise.reject(error),
      },
    },
  } as unknown as typeof sdk;
}

describe("the Port throws the adapter's errors from every call", () => {
  const error = new sdk.NetworkError('Service unavailable');
  const port = cursorPort(fakeSdk(error));
  const network = { kind: 'network', message: 'Service unavailable' };

  test('its own calls', async () => {
    await expect(port.me({ apiKey: 'k' })).rejects.toMatchObject(network);
    await expect(port.models({ apiKey: 'k' })).rejects.toMatchObject(network);
    await expect(port.login({})).rejects.toMatchObject(network);
    await expect(port.logout({})).rejects.toMatchObject(network);
    await expect(port.status({})).rejects.toMatchObject(network);
    await expect(port.resume('bc-1', { apiKey: 'k' })).rejects.toMatchObject(
      network,
    );
    await expect(
      port.list({ runtime: 'cloud', apiKey: 'k' }),
    ).rejects.toMatchObject(network);
  });

  test("an agent's and its run's, the stream after what it yielded", async () => {
    const agent = await port.create({ apiKey: 'k' });

    await expect(agent.listArtifacts()).rejects.toMatchObject(network);

    const run = await agent.send('hi');
    const seen: unknown[] = [];

    expect(run).toMatchObject({ id: 'run-1', agentId: 'bc-1' });
    await expect(
      (async () => {
        for await (const message of run.stream()) {
          seen.push(message);
        }
      })(),
    ).rejects.toMatchObject(network);
    expect(seen).toEqual([{ type: 'status', status: 'RUNNING' }]);
    await expect(run.wait()).rejects.toMatchObject(network);
    await expect(run.cancel()).rejects.toMatchObject(network);
    await expect(run.conversation()).rejects.toMatchObject(network);
  });

  test("the runs it lists, and the agent's model as the SDK last set it", async () => {
    const { items, nextCursor } = await port.listRuns('bc-1', {
      runtime: 'cloud',
      apiKey: 'k',
    });

    expect(nextCursor).toBe('c2');
    await expect(items[0]!.wait()).rejects.toMatchObject(network);

    const agent = await port.create({ apiKey: 'k' });

    expect(agent.model).toBeUndefined();
    await agent.send('hi', { model: { id: 'composer-2' } });
    expect(agent.model).toEqual({ id: 'composer-2' });
  });
});

describe('CHD-622 tester: error boundaries', () => {
  test.each([
    ['auth', new sdk.AuthenticationError('Agent is archived')],
    ['network', new sdk.NetworkError('Invalid API key')],
    [
      'other',
      new sdk.ConfigurationError('Agent is archived', {
        code: 'invalid_model',
      }),
    ],
    [
      'archived',
      new sdk.ConfigurationError('Invalid API key', {
        code: 'agent_archived',
      }),
    ],
  ] as const)(
    '%s is decided without interpreting the message',
    (kind, error) => {
      expect(normalise(error)).toMatchObject({
        kind,
        message: error.message,
        cause: error,
      });
    },
  );

  test('normalises a failed create, list-runs and send without retrying', async () => {
    const error = new sdk.RateLimitError('Try later', {
      code: 'rate_limited',
      requestId: 'req-limit',
    });
    const from = fakeSdk(error);
    let attempts = 0;
    const fail = () => {
      attempts += 1;

      return Promise.reject(error);
    };

    const port = cursorPort({
      ...from,
      Agent: {
        ...from.Agent,
        create: fail,
        listRuns: fail,
        resume: () =>
          Promise.resolve({
            agentId: 'bc-1',
            send: fail,
          }),
      },
    } as unknown as typeof sdk);
    const expected = {
      kind: 'rate-limit',
      message: 'Try later',
      code: 'rate_limited',
      requestId: 'req-limit',
      cause: error,
    };

    await expect(port.create({ apiKey: 'fixture-key' })).rejects.toMatchObject(
      expected,
    );
    await expect(
      port.listRuns('bc-1', { apiKey: 'fixture-key', runtime: 'cloud' }),
    ).rejects.toMatchObject(expected);

    const agent = await port.resume('bc-1', { apiKey: 'fixture-key' });

    await expect(agent.send('hello')).rejects.toMatchObject(expected);
    expect(attempts).toBe(3);
  });

  test('an unknown rejection keeps its identity through a Port call', async () => {
    const error = new Error('Invalid API key');
    const port = cursorPort(fakeSdk(error));

    await expect(port.me({ apiKey: 'fixture-key' })).rejects.toBe(error);
  });
});
