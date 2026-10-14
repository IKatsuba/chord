import { expect, test } from 'bun:test';
import assert from 'node:assert/strict';
import { OUTPUT_LIMIT } from '../../../src/session/context.ts';
import { reduceTranscript } from '../../../src/session/transcript/reducer.ts';
import {
  emptyTranscript,
  type TranscriptAction,
} from '../../../src/session/transcript/types.ts';

test('a shell run gathers its output until it ends, then keeps still', () => {
  const actions: TranscriptAction[] = [
    { type: 'shell_started', turnId: 's1', command: 'ls' },
    { type: 'shell_output', turnId: 's1', stream: 'stdout', text: 'a\n' },
    { type: 'shell_output', turnId: 's1', stream: 'stderr', text: 'oops\n' },
    { type: 'shell_output', turnId: 's1', stream: 'stdout', text: 'b\n' },
    { type: 'shell_ended', turnId: 's1', code: 2 },
    // Late, and for a run the transcript never had.
    { type: 'shell_output', turnId: 's1', stream: 'stdout', text: 'late' },
    { type: 'shell_ended', turnId: 's2', stopped: true },
  ];
  const transcript = actions.reduce(reduceTranscript, emptyTranscript);

  expect(transcript.entries).toStrictEqual([
    {
      kind: 'shell',
      turnId: 's1',
      run: {
        command: 'ls',
        stdout: 'a\nb\n',
        stderr: 'oops\n',
        running: false,
        code: 2,
      },
    },
  ]);
  expect(transcript.turn).toStrictEqual({ status: 'idle' });
});

test('a shell run keeps no more than the limit of each stream', () => {
  const big = 'x'.repeat(OUTPUT_LIMIT - 1);
  const transcript = (
    [
      { type: 'shell_started', turnId: 's1', command: 'yes' },
      { type: 'shell_output', turnId: 's1', stream: 'stdout', text: big },
      { type: 'shell_output', turnId: 's1', stream: 'stdout', text: 'yz' },
      { type: 'shell_output', turnId: 's1', stream: 'stdout', text: 'more' },
    ] as const
  ).reduce(reduceTranscript, emptyTranscript);
  const [entry] = transcript.entries;

  assert(entry?.kind === 'shell');
  expect(entry.run.stdout).toStrictEqual(`${big}y`);
  expect(entry.run.truncated).toStrictEqual(true);
});
