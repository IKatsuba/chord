import { expect, test } from 'bun:test';
import type {
  Compaction,
  Entry,
  TurnState,
} from '../../../src/session/transcript/types.ts';
import {
  compactionLine,
  inSpinner,
} from '../../../src/ui/transcript/compaction.ts';

const base: Compaction = { id: 'k1', status: 'in_progress', summary: '' };

test('a compaction that runs reads as Claude Code says it', () => {
  expect(compactionLine(base, false, 'ctrl+o')).toStrictEqual({
    text: 'Compacting conversation…',
    tone: 'running',
  });
  // A status ACP may add later is not taken for an ending.
  expect(
    compactionLine({ ...base, status: 'paused' }, false, 'ctrl+o').tone,
  ).toStrictEqual('running');
});

test('a completed compaction names the key to its summary only while there is one to see', () => {
  const done = { ...base, status: 'completed', summary: 'Kept this.' };

  expect(compactionLine(done, false, 'ctrl+o')).toStrictEqual({
    text: 'Conversation compacted (ctrl+o for history)',
    tone: 'done',
  });
  expect(compactionLine(done, true, 'ctrl+o').text).toStrictEqual(
    'Conversation compacted',
  );
  expect(compactionLine(done, false, undefined).text).toStrictEqual(
    'Conversation compacted',
  );
  // Codex's adapter sends no summary.
  expect(
    compactionLine({ ...done, summary: '' }, false, 'ctrl+o').text,
  ).toStrictEqual('Conversation compacted');
});

test('a failed or cancelled compaction says so', () => {
  expect(
    compactionLine(
      { ...base, status: 'failed', error: 'Not enough messages.\n' },
      false,
      'ctrl+o',
    ),
  ).toStrictEqual({
    text: 'Compaction failed: Not enough messages.',
    tone: 'failed',
  });
  expect(
    compactionLine({ ...base, status: 'failed' }, false, 'ctrl+o').text,
  ).toStrictEqual('Compaction failed');
  expect(
    compactionLine({ ...base, status: 'cancelled' }, false, 'ctrl+o'),
  ).toStrictEqual({ text: 'Compaction cancelled', tone: 'failed' });
});

test('a compaction running in the turn that is goes to the spinner, any other stays in the transcript', () => {
  const working: TurnState = { status: 'working', turnId: 't2', since: 0 };
  const entry = (turnId: string, status: string): Entry => ({
    kind: 'compaction',
    turnId,
    compaction: { ...base, status },
  });

  expect(inSpinner(entry('t2', 'in_progress'), working)).toStrictEqual(true);
  // No spinner outside a turn, so the transcript says it.
  expect(
    inSpinner(entry('t2', 'in_progress'), { status: 'idle' }),
  ).toStrictEqual(false);
  // One a past turn left unended is not this turn's work.
  expect(inSpinner(entry('t1', 'in_progress'), working)).toStrictEqual(false);
  // An ended one is the transcript's line.
  expect(inSpinner(entry('t2', 'completed'), working)).toStrictEqual(false);
  expect(
    inSpinner({ kind: 'user', turnId: 't2', text: 'hi' }, working),
  ).toStrictEqual(false);
});
