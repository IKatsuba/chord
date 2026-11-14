import { expect, test } from 'bun:test';
import type { Notice } from '@agentclientprotocol/sdk/unstable';
import type {
  Transcript,
  TranscriptAction,
} from '../../../src/session/transcript/types.ts';
import { fold } from './fold.ts';

function notice(
  fields: Notice,
  turnId = 't1',
  subagentId?: string,
): TranscriptAction {
  return {
    type: 'update',
    turnId,
    update: { sessionUpdate: 'notice', ...fields },
    ...(subagentId === undefined ? {} : { subagentId }),
  };
}

function chunk(text: string): TranscriptAction {
  return {
    type: 'update',
    turnId: 't1',
    update: {
      sessionUpdate: 'agent_message_chunk',
      content: { type: 'text', text },
    },
  };
}

const PROMPT: TranscriptAction = {
  type: 'prompt',
  turnId: 't1',
  text: 'go',
  at: 0,
};

function kinds({ entries }: Transcript): string[] {
  return entries.map((entry) => entry.kind);
}

test('a notice in a turn is an entry of its own that closes the reply block, the next chunk opening another', () => {
  const state = fold([
    PROMPT,
    chunk('Running the suite. '),
    notice({
      severity: 'warning',
      title: 'Fast mode turned off',
      description: 'Rate limit reached.',
    }),
    chunk('Done.'),
  ]);

  expect(state.entries).toStrictEqual([
    { kind: 'user', turnId: 't1', text: 'go' },
    { kind: 'assistant', turnId: 't1', text: 'Running the suite. ' },
    {
      kind: 'notice',
      turnId: 't1',
      severity: 'warning',
      title: 'Fast mode turned off',
      description: 'Rate limit reached.',
    },
    { kind: 'assistant', turnId: 't1', text: 'Done.' },
  ]);
});

test('two notices alike are two entries: notices carry no id and are never merged', () => {
  const twice = notice({ severity: 'info', title: 'Same' });

  expect(kinds(fold([PROMPT, twice, twice]))).toStrictEqual([
    'user',
    'notice',
    'notice',
  ]);
});

test('a severity the schema leaves open draws as info; a description null or empty is none', () => {
  const { entries } = fold([
    PROMPT,
    notice({ severity: 'critical', title: 'Odd', description: null }),
    notice({ severity: 'error', title: 'Bad', description: '' }),
  ]);

  expect(entries.slice(1)).toStrictEqual([
    { kind: 'notice', turnId: 't1', severity: 'info', title: 'Odd' },
    { kind: 'notice', turnId: 't1', severity: 'error', title: 'Bad' },
  ]);
});

test('a notice after the turn was answered, or before any turn, is drawn under the turn id it came with', () => {
  const after = fold([
    PROMPT,
    chunk('Done.'),
    {
      type: 'result',
      turnId: 't1',
      result: { status: 'completed', stopReason: 'end_turn' },
    },
    notice({ severity: 'info', title: 'Later' }),
  ]);

  expect(after.entries.at(-1)).toStrictEqual({
    kind: 'notice',
    turnId: 't1',
    severity: 'info',
    title: 'Later',
  });
  expect(
    fold([notice({ severity: 'warning', title: 'Early' }, 'start')]).entries,
  ).toStrictEqual([
    { kind: 'notice', turnId: 'start', severity: 'warning', title: 'Early' },
  ]);
});

test("a subagent's notice goes into that subagent's entries, not its parent's", () => {
  const state = fold([
    PROMPT,
    {
      type: 'update',
      turnId: 't1',
      update: {
        sessionUpdate: 'subagent_update',
        sessionId: 'a',
        title: 'Watch',
        state: { state: 'running' },
      },
    },
    notice({ severity: 'info', title: 'From the child' }, 't1', 'a'),
  ]);
  const child = state.entries.find((entry) => entry.kind === 'subagent');

  expect(kinds(state)).toStrictEqual(['user', 'subagent']);
  expect(
    child?.kind === 'subagent' ? child.subagent.entries : undefined,
  ).toStrictEqual([
    { kind: 'notice', turnId: 't1', severity: 'info', title: 'From the child' },
  ]);
});
