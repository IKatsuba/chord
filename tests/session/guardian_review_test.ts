import { expect, test } from 'bun:test';
import assert from 'node:assert/strict';
import type { SessionUpdate } from '@agentclientprotocol/sdk';
import { guardianReview } from '../../src/session/guardian_review.ts';
import { FILLED, GUARDIAN_REVIEW } from '../../src/session/enrich.ts';

test('Guardian reading is pure and repeatable for recorded updates already enriched', () => {
  const update: SessionUpdate = {
    sessionUpdate: 'tool_call_update',
    toolCallId: 'guardian_assessment:review',
    rawOutput: { review: { status: 'approved' } },
    _meta: { own: true },
  };
  const read = guardianReview(update);

  assert(read.sessionUpdate === 'tool_call_update');
  expect(read._meta).toStrictEqual({
    own: true,
    [FILLED]: [GUARDIAN_REVIEW],
    [GUARDIAN_REVIEW]: 'approved',
  });
  expect(guardianReview(read)).toStrictEqual(read);
  expect(update._meta).toStrictEqual({ own: true });
  expect(read.rawOutput).toBe(update.rawOutput);
});
