import { expect, test } from 'bun:test';
import {
  refusedByAgentNote,
  refusedNote,
  renamedNote,
  renamingNote,
  unnamedNote,
} from '../../../src/ui/app/rename.ts';

test("each target /rename refuses is said in the design's words, as an error", () => {
  expect(refusedNote({ kind: 'starting' })).toStrictEqual({
    text: 'The session is not open yet; rename it once it is.',
    failed: true,
  });
  expect(refusedNote({ kind: 'exited', name: 'parser' })).toStrictEqual({
    text: 'parser has exited; its session cannot be renamed.',
    failed: true,
  });
  expect(refusedNote({ kind: 'task', name: 'main' })).toStrictEqual({
    text: 'main is a task; it keeps the title it was given.',
    failed: true,
  });
  expect(
    refusedNote({ kind: 'open', key: 1, agent: 'claude', conversation: {} }),
  ).toBeUndefined();
});

test('with no title, how to name it, and the title it has when it has one', () => {
  expect(unnamedNote(undefined)).toStrictEqual({
    text: 'Name the session: /rename <title>',
    failed: false,
  });
  expect(unnamedNote('Fix\nthe   parser')).toStrictEqual({
    text: 'Name the session: /rename <title>. Now: Fix the parser',
    failed: false,
  });
});

test("in flight, taken by the agent, kept in chord alone, or refused in the agent's words", () => {
  expect(renamingNote('Parser test tidy-up')).toStrictEqual({
    text: 'Renaming to Parser test tidy-up…',
    failed: false,
  });
  expect(renamedNote('Parser test tidy-up', 'claude', true)).toStrictEqual({
    text: 'Renamed to Parser test tidy-up',
    failed: false,
  });
  expect(renamedNote('Parser test tidy-up', 'cursor', false)).toStrictEqual({
    text: 'Renamed to Parser test tidy-up in chord only: cursor takes no title, and its own may replace it',
    failed: false,
  });
  expect(
    refusedByAgentNote('claude', 'Session title cannot be empty'),
  ).toStrictEqual({
    text: 'Could not rename: claude refused it: Session title cannot be empty',
    failed: true,
  });
});

test("an agent's title and words are drawn cleaned: its escapes gone, on one line", () => {
  expect(
    renamedNote('\u001b[31mRed\u001b[0m\ntitle', 'claude', true).text,
  ).toBe('Renamed to Red title');
});
