import { afterEach, beforeEach, describe, expect, test } from 'bun:test';
import {
  DONE,
  type FakeChat,
  NEEDLE,
  NEEDLE_FILE,
  serveFakeChat,
} from '../../../../scripts/dev/release/fake_chat.ts';

let fake: FakeChat;

beforeEach(() => {
  fake = serveFakeChat();
});

afterEach(async () => {
  await fake.stop();
});

describe('the fake chat server', () => {
  test('calls search, then read, then says done, by the tool results it is given, counting requests', async () => {
    const ask = async (results: number) => {
      const answer = await fetch(`${fake.url}/chat/completions`, {
        method: 'POST',
        body: JSON.stringify({
          messages: [
            { role: 'user', content: 'go' },
            ...Array.from({ length: results }, () => ({ role: 'tool' })),
          ],
        }),
      });

      return await answer.text();
    };

    const call = (name: string, args: object) =>
      `"name":"${name}","arguments":${JSON.stringify(JSON.stringify(args))}`;

    expect(await ask(0)).toContain(call('search', { query: NEEDLE }));
    expect(await ask(1)).toContain(call('read', { path: NEEDLE_FILE }));
    expect(await ask(2)).toContain(`"content":"${DONE}"`);
    expect(fake.requests()).toBe(3);
  });

  test('answers nothing but chat completions', async () => {
    const answer = await fetch(`${fake.url}/models`);

    expect(answer.status).toBe(404);
    expect(fake.requests()).toBe(0);
  });
});
