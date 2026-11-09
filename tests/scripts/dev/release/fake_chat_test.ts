import { afterEach, beforeEach, describe, expect, test } from 'bun:test';
import {
  ECHOED,
  type FakeChat,
  serveFakeChat,
} from '../../../../scripts/dev/release/fake_chat.ts';

let fake: FakeChat;

beforeEach(() => {
  fake = serveFakeChat();
});

afterEach(async () => {
  await fake.stop();
});

/** The streamed answer to `messages`, as one string. */
async function ask(messages: object[]): Promise<string> {
  const answer = await fetch(`${fake.url}/chat/completions`, {
    method: 'POST',
    body: JSON.stringify({ messages }),
  });

  return answer.text();
}

describe('the fake chat server', () => {
  test('calls echo first, then says done for its result, counting requests', async () => {
    expect(await ask([{ role: 'user', content: 'go' }])).toContain(
      '"name":"echo"',
    );
    expect(
      await ask([
        { role: 'user', content: 'go' },
        { role: 'tool', content: ECHOED, tool_call_id: 'call_selftest' },
      ]),
    ).toContain('"content":"done"');
    expect(fake.requests()).toBe(2);
  });

  test('a failed tool call never gets done', async () => {
    const answer = await ask([
      { role: 'user', content: 'go' },
      { role: 'tool', content: 'Error: boom', tool_call_id: 'call_selftest' },
    ]);

    expect(answer).not.toContain('"content":"done"');
    expect(answer).toContain('echo did not run');
  });
});
