import { expect, test } from 'bun:test';
import type { Entry, Subagent } from '../../../src/session/transcript/types.ts';
import { type AskerPart, askerParts } from '../../../src/ui/dialogs/asker.ts';

function block(subagent: Subagent): Entry {
  return { kind: 'subagent', turnId: 't', subagent };
}

const TASK: Subagent = {
  id: 'task-1',
  title: 'Fix the tokenizer',
  state: 'running',
  entries: [],
  plan: [],
  task: { name: 'Fix the tokenizer', runtime: 'fake', model: 'fake-small' },
};

const ENTRIES = [block(TASK)];

const DOCS = { name: 'docs', colour: '#6cb6ff' };

/** The parts as one line, to read at once. */
function said(parts: readonly AskerPart[]): string {
  return parts.map((part) => part.text).join('');
}

test('main is named by its runtime in a turn, by main between turns, and not at all where nothing names it', () => {
  expect(askerParts({ entries: [], runtime: 'claude' })).toStrictEqual([
    { text: 'claude', tone: 'plain' },
  ]);
  expect(
    askerParts({ entries: [], runtime: 'claude', between: true }),
  ).toStrictEqual([{ text: 'main', tone: 'plain', bold: true }]);
  // Its permission box names nobody in a turn.
  expect(askerParts({ entries: [] })).toStrictEqual([]);
});

test('a task is named as its call is headed, in the accent colour, in a turn or between', () => {
  for (const between of [false, true]) {
    const parts = askerParts({
      entries: ENTRIES,
      subagentId: 'task-1',
      between,
      runtime: 'fake',
    });

    expect(said(parts)).toStrictEqual('Agent(Fix the tokenizer) · fake');
    expect(parts.every((part) => part.tone === 'accent')).toBeTrue();
    expect(parts.find((part) => part.bold)?.text).toStrictEqual('Agent');
  }
});

test('a subagent chord drew nothing of is one of whoever asks, between turns', () => {
  expect(
    askerParts({ entries: [], subagentId: 'gone', between: true }),
  ).toStrictEqual([{ text: 'a subagent of main', tone: 'accent' }]);
  expect(
    said(
      askerParts({
        entries: [],
        subagentId: 'gone',
        between: true,
        picked: DOCS,
      }),
    ),
  ).toStrictEqual('a subagent of docs');
});

test('a child is named bold in its colour; a member with its team after, dim', () => {
  expect(
    askerParts({ entries: [], picked: DOCS, runtime: 'fake' }),
  ).toStrictEqual([
    { text: 'docs', tone: 'agent', bold: true, colour: '#6cb6ff' },
  ]);
  expect(
    askerParts({
      entries: [],
      picked: { name: 'tester', colour: '#c49cff', team: 'bugfix' },
      runtime: 'fake',
      between: true,
    }),
  ).toStrictEqual([
    { text: 'tester', tone: 'agent', bold: true, colour: '#c49cff' },
    { text: ' · bugfix', tone: 'dim' },
  ]);
});
