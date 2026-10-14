/**
 * Compactions as Claude's and Codex's adapters run them, and one that fails.
 */
import * as acp from '@agentclientprotocol/sdk';
import { COMPACT_ERROR, COMPACT_SUMMARY } from '../../compactions.ts';
import { clientTakesCompaction } from '../client.ts';
import { STEP_MS } from '../options.ts';
import { pause, type Play, type Turn } from '../turn.ts';

/**
 * How long a compaction takes between chunks of its summary: 50 steps, a
 * quarter of a second by default, so `compact` runs for about 2 s.
 */
const COMPACT_STEP_MS = STEP_MS * 50;

/**
 * A compaction as both adapters run one: by id to a client that takes it,
 * the `chunks` of its summary streamed while it runs, then `ending`; to any
 * other, as the tool call they fall back on. Interrupted, it is cancelled,
 * as Claude's adapter ends one its turn left open.
 */
async function compact(
  turn: Turn,
  chunks: readonly string[],
  ending: { status: 'completed' } | { status: 'failed'; error: string },
): Promise<acp.StopReason> {
  const compactionId = turn.callId('compaction');

  if (!clientTakesCompaction) {
    await turn.send({
      sessionUpdate: 'tool_call',
      toolCallId: compactionId,
      title: 'Compact conversation',
      kind: 'think',
      status: 'in_progress',
    });
    await pause(turn.signal, COMPACT_STEP_MS * Math.max(chunks.length, 4));
    await turn.send({
      sessionUpdate: 'tool_call_update',
      toolCallId: compactionId,
      status: ending.status,
    });

    return 'end_turn';
  }

  await turn.send({
    sessionUpdate: 'compaction_update',
    compactionId,
    status: 'in_progress',
  });

  try {
    for (const text of chunks) {
      await pause(turn.signal, COMPACT_STEP_MS);
      await turn.send({
        sessionUpdate: 'compaction_summary_chunk',
        compactionId,
        content: { type: 'text', text },
      });
    }

    await pause(turn.signal, COMPACT_STEP_MS * (chunks.length === 0 ? 8 : 1));
  } catch (error) {
    await turn.client.notify('session/update', {
      sessionId: turn.sessionId,
      update: {
        sessionUpdate: 'compaction_update',
        compactionId,
        status: 'cancelled',
      },
    });

    throw error;
  }

  await turn.send({
    sessionUpdate: 'compaction_update',
    compactionId,
    ...ending,
  });

  return 'end_turn';
}

export const COMPACTION = {
  async compact(turn) {
    return await compact(turn, COMPACT_SUMMARY, { status: 'completed' });
  },

  async codexcompact(turn) {
    return await compact(turn, [], { status: 'completed' });
  },

  async compactfail(turn) {
    return await compact(turn, [], { status: 'failed', error: COMPACT_ERROR });
  },
} satisfies Record<string, Play>;
