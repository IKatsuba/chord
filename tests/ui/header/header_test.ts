import { expect, test } from 'bun:test';
import {
  type HeaderFacts,
  type HeaderLine,
  headerLines,
  MARK_WIDTH,
  markColour,
  textWidth,
} from '../../../src/ui/header/header.ts';
import type { MarkStops } from '../../../src/ui/header/mark_rows.ts';
import { PALETTES, PLAIN } from '../../../src/ui/theme/theme.ts';

const NOW = Date.parse('2026-10-08T12:00:00.000Z');
const HOUR = 60 * 60 * 1000;

const FACTS: HeaderFacts = {
  version: '0.0.0',
  agent: 'claude',
  directory: '~/src/app',
  helpKey: '?',
};

/** The lines as text, the bold runs in `*`. */
function texts(lines: readonly HeaderLine[]): string[] {
  return lines.map((line) =>
    line.map(({ text, bold }) => (bold ? `*${text}*` : text)).join(''),
  );
}

test('the mark is 4 columns at every size, and the text 3 after it', () => {
  expect(MARK_WIDTH).toStrictEqual(4);
  // Inside the transcript's padding on both sides.
  expect(textWidth(120)).toStrictEqual(120 - 2 - 4 - 3);
  expect(textWidth(44)).toStrictEqual(44 - 2 - 4 - 3);
});

test('the mark is the gradient at 256 colours and more, one tone at 16, and none without colour', () => {
  const dark = PALETTES.dark.mark;

  expect(markColour(dark, 3)).toStrictEqual({
    level: 'truecolor',
    stops: ['#89f5b3', '#47e7a5', '#15c7a2'],
  });
  expect(markColour(dark, 2)).toStrictEqual({
    level: '256',
    stops: ['#89f5b3', '#47e7a5', '#15c7a2'],
  });
  expect(markColour(dark, 1)).toStrictEqual({
    level: '16',
    tone: 'greenBright',
  });
  expect(markColour(dark, 0)).toStrictEqual({ level: 'none' });
  expect(markColour(PLAIN.mark, 3)).toStrictEqual({ level: 'none' });
});

test('light themes take the darker stops, and the 16-colour themes one tone at any level', () => {
  const light: MarkStops = ['#1e9a5e', '#147d55', '#0a5e57'];

  expect(markColour(PALETTES.light.mark, 3)).toStrictEqual({
    level: 'truecolor',
    stops: light,
  });
  expect(markColour(PALETTES['light-daltonized'].mark, 2)).toStrictEqual({
    level: '256',
    stops: light,
  });
  expect(markColour(PALETTES.light.mark, 1)).toStrictEqual({
    level: '16',
    tone: 'green',
  });
  expect(markColour(PALETTES['dark-daltonized'].mark, 3)).toStrictEqual({
    level: 'truecolor',
    stops: ['#89f5b3', '#47e7a5', '#15c7a2'],
  });
  expect(markColour(PALETTES['dark-ansi'].mark, 3)).toStrictEqual({
    level: '16',
    tone: 'greenBright',
  });
  expect(markColour(PALETTES['light-ansi'].mark, 3)).toStrictEqual({
    level: '16',
    tone: 'green',
  });
});

test('a fresh session says chord, the agent, the directory and the keys', () => {
  expect(texts(headerLines(FACTS, 80, NOW))).toStrictEqual([
    '*chord* v0.0.0',
    'claude',
    '~/src/app',
    '? for shortcuts · /help',
  ]);
});

test('the hint names the key the help is bound to, and only /help when none is', () => {
  expect(
    texts(headerLines({ ...FACTS, helpKey: 'h' }, 80, NOW))[3],
  ).toStrictEqual('h for shortcuts · /help');
  expect(
    texts(headerLines({ ...FACTS, helpKey: undefined }, 80, NOW))[3],
  ).toStrictEqual('/help');
});

test('the model joins the agent once it is known', () => {
  expect(
    texts(headerLines({ ...FACTS, model: 'Sonnet 4.5' }, 80, NOW))[1],
  ).toStrictEqual('claude · Sonnet 4.5');
});

test('the directory is cut from the left at a separator', () => {
  const lines = headerLines(
    { ...FACTS, directory: '~/projects/someone/chord' },
    16,
    NOW,
  );

  expect(texts(lines)[2]).toStrictEqual('…/someone/chord');
});

test('a resumed session says when it was last used and its first prompt', () => {
  const lines = headerLines(
    {
      ...FACTS,
      resumed: { lastUsedAt: NOW - 2 * HOUR, title: 'fix the parser' },
    },
    80,
    NOW,
  );

  expect(texts(lines).length).toStrictEqual(5);
  expect(texts(lines)[4]).toStrictEqual(
    'resumed · 2 hours ago · fix the parser',
  );
});

test('a resumed session says only what is known of it', () => {
  expect(
    texts(headerLines({ ...FACTS, resumed: {} }, 80, NOW))[4],
  ).toStrictEqual('resumed');
  expect(
    texts(headerLines({ ...FACTS, resumed: { title: 'hello' } }, 80, NOW))[4],
  ).toStrictEqual('resumed · hello');
});

test("an agent's own title for a resumed session wraps under its own start at its spaces, a path moved whole, where a first prompt is cut (CHD-445)", () => {
  const title =
    'Find out why the tokenizer drops the closing quote, write a test in tests/parse/tokenize_test.ts that fails';
  const lines = (titled: boolean) =>
    texts(
      headerLines(
        {
          ...FACTS,
          resumed: { lastUsedAt: NOW - 2 * HOUR, title, titled },
        },
        50,
        NOW,
      ),
    ).slice(4);

  expect(lines(true)).toStrictEqual([
    'resumed · 2 hours ago · Find out why the tokenizer',
    'drops the closing quote, write a test in',
    'tests/parse/tokenize_test.ts that fails',
  ]);
  expect(lines(false)).toStrictEqual([`resumed · 2 hours ago · ${title}`]);
});
