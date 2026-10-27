import { describe, expect, test } from 'bun:test';
import assert from 'node:assert/strict';
import {
  freezeSelection,
  selectionReceipt,
} from '../../../src/session/team_selection.ts';
import { reduceTranscript } from '../../../src/session/transcript/reducer.ts';
import {
  emptyTranscript,
  type ChordCall,
} from '../../../src/session/transcript/types.ts';
import { recordedReceipts } from '../../../src/ui/teams/recorded_receipts.ts';

function call(id = 'actual-id'): ChordCall {
  const selected = freezeSelection(
    {
      description: 'Fixture',
      lead: { agent: 'fake' },
      members: [],
      body: 'Preserve permissions.',
    },
    { reason: 'Keep permissions; provider freshness is unknown.' },
    {},
    ['fake'],
  );

  assert('frozen' in selected);

  const receipt = selectionReceipt(
    id,
    { name: 'fixture', place: 'project' },
    selected.frozen,
  );

  return {
    tool: 'run_team',
    asked: id,
    input: { team: 'fixture', job: 'Actual recorded job.' },
    answer: { id, receipt },
  };
}

describe('owned unlinked Team receipt selection', () => {
  test('uses latest strict revision per actual ID, keeps distinct runs and ignores malformed late metadata', () => {
    const original = call();
    const update = {
      ...original,
      error: 'Cancelled before first job; closing.',
    };
    let state = reduceTranscript(emptyTranscript, {
      type: 'served',
      turnId: 'actual',
      call: original,
    });

    state = reduceTranscript(state, {
      type: 'served',
      turnId: 'actual',
      call: update,
    });
    state = reduceTranscript(state, {
      type: 'served',
      turnId: 'actual',
      call: { ...original, answer: { receipt: { schemaVersion: 9 } } },
    });
    state = reduceTranscript(state, {
      type: 'served',
      turnId: 'actual',
      call: call('second-id'),
    });

    expect(recordedReceipts(state)).toEqual([update, call('second-id')]);
    expect(recordedReceipts(emptyTranscript)).toEqual([]);
  });

  test('genuine ACP linkage replaces the owned fallback with one normal Team call carrying the same latest receipt', () => {
    const latest = { ...call(), error: 'Actual recorded refusal.' };
    let state = reduceTranscript(emptyTranscript, {
      type: 'served',
      turnId: 'actual',
      call: latest,
    });

    expect(recordedReceipts(state)).toEqual([latest]);

    state = reduceTranscript(state, {
      type: 'update',
      turnId: 'actual',
      update: {
        sessionUpdate: 'tool_call',
        toolCallId: 'genuine-call',
        title: 'mcp__chord__run_team',
        status: 'completed',
        rawInput: latest.input,
      },
    });

    expect(recordedReceipts(state)).toEqual([]);

    const tools = state.entries.filter((entry) => entry.kind === 'tool');

    expect(tools).toHaveLength(1);
    expect(tools[0]?.call.chord).toEqual(latest);
  });

  test('unproved receipt IDs and model text cannot create a fallback', () => {
    const original = call();

    expect(
      recordedReceipts({
        ...emptyTranscript,
        served: [{ ...original, asked: 'not-its-run' }],
      }),
    ).toEqual([]);
    expect(
      recordedReceipts({
        ...emptyTranscript,
        served: [{ ...original, tool: 'send_message' }],
      }),
    ).toEqual([]);
  });
});
