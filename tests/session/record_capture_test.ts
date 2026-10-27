import { describe, expect, test } from 'bun:test';
import assert from 'node:assert/strict';
import { mkdtemp, readdir, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import {
  Conversation,
  type ConversationEvent,
} from '../../src/session/conversation.ts';
import {
  FileRecording,
  readPast,
  recordActions,
} from '../../src/session/record.ts';
import { openSession, type Session } from '../../src/session/session.ts';
import {
  freezeSelection,
  selectionReceipt,
  SelectionReceipt,
} from '../../src/session/team_selection.ts';
import {
  emptyTranscript,
  type ChordCall,
} from '../../src/session/transcript/types.ts';
import { reduceTranscript } from '../../src/session/transcript/reducer.ts';
import { fakeAgentCommand } from '../fixtures/fake.ts';
import { until } from './conversation_fake.ts';

async function withRecord(
  body: (directory: string, recording: FileRecording) => Promise<void>,
) {
  const directory = await mkdtemp(join(tmpdir(), 'chord-record-capture-'));
  const recording = new FileRecording(directory, () => {});

  try {
    await body(directory, recording);
  } finally {
    await recording.flushed();
    await rm(directory, { recursive: true });
  }
}

function looked(id: string): Session {
  return {
    id,
    agent: 'fake',
    cwd: '/project',
    history: () => [],
    models: () => undefined,
    modes: () => undefined,
    options: () => [],
  } as unknown as Session;
}

function selected() {
  const input = {
    team: 'fixture',
    job: 'Preserve the job.',
    selection: { reason: 'Preserve every role; capacity is unknown.' },
  };
  const result = freezeSelection(
    {
      description: 'Record fixture',
      lead: { agent: 'fake' },
      members: [
        {
          name: 'reviewer',
          role: 'Review',
          agent: 'fake',
          instructions: 'Review without editing.',
        },
      ],
      body: 'Keep the team instructions unchanged.',
    },
    input.selection,
    {},
    ['fake'],
  );

  assert('frozen' in result);

  const receipt = selectionReceipt(
    'attempt-one',
    { name: 'fixture', place: 'project' },
    result.frozen,
  );
  const call: ChordCall = {
    tool: 'run_team',
    input,
    asked: receipt.runId,
    answer: {
      id: receipt.runId,
      name: 'fixture',
      team: 'fixture',
      agent: 'fake',
      receipt,
    },
  };

  return { receipt, call };
}

describe('captured run receipt records', () => {
  test('no opened record means no captured path or fabricated session', () =>
    withRecord(async (directory, recording) => {
      expect(recording.captureServed()).toBeUndefined();
      await recording.flushed();
      expect(await readdir(directory)).toEqual([]);
    }));

  test('late updates append only to the original record and replay the latest receipt', () =>
    withRecord(async (_directory, recording) => {
      const { receipt, call } = selected();

      recording.opened(looked('real-caller-fixture'));

      const original = recording.path;
      const write = recording.captureServed();

      assert(original !== undefined && write !== undefined);
      recording.heard({
        type: 'update',
        turnId: 'selection',
        update: {
          sessionUpdate: 'tool_call',
          toolCallId: 'team-call',
          title: 'mcp__chord__run_team',
          status: 'completed',
          rawInput: call.input,
        },
      });
      write('selection', call);
      recording.heard({ type: 'cleared' });
      recording.opened(looked('replacement-fixture'));

      const replacement = recording.path;
      const refused = SelectionReceipt.parse({
        ...receipt,
        roles: receipt.roles.map((role) =>
          role.role === 'lead'
            ? { ...role, state: 'refused', note: 'Initialization was refused.' }
            : role,
        ),
      });

      write('selection', {
        ...call,
        error: 'Lead initialization failed before its first job.',
        answer: { receipt: refused },
      });
      await recording.flushed();
      assert(replacement !== undefined);

      const originalEntries = await readPast(original);
      const replay = recordActions(originalEntries).reduce(
        (state, action) =>
          action.type === 'usage' ? state : reduceTranscript(state, action),
        emptyTranscript,
      );
      const teamCall = replay.entries.find((entry) => entry.kind === 'tool');

      assert(teamCall?.kind === 'tool');
      expect(teamCall.call.chord?.answer).toEqual({ receipt: refused });
      expect(
        originalEntries.filter((entry) => entry.type === 'served'),
      ).toHaveLength(2);
      expect(originalEntries.some((entry) => entry.type === 'prompt')).toBe(
        false,
      );
      expect(JSON.stringify(originalEntries)).not.toContain(
        'replacement-fixture',
      );
      expect(await readPast(replacement)).toEqual([]);
    }));

  test('failed initialization keeps the attempt in its actual caller record without a lead record', () =>
    withRecord(async (directory, recording) => {
      const { receipt: planned, call } = selected();
      const receipt = SelectionReceipt.parse({
        ...planned,
        roles: planned.roles.map((role) =>
          role.role === 'lead'
            ? {
                ...role,
                state: 'refused',
                note: 'Initialization failed before the first job.',
              }
            : role,
        ),
      });

      recording.opened(looked('actual-parent'));

      const write = recording.captureServed();
      const path = recording.path;

      assert(write !== undefined && path !== undefined);
      write('selection', {
        ...call,
        error: 'Initialization failed before the first job.',
        answer: { id: receipt.runId, receipt },
      });
      await recording.flushed();

      const entries = await readPast(path);

      expect(entries.filter((entry) => entry.type === 'session')).toEqual([
        expect.objectContaining({ sessionId: 'actual-parent' }),
      ]);
      expect(entries.some((entry) => entry.type === 'prompt')).toBe(false);
      expect((await readdir(join(directory, 'records'))).length).toBe(1);
      expect(entries.find((entry) => entry.type === 'served')).toMatchObject({
        call: { answer: { id: 'attempt-one', receipt } },
      });
    }));

  test('Conversation captured writer never emits a late receipt into its replacement', () =>
    withRecord(async (directory, recording) => {
      const events: ConversationEvent[] = [];
      const { receipt, call } = selected();
      const conversation = new Conversation(
        (signal) =>
          openSession({
            agent: 'fake',
            cwd: directory,
            agentCommand: fakeAgentCommand(),
            signal,
          }),
        (event) => events.push(event),
        Date.now,
        {},
        recording,
      );

      try {
        expect(conversation.captureServed()).toBeUndefined();
        conversation.start();
        await until(() => events.some((event) => event.type === 'connected'));

        const original = recording.path;
        const write = conversation.captureServed();

        assert(original !== undefined && write !== undefined);
        write(call);
        await conversation.clear();
        await until(
          () =>
            events.filter((event) => event.type === 'connected').length === 2,
        );

        const replacement = recording.path;
        const before = events.length;

        write({
          ...call,
          error: 'Attempt cancelled before its first job.',
          answer: { receipt },
        });
        await recording.flushed();
        expect(
          events.slice(before).some((event) => event.type === 'served'),
        ).toBe(false);
        expect(
          (await readPast(original)).filter((entry) => entry.type === 'served'),
        ).toHaveLength(2);
        assert(replacement !== undefined);
        expect(await readPast(replacement)).toEqual([]);
      } finally {
        await conversation.close();
      }
    }));
});
