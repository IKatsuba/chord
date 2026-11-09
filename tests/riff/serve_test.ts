import { describe, expect, test } from 'bun:test';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import process from 'node:process';
import { agentStart } from '../../src/agents.ts';
import { openAgent } from '../../src/acp/connection.ts';
import { BACKEND_ENV, riffBackend } from '../../src/riff/serve.ts';
import { FAKE_PROVIDER_ENV, fakeProvider } from '../../src/riff/start.ts';
import { HELLO, serveFakeChat } from '../fixtures/riff/fake_chat.ts';

const STOP = { exitMs: 300, termMs: 300, killMs: 2000 } as const;

describe('chord --riff-agent', () => {
  test('takes the fake provider from its environment alone', () => {
    expect(fakeProvider({})).toBeUndefined();
    expect(fakeProvider({ [FAKE_PROVIDER_ENV]: '' })).toBeUndefined();
    expect(
      fakeProvider({ [FAKE_PROVIDER_ENV]: 'http://localhost:1/v1' }),
    ).toStrictEqual({
      baseUrl: 'http://localhost:1/v1',
    });
  });

  test('turns the native addon off only for wasm', () => {
    const base = { backend: 'auto' as const };

    expect(riffBackend(base, {})).toBe(base);
    expect(riffBackend(base, { [BACKEND_ENV]: 'native' })).toBe(base);
    expect(riffBackend(base, { [BACKEND_ENV]: 'wasm' })).toStrictEqual({
      backend: 'auto',
      nativeAddon: false,
    });
  });

  test.each([
    [undefined, 'native'],
    ['wasm', 'wasm-jspi'],
  ])(
    'runs a turn in its own process, backend %p, and names %p on stderr',
    async (chosen, backend) => {
      const fake = serveFakeChat();
      const state = await mkdtemp(join(tmpdir(), 'chord-riff-'));
      const said: string[] = [];
      let stderr = '';
      const agent = await openAgent({
        command: agentStart('riff').command,
        env: {
          [FAKE_PROVIDER_ENV]: fake.url,
          XDG_STATE_HOME: state,
          ...(chosen === undefined ? {} : { [BACKEND_ENV]: chosen }),
        },
        cwd: process.cwd(),
        onTraffic: (traffic) => {
          if (traffic.from === 'stderr') {
            stderr += traffic.text;
          }

          if (traffic.from === 'agent') {
            const update = (
              traffic.message as {
                params?: {
                  update?: {
                    sessionUpdate?: string;
                    content?: { text?: string };
                  };
                };
              }
            ).params?.update;

            if (update?.sessionUpdate === 'agent_message_chunk') {
              said.push(update.content?.text ?? '');
            }
          }
        },
        onPermission: () =>
          Promise.resolve({ outcome: { outcome: 'cancelled' } }),
        onElicitation: () => Promise.resolve({ action: 'decline' }),
        stop: STOP,
      });

      try {
        const { sessionId } = await agent.newSession({
          cwd: process.cwd(),
          mcpServers: [],
        });
        const answer = await agent.prompt({
          sessionId,
          prompt: [{ type: 'text', text: 'hello' }],
        });

        expect(answer.stopReason).toBe('end_turn');
        expect(said.join('')).toBe(HELLO);
        expect(fake.requests).toHaveLength(1);
        expect(stderr).toContain(`riff: backend ${backend}\n`);
      } finally {
        await agent.close();
        await fake.stop();
        await rm(state, { recursive: true, force: true });
      }
    },
  );
});
