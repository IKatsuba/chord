import { expect, test } from 'bun:test';
import { cutNote, cutSentence } from '../../src/session/cut_off.ts';

test('a cut send_message names its recipient and quotes its first line, cut at 60 characters', () => {
  expect(
    cutSentence({
      tool: 'send_message',
      input: {
        to: 'main',
        text: 'CHD-393: the owner has a question on Q8, with the options for the headline:\n\n1. Wrap it.',
      },
    }),
  ).toStrictEqual(
    'Your send_message to @main was cut off before it reached chord and was not delivered ("CHD-393: the owner has a question on Q8, with the options fo…"). Send it again, on its own.',
  );
  // A child's, to the agent that started it, names main, as its row does.
  expect(
    cutSentence({ tool: 'send_message', input: { text: 'Found it.' } }),
  ).toStrictEqual(
    'Your send_message to @main was cut off before it reached chord and was not delivered ("Found it."). Send it again, on its own.',
  );
  expect(
    cutSentence({ tool: 'send_message', input: { to: 'tester', text: ' ' } }),
  ).toStrictEqual(
    'Your send_message to @tester was cut off before it reached chord and was not delivered. Send it again, on its own.',
  );
});

test('any other cut call names its tool, and several are a line each, in order', () => {
  const open = { tool: 'open_agent', input: { name: 'parser' } } as const;

  expect(cutSentence(open)).toStrictEqual(
    'Your open_agent call was cut off before it reached chord and did nothing. Call it again if you still need it, on its own.',
  );
  expect(
    cutNote([
      { tool: 'send_message', input: { to: 'main', text: 'Hi' } },
      open,
    ]).split('\n'),
  ).toStrictEqual([
    cutSentence({ tool: 'send_message', input: { to: 'main', text: 'Hi' } }),
    cutSentence(open),
  ]);
});
