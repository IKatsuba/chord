/** A review hold asks once, without creating a session grant. */
import type { ToolCallUpdate } from '@agentclientprotocol/sdk/unstable';
import type { PermissionReview } from '../../session/permission_review.ts';
import { ALLOW, DENY } from '../tools/permission.ts';
import type { ToolSession } from '../tools/tools.ts';
import type { AutoReview } from './admission.ts';

export const REVIEW_ASK_MS = 5 * 60_000;

type HeldReview = Exclude<AutoReview, { readonly outcome: 'clear' }>;

/** Adapted from vercel-labs/fx v0.0.16 tool_result_errors.zig, Apache-2.0;
 * chord adds the person's decision and its timeout to the held-action messages.
 */
function heldMessage(outcome: HeldReview): string {
  switch (outcome.outcome) {
    case 'caution':
      return 'Action held after safety review. Use the review advice to choose a materially different safe action, or explain why no safe path remains.';
    case 'incomplete':
      return 'Action held because the evidence is incomplete; reduce the action or supporting evidence to fit the review limits, or choose a materially different fully inspectable action.';
    case 'unavailable':
      return 'Safety reviewer unavailable; action held. Continue with a different safe action or retry later.';
  }
}

export async function reviewedPermission(
  session: ToolSession,
  toolCall: ToolCallUpdate,
  outcome: HeldReview,
  signal: AbortSignal,
): Promise<void> {
  signal.throwIfAborted();

  const deadline = new AbortController();
  const deadlineAt = Date.now() + REVIEW_ASK_MS;
  const timer = setTimeout(() => deadline.abort(), REVIEW_ASK_MS);
  const active = AbortSignal.any([signal, deadline.signal]);
  const review: PermissionReview = {
    outcome: outcome.outcome === 'unavailable' ? 'failed' : outcome.outcome,
    reason: outcome.outcome === 'caution' ? outcome.rationale : outcome.reason,
  };

  try {
    const chosen = await session.ask?.(
      toolCall,
      [
        { optionId: ALLOW, name: 'Allow once', kind: 'allow_once' },
        { optionId: DENY, name: 'Deny', kind: 'reject_once' },
      ],
      active,
      { 'chord/permission': { review, deadlineAt } },
    );

    signal.throwIfAborted();

    const timedOut = deadline.signal.aborted || Date.now() >= deadlineAt;

    if (chosen === ALLOW && !timedOut) {
      return;
    }

    const reason = timedOut
      ? 'Denied: no answer within 5 minutes.'
      : chosen === DENY
        ? 'The person denied this call.'
        : 'Nobody answered the permission ask; the call did not run.';

    throw new Error(`${reason}\n${heldMessage(outcome)}\n${review.reason}`);
  } finally {
    clearTimeout(timer);
  }
}
