/** A generic agent review hold, including headless denial despite allow-all. */
import type { Play, Turn } from '../turn.ts';
import type { RequestPermissionResponse } from '@agentclientprotocol/sdk/unstable';

async function reviewed(
  turn: Turn,
  outcome: 'caution' | 'incomplete' | 'failed',
) {
  const toolCall = {
    toolCallId: turn.callId('review'),
    title: 'Run a reviewed action',
    kind: 'execute' as const,
    status: 'pending' as const,
  };

  await turn.send({ sessionUpdate: 'tool_call', ...toolCall });

  const response = await turn.client.request<RequestPermissionResponse>(
    'session/request_permission',
    {
      sessionId: turn.sessionId,
      toolCall,
      options: [
        { optionId: 'allow', name: 'Allow once', kind: 'allow_once' },
        { optionId: 'deny', name: 'Deny', kind: 'reject_once' },
      ],
      _meta: {
        'chord/permission': {
          review: {
            outcome,
            reason:
              outcome === 'caution'
                ? 'Fixture safety review: caution.'
                : outcome === 'incomplete'
                  ? 'The proposed action exceeded the review input limit.'
                  : 'the reviewer did not answer in 30 s',
          },
          deadlineAt: Date.now() + 300_000,
        },
      },
    },
    { cancellationSignal: turn.signal },
  );
  const answer =
    response.outcome.outcome === 'selected'
      ? response.outcome.optionId
      : 'cancelled';

  await turn.say(`Review permission: ${answer}.`);

  return 'end_turn' as const;
}

export const REVIEW_PERMISSIONS = {
  reviewpermission: (turn) => reviewed(turn, 'caution'),
  reviewincomplete: (turn) => reviewed(turn, 'incomplete'),
  reviewfailed: (turn) => reviewed(turn, 'failed'),
} satisfies Record<string, Play>;
