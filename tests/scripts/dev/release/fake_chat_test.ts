import { afterEach, beforeEach, describe, expect, test } from 'bun:test';
import {
  DONE,
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

describe('the fake chat server', () => {
  test('says done to every request, counting them', async () => {
    for (let i = 0; i < 2; i++) {
      const answer = await fetch(`${fake.url}/chat/completions`, {
        method: 'POST',
        body: JSON.stringify({ messages: [{ role: 'user', content: 'go' }] }),
      });

      expect(await answer.text()).toContain(`"content":"${DONE}"`);
    }

    expect(fake.requests()).toBe(2);
  });

  test('answers nothing but chat completions', async () => {
    const answer = await fetch(`${fake.url}/models`);

    expect(answer.status).toBe(404);
    expect(fake.requests()).toBe(0);
  });
});
