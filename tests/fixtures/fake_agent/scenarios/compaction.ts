/**
 * Compactions as Claude's and Codex's adapters run them, one that fails,
 * and Claude's own of an idle session (CHD-624).
 */
import { existsSync } from 'node:fs';
import { join } from 'node:path';
import * as acp from '@agentclientprotocol/sdk/unstable';
import { COMPACT_ERROR, COMPACT_SUMMARY } from '../../compactions.ts';
import { clientTakesCompaction } from '../client.ts';
import { COST_FROM, STEP_MS } from '../options.ts';
import { costs, cwds } from '../sessions.ts';
import { lifetime, pause, type Play, type Turn } from '../turn.ts';
import { GATE, GATE_RELEASE } from './agents.ts';

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

/**
 * Longer than chord waits for a turn's tail to go quiet, so the compaction
 * comes with nothing of chord's under way.
 */
const IDLE_QUIET = 1500;

/** How long an idle compaction runs with no gate to hold it. */
const IDLE_RUN_MS = 6000;

/** What an idle compaction adds to the session's cost, in USD. */
const IDLE_COMPACT_COST = 0.04;

/** The chunk `idlecompactsays` sends after its compaction, untagged. */
export const IDLE_CHUNK = 'Conversation compacted.';

/**
 * Each session's idle compaction while it runs: a prompt waits for it, as
 * claude-agent-acp queues a prompt behind its own `/compact`, and a cancel
 * of that prompt cancels it.
 */
const idle = new Map<
  string,
  { readonly done: Promise<void>; readonly stop: AbortController }
>();

/**
 * Waits for `sessionId`'s idle compaction, if one runs, and cancels it if
 * `signal` does first.
 */
export async function afterIdleCompaction(
  sessionId: string,
  signal: AbortSignal,
): Promise<void> {
  const running = idle.get(sessionId);

  if (running === undefined) {
    return;
  }

  const stop = () => running.stop.abort();

  signal.addEventListener('abort', stop, { once: true });

  try {
    await running.done;
  } finally {
    signal.removeEventListener('abort', stop);
  }
}

/**
 * Holds a running idle compaction: until `<cwd>/.fake-gate/release`, at most
 * 10 s, where the gate is, so a test can act while it runs; else for a while.
 */
async function held(sessionId: string, signal: AbortSignal): Promise<void> {
  const gate = join(cwds.get(sessionId) ?? '.', GATE);

  if (!existsSync(gate)) {
    await pause(signal, IDLE_RUN_MS);

    return;
  }

  const deadline = performance.now() + 10_000;

  while (
    !existsSync(join(gate, GATE_RELEASE)) &&
    performance.now() < deadline
  ) {
    await pause(signal, STEP_MS * 2);
  }
}

/**
 * Ends the turn with a line, then, once it has gone quiet, compacts as
 * claude-agent-acp 0.107 does an idle session: `compaction_update`s with no
 * request open, the summary streamed, then the context's usage twice, the
 * second with the cost. With `says`, an untagged chunk 1.2 s after.
 */
function idleCompact(
  ending: { status: 'completed' } | { status: 'failed'; error: string },
  says = false,
): Play {
  return async (turn) => {
    const { client, sessionId } = turn;
    const send = (update: acp.SessionUpdate) =>
      client.notify('session/update', { sessionId, update });

    void (async () => {
      try {
        await turn.over;
        await pause(lifetime.signal, IDLE_QUIET);
      } catch {
        return;
      }

      const compactionId = crypto.randomUUID();
      const stop = new AbortController();
      const signal = AbortSignal.any([lifetime.signal, stop.signal]);
      const done = Promise.withResolvers<void>();

      idle.set(sessionId, { done: done.promise, stop });

      try {
        await send({
          sessionUpdate: 'compaction_update',
          compactionId,
          status: 'in_progress',
        });

        try {
          if (ending.status === 'completed') {
            for (const text of COMPACT_SUMMARY) {
              await send({
                sessionUpdate: 'compaction_summary_chunk',
                compactionId,
                content: { type: 'text', text },
              });
            }
          }

          await held(sessionId, signal);
        } catch {
          if (!lifetime.signal.aborted) {
            await send({
              sessionUpdate: 'compaction_update',
              compactionId,
              status: 'cancelled',
            });
          }

          return;
        }

        await send({
          sessionUpdate: 'compaction_update',
          compactionId,
          ...ending,
        });

        if (ending.status === 'completed') {
          const cost = (costs.get(sessionId) ?? COST_FROM) + IDLE_COMPACT_COST;

          costs.set(sessionId, cost);
          await send({
            sessionUpdate: 'usage_update',
            used: 41200,
            size: 1000000,
          });
          await send({
            sessionUpdate: 'usage_update',
            used: 41200,
            size: 1000000,
            cost: { amount: cost, currency: 'USD' },
          });
        }

        if (says) {
          await pause(lifetime.signal, 1200);
          await send({
            sessionUpdate: 'agent_message_chunk',
            content: { type: 'text', text: IDLE_CHUNK },
          });
        }
      } catch {
        // The client went first.
      } finally {
        idle.delete(sessionId);
        done.resolve();
      }
    })();

    await turn.say('Done: three tests merged into one table, all green.');

    return 'end_turn';
  };
}

export const IDLE_COMPACTION = {
  idlecompact: idleCompact({ status: 'completed' }),
  idlecompactfail: idleCompact({ status: 'failed', error: COMPACT_ERROR }),
  idlecompactsays: idleCompact({ status: 'completed' }, true),
} satisfies Record<string, Play>;
