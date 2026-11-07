/**
 * What a transport has to survive: a turn that fails, a chunk after the
 * answer, and what ACP does not have.
 */
import * as acp from '@agentclientprotocol/sdk/unstable';
import { STEP_MS } from '../options.ts';
import { strayCancels } from '../sessions.ts';
import { lifetime, pause, type Play } from '../turn.ts';

const FLOOD_CHUNK = 64 * 1024;
const FLOOD_BYTES = 64 * 1024 * 1024;

export const MISBEHAVING = {
  // More than any pipe holds, as fast as chord takes it, for a client that
  // stopped reading; a cancel or the client's going ends it.
  async flood(turn) {
    const chunk = 'x'.repeat(FLOOD_CHUNK);

    for (let sent = 0; sent < FLOOD_BYTES; sent += FLOOD_CHUNK) {
      if (turn.signal.aborted || lifetime.signal.aborted) {
        return 'cancelled';
      }

      await turn.say(chunk);
    }

    return 'end_turn';
  },

  // A cancel changes nothing: the prompt stays open until the client goes, or
  // 30 s, so a test that never closes it fails rather than hangs.
  async ignorescancel(turn) {
    await turn.say('Holding on.');
    await pause(lifetime.signal, 30_000).catch(() => {});

    return 'end_turn';
  },

  // How many cancels came with no turn playing.
  async cancels(turn) {
    await turn.say(
      `Cancels with no turn: ${strayCancels.get(turn.sessionId) ?? 0}.`,
    );

    return 'end_turn';
  },

  async error(turn) {
    await turn.say('About to fail.');
    await pause(turn.signal);

    throw new acp.RequestError(-32603, 'The fake agent failed on purpose.');
  },

  // An update after the answer, as some adapters send their last chunks or
  // their usage once `session/prompt` has been answered.
  async late(turn) {
    await turn.say('Answered.');

    setTimeout(
      () =>
        void turn.client
          .notify('session/update', {
            sessionId: turn.sessionId,
            update: {
              sessionUpdate: 'agent_message_chunk',
              content: { type: 'text', text: ' Late, after the answer.' },
            },
          })
          .catch(() => {}),
      STEP_MS * 4,
    );

    return 'end_turn';
  },

  // What no schema chord knows has: an update of a kind ACP may add later,
  // and a notification of the agent's own.
  async unknown(turn) {
    await turn.client.notify('session/update', {
      sessionId: turn.sessionId,
      update: { sessionUpdate: 'future_update', detail: 'from later' },
    });
    await turn.client.notify('_fake/notice', { text: 'an extension' });
    await turn.say('Sent the unknown.');

    return 'end_turn';
  },
} satisfies Record<string, Play>;
