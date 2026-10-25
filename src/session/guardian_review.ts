import type { SessionUpdate } from '@agentclientprotocol/sdk';
import { GUARDIAN_REVIEW, markFilled, recordOf } from './enrich.ts';

/**
 * codex-acp v2.2.2's GuardianReporter names reviews `guardian_assessment:`
 * followed by their id, and sends `rawInput.review.status` on a tool_call,
 * `rawOutput.review.status` on an update, including a completed review that
 * arrives as an opening call. File only that structured string, never its
 * rendered text, for live traffic and records written before this reader.
 * Missing ids or statuses leave the ordinary block; unknown statuses do too.
 * A missing status on an update leaves the last one read by the transcript.
 */
export function guardianReview(update: SessionUpdate): SessionUpdate {
  if (
    (update.sessionUpdate !== 'tool_call' &&
      update.sessionUpdate !== 'tool_call_update') ||
    typeof update.toolCallId !== 'string' ||
    !update.toolCallId.startsWith('guardian_assessment:') ||
    update.toolCallId === 'guardian_assessment:'
  ) {
    return update;
  }

  const raw = recordOf(
    update.sessionUpdate === 'tool_call' ? update.rawInput : update.rawOutput,
  );
  const { status } = recordOf(raw.review);

  if (typeof status !== 'string') {
    return update;
  }

  return {
    ...update,
    _meta: {
      ...markFilled(update._meta, [GUARDIAN_REVIEW]),
      [GUARDIAN_REVIEW]: status,
    },
  };
}
