import { expect, test } from 'bun:test';
import {
  chordHeadline,
  chordLines,
} from '../../../../src/ui/transcript/tools/chord.ts';

test('close_agent names what it closed, and a task already ended says so (CHD-590)', () => {
  const closed = {
    tool: 'close_agent' as const,
    input: { to: 'a1' },
    answer: { closed: 'Watch the build' },
  };
  const ended = { ...closed, answer: { ended: 'Watch the build' } };

  expect(chordHeadline(closed)).toStrictEqual({
    name: 'Close',
    arg: 'Watch the build',
  });
  expect(chordLines(closed)).toStrictEqual(['Closed']);
  expect(chordHeadline(ended)).toStrictEqual({
    name: 'Close',
    arg: 'Watch the build',
  });
  expect(chordLines(ended)).toStrictEqual(['Already ended']);
});
