import { expect, test } from 'bun:test';
import type { SessionUpdate } from '@agentclientprotocol/sdk';
import type {
  Transcript,
  TranscriptAction,
} from '../../../src/session/transcript/types.ts';
import { fold, states } from './fold.ts';

function compactionUpdate(
  update: Omit<
    Extract<SessionUpdate, { sessionUpdate: 'compaction_update' }>,
    'sessionUpdate'
  >,
): TranscriptAction {
  return {
    type: 'update',
    turnId: 't1',
    update: { sessionUpdate: 'compaction_update', ...update },
  };
}

function summaryChunk(compactionId: string, text: string): TranscriptAction {
  return {
    type: 'update',
    turnId: 't1',
    update: {
      sessionUpdate: 'compaction_summary_chunk',
      compactionId,
      content: { type: 'text', text },
    },
  };
}

function compactionsOf({ entries }: Transcript) {
  return entries.flatMap((entry) =>
    entry.kind === 'compaction' ? [entry.compaction] : [],
  );
}

test("a compaction is one entry by its id, its summary built from chunks, as Claude's adapter sends it", () => {
  const actions: TranscriptAction[] = [
    { type: 'prompt', turnId: 't1', text: '/compact', at: 0 },
    compactionUpdate({ compactionId: 'k1', status: 'in_progress' }),
    summaryChunk('k1', 'Read the '),
    summaryChunk('k1', 'README.'),
    compactionUpdate({ compactionId: 'k1', status: 'completed' }),
  ];
  const seen = states(actions);

  expect(compactionsOf(seen[1]!)).toStrictEqual([
    { id: 'k1', status: 'in_progress', summary: '' },
  ]);
  expect(compactionsOf(seen[3]!)).toStrictEqual([
    { id: 'k1', status: 'in_progress', summary: 'Read the README.' },
  ]);
  expect(fold(actions).entries).toStrictEqual([
    { kind: 'user', turnId: 't1', text: '/compact' },
    {
      kind: 'compaction',
      turnId: 't1',
      compaction: {
        id: 'k1',
        status: 'completed',
        summary: 'Read the README.',
      },
    },
  ]);
});

test('a summary sent whole replaces the chunks, and null or [] clears it', () => {
  const start = [
    compactionUpdate({ compactionId: 'k1', status: 'in_progress' }),
    summaryChunk('k1', 'raw <summary>'),
  ];

  expect(
    compactionsOf(
      fold([
        ...start,
        compactionUpdate({
          compactionId: 'k1',
          status: 'completed',
          summary: [
            { type: 'text', text: 'Clean' },
            {
              type: 'text',
              text: ' summary.',
            },
          ],
        }),
      ]),
    )[0]?.summary,
  ).toStrictEqual('Clean summary.');

  for (const summary of [null, []]) {
    expect(
      compactionsOf(
        fold([
          ...start,
          compactionUpdate({
            compactionId: 'k1',
            status: 'completed',
            summary,
          }),
        ]),
      )[0]?.summary,
    ).toStrictEqual('');
  }
});

test('a failed compaction keeps its error, and a later update without one leaves it', () => {
  const failed = fold([
    compactionUpdate({ compactionId: 'k1', status: 'in_progress' }),
    compactionUpdate({
      compactionId: 'k1',
      status: 'failed',
      error: 'Not enough messages to compact.',
    }),
    // A duplicate of the terminal update, as Claude's adapter can send.
    compactionUpdate({ compactionId: 'k1', status: 'failed' }),
  ]);

  expect(compactionsOf(failed)).toStrictEqual([
    {
      id: 'k1',
      status: 'failed',
      summary: '',
      error: 'Not enough messages to compact.',
    },
  ]);
  expect(
    compactionsOf(
      fold(
        [
          compactionUpdate({
            compactionId: 'k1',
            status: 'failed',
            error: null,
          }),
        ],
        failed,
      ),
    )[0]?.error,
  ).toStrictEqual(undefined);
});

test('a compaction whose first update is its last, as one replayed, still gets its entry', () => {
  expect(
    fold([
      compactionUpdate({
        compactionId: 'k1',
        status: 'completed',
        summary: [{ type: 'text', text: 'Done.' }],
      }),
    ]).entries,
  ).toStrictEqual([
    {
      kind: 'compaction',
      turnId: 't1',
      compaction: { id: 'k1', status: 'completed', summary: 'Done.' },
    },
  ]);
});

test('a chunk for no compaction is dropped, and two compactions keep apart', () => {
  const state = fold([
    summaryChunk('k0', 'stray'),
    compactionUpdate({ compactionId: 'k1', status: 'in_progress' }),
    compactionUpdate({ compactionId: 'k2', status: 'in_progress' }),
    summaryChunk('k1', 'one'),
    summaryChunk('k2', 'two'),
    compactionUpdate({ compactionId: 'k1', status: 'cancelled' }),
  ]);

  expect(compactionsOf(state)).toStrictEqual([
    { id: 'k1', status: 'cancelled', summary: 'one' },
    { id: 'k2', status: 'in_progress', summary: 'two' },
  ]);
});
