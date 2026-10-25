import { describe, expect, test } from 'bun:test';
import assert from 'node:assert/strict';
import type { SessionUpdate } from '@agentclientprotocol/sdk';
import { guardianReview } from '../../src/session/guardian_review.ts';
import { FILLED, GUARDIAN_REVIEW } from '../../src/session/enrich.ts';
import { recordActions, type RecordEntry } from '../../src/session/record.ts';
import { reduceTranscript } from '../../src/session/transcript/reducer.ts';
import { emptyTranscript } from '../../src/session/transcript/types.ts';

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

describe('CHD-521 U1 tester: structured fallback and independent review lifetimes', () => {
  test('odd raw shapes never borrow an Approved content label, and string statuses stay exact', () => {
    for (const opening of [true, false]) {
      for (const raw of [
        undefined,
        null,
        [],
        'approved',
        { review: [] },
        { review: 'approved' },
        { review: { status: false } },
        { review: { status: 1 } },
        { review: { status: ['approved'] } },
        { review: { status: { value: 'approved' } } },
      ]) {
        const update: SessionUpdate = {
          sessionUpdate: opening ? 'tool_call' : 'tool_call_update',
          toolCallId: 'guardian_assessment:odd-shape',
          title: 'Guardian Review',
          ...(opening ? { rawInput: raw } : { rawOutput: raw }),
          content: [
            {
              type: 'content',
              content: { type: 'text', text: 'Status: Approved' },
            },
          ],
        };

        expect(guardianReview(update)).toBe(update);
      }

      for (const status of ['', 'Approved', ' approved', 'futureStatus']) {
        const update: SessionUpdate = {
          sessionUpdate: opening ? 'tool_call' : 'tool_call_update',
          toolCallId: 'guardian_assessment:exact-status',
          title: 'Guardian Review',
          ...(opening
            ? { rawInput: { review: { status } } }
            : { rawOutput: { review: { status } } }),
        };

        expect(guardianReview(update)._meta?.[GUARDIAN_REVIEW]).toBe(status);
      }
    }
  });

  test('interleaved old records retain each review verdict across malformed updates without mutating raw data', () => {
    const updates: SessionUpdate[] = [
      ...['first', 'second'].map((id): SessionUpdate => ({
        sessionUpdate: 'tool_call',
        toolCallId: `guardian_assessment:${id}`,
        title: 'Guardian Review',
        status: 'in_progress',
        rawInput: { review: { status: 'inProgress' } },
      })),
      {
        sessionUpdate: 'tool_call_update',
        toolCallId: 'guardian_assessment:second',
        rawOutput: { review: { status: 'approved' } },
      },
      {
        sessionUpdate: 'tool_call_update',
        toolCallId: 'guardian_assessment:first',
        rawOutput: { review: { status: 'denied' } },
      },
      ...['first', 'second'].map((id): SessionUpdate => ({
        sessionUpdate: 'tool_call_update',
        toolCallId: `guardian_assessment:${id}`,
        status: 'completed',
        rawOutput: { review: { status: null } },
      })),
    ];
    const original = structuredClone(updates);
    const entries: RecordEntry[] = updates.map((update) => ({
      type: 'update',
      turnId: 'reviews',
      update,
    }));
    let transcript = emptyTranscript;

    for (const action of recordActions(entries)) {
      if (action.type !== 'usage') {
        transcript = reduceTranscript(transcript, action);
      }
    }

    const calls = transcript.entries.flatMap((entry) =>
      entry.kind === 'tool' ? [entry.call] : [],
    );

    expect(calls.map((call) => [call.id, call.guardian])).toEqual([
      ['guardian_assessment:first', 'denied'],
      ['guardian_assessment:second', 'approved'],
    ]);
    expect(calls.map((call) => call.rawOutput)).toEqual([
      { review: { status: null } },
      { review: { status: null } },
    ]);
    expect(updates).toEqual(original);
  });
});
