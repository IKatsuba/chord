import { expect, test } from 'bun:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { turnCost } from '../../src/session/prices.ts';
import type { ConversationEvent } from '../../src/session/conversation.ts';
import {
  FileRecording,
  readPast,
  type RecordEntry,
} from '../../src/session/record.ts';
import type { Session } from '../../src/session/session.ts';
import { readRecords } from '../../src/session/sessions.ts';
import { fakeAgentCommand } from '../fixtures/fake.ts';
import { recordSession } from '../fixtures/records.ts';

async function withDir(body: (dir: string) => Promise<void>) {
  const dir = await mkdtemp(join(tmpdir(), 'chord-record-'));

  try {
    await body(dir);
  } finally {
    await rm(dir, { recursive: true });
  }
}

/** The one record in `dir`'s state, with its path. */
async function theRecord(dir: string) {
  const [record, ...more] = await readRecords(join(dir, 'state'));

  assert(record !== undefined && more.length === 0, 'one record');

  return record;
}

/** Each turn's cost as its last usage line has it, in the order turns ended. */
function costs(entries: readonly RecordEntry[]) {
  const last = new Map<string, RecordEntry>();

  for (const entry of entries) {
    if (entry.type === 'usage') {
      last.delete(entry.turnId);
      last.set(entry.turnId, entry);
    }
  }

  return [...last.values()].map((entry) => {
    assert(entry.type === 'usage');

    const { type: _, turnId: __, usage: ___, ...rest } = entry;

    return rest;
  });
}

/**
 * Leaves a record of `prompts` in a session of the fake as `agent`, then
 * reopens it with `again` sent, the fake started again with `flags`.
 */
async function resumed(
  dir: string,
  {
    agent = 'fake',
    prompts = ['text', 'text'],
    again = ['text', 'text'],
    flags = [],
    first = [],
  }: {
    agent?: string;
    prompts?: string[];
    again?: string[];
    flags?: string[];
    first?: string[];
  },
): Promise<RecordEntry[]> {
  const stateDir = join(dir, 'state');
  const id = await recordSession({
    stateDir,
    cwd: dir,
    command: fakeAgentCommand(undefined, ...first),
    prompts,
    agent,
  });
  const record = await theRecord(dir);

  await recordSession({
    stateDir,
    cwd: dir,
    command: fakeAgentCommand(undefined, '--resume-only', ...flags),
    prompts: again,
    agent,
    resume: { sessionId: id, cwd: dir, record: record.path },
  });

  return await readPast(record.path);
}

const turn = (amount: number) => ({
  model: 'fake-large',
  cost: { amount: expect.closeTo(amount, 9), currency: 'USD' },
});

test("each opening of a session is a line of its own, and each turn's line keeps its own cost and the model it ended on (CHD-373)", () =>
  withDir(async (dir) => {
    const entries = await resumed(dir, { agent: 'claude' });

    expect(entries.map((entry) => entry.type).slice(0, 4)).toStrictEqual([
      'session',
      'opened',
      'state',
      'prompt',
    ]);
    expect(entries.filter((entry) => entry.type === 'opened')).toHaveLength(2);
    // Claude's counts from each opening: the fake started again starts its
    // cost again, and the first turn after is the turn's alone.
    expect(costs(entries)).toStrictEqual([
      turn(0.0125),
      turn(0.0125),
      turn(0.0125),
      turn(0.0125),
    ]);
  }));

test("after a resume, an agent that keeps its cost with the session has its first turn's less what the record had come to", () =>
  withDir(async (dir) => {
    // Two turns of $0.0125 before; the agent counts on from there.
    const entries = await resumed(dir, {
      agent: 'kilo',
      flags: ['--cost-from', '0.025'],
    });

    expect(costs(entries)).toStrictEqual([
      turn(0.0125),
      turn(0.0125),
      turn(0.0125),
      turn(0.0125),
    ]);
  }));

test("after a resume, an agent whose counting is not known has a first turn chord cannot price left uncounted, and the next by what it moved (the owner's Q61)", () =>
  withDir(async (dir) => {
    const entries = await resumed(dir, {
      flags: ['--cost-from', '0.025'],
    });

    expect(costs(entries)).toStrictEqual([
      turn(0.0125),
      turn(0.0125),
      { model: 'fake-large', uncounted: true },
      turn(0.0125),
    ]);
  }));

test("chord's estimate is each turn's tokens priced, marked, also after a resume", () =>
  withDir(async (dir) => {
    const entries = await resumed(dir, {
      agent: 'codex',
      prompts: ['text'],
      again: ['text'],
      first: ['--tokens-only'],
      flags: ['--tokens-only'],
    });
    const each = {
      model: 'gpt-5.3-codex',
      cost: {
        amount: expect.closeTo(
          turnCost('gpt-5.3-codex', {
            inputTokens: 1000,
            outputTokens: 200,
            cachedReadTokens: 800,
            totalTokens: 2000,
          })!,
          12,
        ),
        currency: 'USD',
      },
      estimated: true as const,
    };

    expect(costs(entries)).toStrictEqual([each, each]);
  }));

test("a cost that comes after its turn's answer, as Claude's can, is still that turn's: its line is written again with it", () =>
  withDir(async (dir) => {
    await recordSession({
      stateDir: join(dir, 'state'),
      cwd: dir,
      command: fakeAgentCommand(undefined, '--late-cost'),
      prompts: ['text', 'text'],
      agent: 'claude',
      lateCost: true,
    });

    const entries = await readPast((await theRecord(dir)).path);
    const usage = entries.filter((entry) => entry.type === 'usage');

    // Each turn's line once at its end, with no cost yet, then again.
    expect(usage.map((entry) => 'cost' in entry)).toStrictEqual([
      false,
      true,
      false,
      true,
    ]);
    expect(costs(entries)).toStrictEqual([turn(0.0125), turn(0.0125)]);
  }));

/** A session as far as its recording reads it, `record` its file if resumed. */
const looked = (record?: string) =>
  ({
    id: 's',
    agent: 'claude',
    cwd: '/',
    ...(record === undefined ? {} : { record }),
    history: () => [],
    models: () => ({ current: 'm', available: [] }),
    modes: () => undefined,
    options: () => [],
  }) as unknown as Session;

/** The agent's own cycle, with no prompt sent, as the conversation reports it. */
const cycle: ConversationEvent[] = [
  { type: 'cycle_started', turnId: 'c1', at: 2 },
  {
    type: 'update',
    turnId: 'c1',
    update: {
      sessionUpdate: 'usage_update',
      used: 1,
      size: 2,
      cost: { amount: 0.01, currency: 'USD' },
    },
  },
  {
    type: 'result',
    turnId: 'c1',
    result: { status: 'completed', stopReason: 'end_turn' },
  },
  {
    type: 'usage',
    turnId: 'c1',
    usage: {},
    model: 'm',
    cost: { amount: 0.01, currency: 'USD' },
  },
];

test("an agent's own cycle is kept with no prompt sent, in a new session and in one resumed, as what it spent counts", () =>
  withDir(async (dir) => {
    const fresh = new FileRecording(join(dir, 'state'), () => {});

    fresh.opened(looked());
    cycle.forEach((event) => fresh.heard(event));
    await fresh.flushed();

    const kept = await readPast(fresh.path!);

    expect(kept.map((entry) => entry.type)).toStrictEqual([
      'session',
      'opened',
      'state',
      'update',
      'result',
      'usage',
    ]);

    // Opened again from its record, the cycle goes on in it.
    const resumed = new FileRecording(join(dir, 'state'), () => {});

    resumed.opened(looked(fresh.path!));
    cycle.forEach((event) => resumed.heard(event));
    await resumed.flushed();

    expect(
      (await readPast(fresh.path!)).slice(kept.length).map((each) => each.type),
    ).toStrictEqual(['opened', 'state', 'update', 'result', 'usage']);
  }));

test('a session only looked at, with no prompt and no cycle, leaves no record', () =>
  withDir(async (dir) => {
    const recording = new FileRecording(join(dir, 'state'), () => {});

    recording.opened(looked());
    recording.heard(cycle[1]!);
    await recording.flushed();

    expect(await readRecords(join(dir, 'state'))).toStrictEqual([]);
  }));
