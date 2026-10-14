/** A compaction the agent ran, by its id, with the summary it kept. */
import type { SessionUpdate } from '@agentclientprotocol/sdk';
import { textOf } from './messages.ts';
import type { Compaction, Transcript } from './types.ts';

/**
 * A compaction where its first update put it, each later update patching it
 * in place as ACP says: a `summary` or `error` left out keeps what was there,
 * `null` clears it. The first update may already be the last, as when an
 * agent replays a compaction that is over. A chunk for a compaction never
 * opened is dropped, as ACP sends none before one.
 */
export function mergeCompaction(
  state: Transcript,
  turnId: string,
  update: Extract<
    SessionUpdate,
    { sessionUpdate: 'compaction_update' | 'compaction_summary_chunk' }
  >,
): Transcript {
  const index = state.entries.findLastIndex(
    (entry) =>
      entry.kind === 'compaction' &&
      entry.compaction.id === update.compactionId,
  );
  const found = state.entries[index];

  if (update.sessionUpdate === 'compaction_summary_chunk') {
    const text = textOf(update.content);

    if (found?.kind !== 'compaction' || text === '') {
      return state;
    }

    const entries = [...state.entries];

    entries[index] = {
      ...found,
      compaction: {
        ...found.compaction,
        summary: found.compaction.summary + text,
      },
    };

    return { ...state, entries };
  }

  const before: Compaction =
    found?.kind === 'compaction'
      ? found.compaction
      : { id: update.compactionId, status: update.status, summary: '' };
  const { error: _, ...kept } = before;
  const error = update.error === undefined ? before.error : update.error;
  const compaction: Compaction = {
    ...kept,
    status: update.status,
    ...(update.summary === undefined
      ? {}
      : { summary: (update.summary ?? []).map(textOf).join('') }),
    ...(error === null || error === undefined ? {} : { error }),
  };

  if (found?.kind !== 'compaction') {
    return {
      ...state,
      entries: [...state.entries, { kind: 'compaction', turnId, compaction }],
    };
  }

  const entries = [...state.entries];

  entries[index] = { ...found, compaction };

  return { ...state, entries };
}
