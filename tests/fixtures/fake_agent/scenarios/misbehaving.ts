/**
 * What a transport has to survive: a turn that fails, a chunk after the
 * answer, and what ACP does not have.
 */
import * as acp from '@agentclientprotocol/sdk';
import { STEP_MS } from '../options.ts';
import { strayCancels } from '../sessions.ts';
import { pause, type Play } from '../turn.ts';

export const MISBEHAVING = {
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
