import { describe, expect, test } from 'bun:test';
import process from 'node:process';
import { agentStart } from '../../src/agents.ts';
import { openAgent } from '../../src/acp/connection.ts';
import { FAKE_PROVIDER_ENV, fakeProvider } from '../../src/riff/serve.ts';
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

  test('runs a turn on the fake provider in its own process', async () => {
    const fake = serveFakeChat();
    const said: string[] = [];
    const agent = await openAgent({
      command: agentStart('riff').command,
      env: { [FAKE_PROVIDER_ENV]: fake.url },
      cwd: process.cwd(),
      onTraffic: (traffic) => {
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
    } finally {
      await agent.close();
      await fake.stop();
    }
  });
});
