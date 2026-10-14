/** Elicitations: a form to fill in and a link to open. */
import * as acp from '@agentclientprotocol/sdk';
import { FORM_SCHEMA, LINK_URL } from '../../forms.ts';
import { type Play, type Turn } from '../turn.ts';

/**
 * Asks the client for input and says what came back: the action, and an
 * accepted form's content as one line of JSON.
 */
async function elicit(
  turn: Turn,
  request: acp.CreateElicitationRequest,
): Promise<acp.StopReason> {
  const answer = await turn.client.request('elicitation/create', request);

  // The client answers `cancel` for a turn being cancelled; the turn ends so.
  if (turn.signal.aborted) {
    return 'cancelled';
  }

  // A link accepted is done once the person has been there, which only the
  // agent learns; it says so, as ACP's `elicitation/complete`.
  if (request.mode === 'url' && answer.action === 'accept') {
    await turn.client.notify('elicitation/complete', {
      elicitationId: request.elicitationId,
    });
  }

  // A hard break, so the content starts a line of its own.
  const content =
    answer.action === 'accept' && answer.content
      ? `  \n${JSON.stringify(answer.content)}`
      : '';

  await turn.say(`Elicitation answer: ${answer.action}${content}`);

  return 'end_turn';
}

export const FORMS = {
  // A form with a field of each kind, then what came back, so a capture
  // shows the round trip.
  async form(turn) {
    return await elicit(turn, {
      sessionId: turn.sessionId,
      mode: 'form',
      message: 'Set up the deploy target',
      requestedSchema: FORM_SCHEMA,
    });
  },

  // A link to open; the client opens nothing without a key press.
  async link(turn) {
    return await elicit(turn, {
      sessionId: turn.sessionId,
      mode: 'url',
      elicitationId: turn.callId('link'),
      message: 'Sign in to Example to continue',
      url: LINK_URL,
    });
  },
} satisfies Record<string, Play>;
