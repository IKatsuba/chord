/**
 * An agent's own cycles after its turn has ended (CHD-426): Claude Code's
 * when a background task ends, its end only a usage update of an autonomous
 * origin, and codebuddy's unasked turn, marked at both ends.
 */
import type * as acp from '@agentclientprotocol/sdk';
import { COST_FROM, CYCLE_COST } from '../options.ts';
import { costs } from '../sessions.ts';
import { type Client, lifetime, pause, type Play, type Turn } from '../turn.ts';

/**
 * Longer than chord waits for a turn's tail to go quiet, so what follows is
 * the agent's own and not the turn's.
 */
const QUIET = 1500;

/** Between one part of a cycle and the next. */
const STEP = 200;

/** Where a cycle's updates go: the client, and the session they are of. */
type To = Pick<Turn, 'client' | 'sessionId'>;

/** Sends `update` to the session with no turn running. */
function send(to: To, update: unknown): Promise<void> {
  return to.client.notify('session/update', {
    sessionId: to.sessionId,
    update: update as acp.SessionUpdate,
  });
}

function say(to: To, text: string): Promise<void> {
  return send(to, {
    sessionUpdate: 'agent_message_chunk',
    content: { type: 'text', text },
  });
}

/**
 * The usage update that ends a Claude cycle, as claude-agent-acp 0.93 sends
 * it, of a `task-notification` origin; with `--cycle-cost`, the session's
 * cost so far with the cycle's added (CHD-373).
 */
function cycleUsage(sessionId: string): acp.SessionUpdate {
  const cost =
    CYCLE_COST === undefined
      ? undefined
      : (costs.get(sessionId) ?? COST_FROM) + CYCLE_COST;

  if (cost !== undefined) {
    costs.set(sessionId, cost);
  }

  return {
    sessionUpdate: 'usage_update',
    used: 1200,
    size: 200000,
    ...(cost === undefined ? {} : { cost: { amount: cost, currency: 'USD' } }),
    _meta: { '_claude/origin': { kind: 'task-notification' } },
  };
}

/**
 * A Claude cycle with no turn before it, once the session has gone quiet,
 * ended by its usage: what `--cycle-on-resume` runs in a session resumed.
 */
export function runCycle(client: Client, sessionId: string): void {
  const to = { client, sessionId };

  void (async () => {
    try {
      await pause(lifetime.signal, QUIET);
      await say(to, 'A background task ended while you were away.');
      await pause(lifetime.signal, STEP);
      await send(to, cycleUsage(sessionId));
    } catch {
      // The client went first.
    }
  })();
}

/**
 * Ends the turn, then, once it has gone quiet, works on its own as Claude
 * Code does when a background task ends; with `usage` it ends that cycle as
 * claude-agent-acp 0.93.0 does, with a usage update whose `_claude/origin`
 * is `task-notification`, and without it the cycle is never marked ended.
 */
function claudeCycle(usage: boolean): Play {
  return async (turn) => {
    void (async () => {
      try {
        await pause(lifetime.signal, QUIET);
        await say(turn, 'The background build ended; reading its log.');
        await pause(lifetime.signal, STEP);
        await say(turn, ' The build passed.');

        if (usage) {
          await pause(lifetime.signal, STEP);
          await send(turn, cycleUsage(turn.sessionId));
        }
      } catch {
        // The client went first.
      }
    })();

    await turn.say('The build runs in the background; I will read it after.');

    return 'end_turn';
  };
}

export const CYCLES = {
  claudecycle: claudeCycle(true),
  claudecyclebare: claudeCycle(false),

  // As claudecycle, the cycle asking to write a file before it ends, and
  // saying which option came back.
  async claudecycleask(turn) {
    void (async () => {
      try {
        await pause(lifetime.signal, QUIET);
        await say(turn, 'The background build ended; saving its log.');

        const toolCall = {
          toolCallId: turn.callId('write'),
          title: 'Write notes/build.md',
          kind: 'edit' as const,
          status: 'pending' as const,
          locations: [{ path: 'notes/build.md' }],
        };

        await send(turn, { sessionUpdate: 'tool_call', ...toolCall });

        const answer: acp.RequestPermissionResponse = await turn.client.request(
          'session/request_permission',
          {
            sessionId: turn.sessionId,
            toolCall,
            options: [
              { optionId: 'allow', name: 'Allow', kind: 'allow_once' },
              { optionId: 'deny', name: 'Deny', kind: 'reject_once' },
            ],
          },
        );
        const chosen =
          answer.outcome.outcome === 'selected'
            ? answer.outcome.optionId
            : 'cancelled';

        await say(turn, `Permission: ${chosen}.`);
        await pause(lifetime.signal, STEP);
        await send(turn, cycleUsage(turn.sessionId));
      } catch {
        // The client went first.
      }
    })();

    await turn.say('The build runs in the background; I will read it after.');

    return 'end_turn';
  },

  // Ends the turn, then runs an unasked turn as codebuddy does once a
  // background task drains: marked at its start by
  // `_meta["codebuddy.ai/unsolicitedTurn"]` and at its end by the
  // `session_end` update ACP does not have.
  async codebuddycycle(turn) {
    void (async () => {
      try {
        await pause(lifetime.signal, STEP);
        await send(turn, {
          sessionUpdate: 'session_info_update',
          _meta: {
            'codebuddy.ai/unsolicitedTurn': {
              requestId: 'unasked-1',
              reason: 'background_drain',
            },
          },
        });
        await pause(lifetime.signal, STEP);
        await say(turn, 'The background task drained; all checks are green.');
        await pause(lifetime.signal, STEP);
        await send(turn, { sessionUpdate: 'session_end' });
      } catch {
        // The client went first.
      }
    })();

    await turn.say('The checks run in the background.');

    return 'end_turn';
  },
} satisfies Record<string, Play>;
