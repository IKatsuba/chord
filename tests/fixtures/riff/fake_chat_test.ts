import { afterEach, describe, expect, test } from 'bun:test';
import { type FakeChat, serveFakeChat } from './fake_chat.ts';

let fake: FakeChat | undefined;

afterEach(async () => {
  await fake?.stop();
});

/** What the fake streams back to `messages`, as one string. */
async function asked(
  messages: { role: string; content?: string }[],
  tools: string[] = [],
): Promise<string> {
  const response = await fetch(`${fake!.url}/chat/completions`, {
    method: 'POST',
    body: JSON.stringify({
      messages,
      tools: tools.map((name) => ({ function: { name } })),
    }),
  });

  return await response.text();
}

describe('the fake chat server playing a scene (CHD-611)', () => {
  test('its calls one per request after the person speaks, then its reply, whatever was typed', async () => {
    fake = serveFakeChat({
      calls: [
        { name: 'edit', arguments: { path: 'a.ts' } },
        { name: 'shell', arguments: { command: 'bun test' } },
      ],
      reply: 'Renamed and tested.',
    });

    const prompt = { role: 'user', content: 'hang on, call it fail' };

    expect(await asked([prompt])).toContain('"name":"edit"');
    expect(await asked([prompt, { role: 'tool', content: 'ok' }])).toContain(
      '"name":"shell"',
    );
    expect(
      await asked([
        prompt,
        { role: 'tool', content: 'ok' },
        { role: 'tool', content: 'ok' },
      ]),
    ).toContain('Renamed and tested.');
    // A new prompt starts the scene again.
    expect(
      await asked([
        prompt,
        { role: 'tool' },
        { role: 'tool' },
        { role: 'assistant' },
        { role: 'user', content: 'again' },
      ]),
    ).toContain('"name":"edit"');
  });

  test("the scene's review verdict holds over the pending action's marker", async () => {
    fake = serveFakeChat({ calls: [], reply: 'x', review: 'clear' });

    expect(
      await asked(
        [
          {
            role: 'user',
            content: '<normalized_action>rm -rf build</normalized_action>',
          },
        ],
        ['permission_decision'],
      ),
    ).toContain('\\"decision\\":\\"clear\\"');
  });
});
