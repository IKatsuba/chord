import { describe, expect, test } from 'bun:test';
import process from 'node:process';
import manifest from '../../package.json' with { type: 'json' };
import { agentStart, findAgent, listAgents } from '../../src/agents.ts';
import { openAgent } from '../../src/acp/connection.ts';
import { riffInit } from '../../src/riff/adapter.ts';
import {
  FAKE_MODELS_ENV,
  FAKE_PROVIDER_ENV,
  fakeProvider,
  RIFF_AGENT_FLAG,
} from '../../src/riff/start.ts';

const STOP = { exitMs: 300, termMs: 300, killMs: 2000 } as const;

describe('riff started by name', () => {
  test('agentStart runs chord itself with the hidden flag, from source', () => {
    const { command, env } = agentStart('riff');

    expect(command).toStrictEqual([
      process.execPath,
      expect.stringMatching(/src[/\\]main\.tsx$/),
      RIFF_AGENT_FLAG,
    ]);
    expect(env).toStrictEqual({});
  });

  test('is listed first without a fake provider now that it can sign in', () => {
    expect(findAgent('riff', {})?.runner).toBe('builtin');
    expect(listAgents({})[0]?.name).toBe('riff');
  });

  test("--riff-agent answers initialize with the design's answer", async () => {
    const agent = await openAgent({
      command: agentStart('riff').command,
      env: { [FAKE_PROVIDER_ENV]: 'http://localhost:1/v1' },
      cwd: process.cwd(),
      onTraffic: () => {},
      onPermission: () =>
        Promise.resolve({ outcome: { outcome: 'cancelled' } }),
      onElicitation: () => Promise.resolve({ action: 'decline' }),
      stop: STOP,
    });

    try {
      expect(agent.init).toStrictEqual(riffInit(manifest.version));
      expect(agent.steering).toBe(false);
    } finally {
      await agent.close();
    }
  });
});

describe('tester: riff startup protocol contract', () => {
  test('the child advertises the literal initialize contract without steering', async () => {
    const agent = await openAgent({
      command: agentStart('riff').command,
      env: { [FAKE_PROVIDER_ENV]: 'http://localhost:1/v1' },
      cwd: process.cwd(),
      onTraffic: () => {},
      onPermission: () =>
        Promise.resolve({ outcome: { outcome: 'cancelled' } }),
      onElicitation: () => Promise.resolve({ action: 'decline' }),
      stop: STOP,
    });

    try {
      expect(agent.init).toStrictEqual({
        protocolVersion: 1,
        _meta: { steering: { supported: false } },
        agentInfo: { name: 'riff', title: 'riff', version: manifest.version },
        authMethods: [
          {
            id: 'chatgpt',
            name: 'ChatGPT plan',
            description: 'Sign in to ChatGPT in chord',
          },
          {
            id: 'grok',
            name: 'Grok plan',
            description: 'Sign in to Grok in chord',
          },
        ],
        agentCapabilities: {
          loadSession: false,
          promptCapabilities: {
            image: true,
            audio: false,
            embeddedContext: true,
          },
          mcpCapabilities: { http: true, sse: false },
          sessionCapabilities: { resume: {}, close: {} },
        },
      });
      expect(agent.steering).toBe(false);
    } finally {
      await agent.close();
    }
  });
});

describe("the fake provider's model list (CHD-611)", () => {
  test('beside the fake provider, it names the plan whose list it presents', () => {
    expect(
      fakeProvider({
        [FAKE_PROVIDER_ENV]: 'http://localhost:1/v1',
        [FAKE_MODELS_ENV]: 'codex',
      }),
    ).toEqual({ baseUrl: 'http://localhost:1/v1', models: 'codex' });
    expect(
      fakeProvider({ [FAKE_PROVIDER_ENV]: 'http://localhost:1/v1' }),
    ).toEqual({ baseUrl: 'http://localhost:1/v1' });
  });

  test('outside --fake and --qa it is ignored', () => {
    expect(fakeProvider({ [FAKE_MODELS_ENV]: 'codex' })).toBeUndefined();
    expect(
      fakeProvider({ [FAKE_PROVIDER_ENV]: '', [FAKE_MODELS_ENV]: 'grok' }),
    ).toBeUndefined();
  });

  test('a name that is no plan is refused', () => {
    expect(() =>
      fakeProvider({
        [FAKE_PROVIDER_ENV]: 'http://localhost:1/v1',
        [FAKE_MODELS_ENV]: 'gpt-6.1-sol',
      }),
    ).toThrow('CHORD_RIFF_FAKE_MODELS takes codex or grok, not gpt-6.1-sol');
  });
});
