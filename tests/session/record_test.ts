import { expect, test } from 'bun:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import type { ConversationEvent } from '../../src/session/conversation.ts';
import { turnCost } from '../../src/session/prices.ts';
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

/** A session as far as its recording reads it. */
const session = {
  id: 's',
  agent: 'claude',
  cwd: '/',
  history: () => [],
  models: () => ({ current: 'm', available: [] }),
  modes: () => undefined,
  options: () => [],
} as unknown as Session;

const usageUpdate = (turnId: string, amount?: number): ConversationEvent => ({
  type: 'update',
  turnId,
  update: {
    sessionUpdate: 'usage_update',
    used: 1,
    size: 2,
    ...(amount === undefined ? {} : { cost: { amount, currency: 'USD' } }),
  },
});

test("an agent's own cycle has a line of its own with what its usage moved the cost by, and one whose usage says none has none", () =>
  withDir(async (dir) => {
    const recording = new FileRecording(dir, () => {});

    const heard = (...events: ConversationEvent[]) =>
      events.forEach((event) => recording.heard(event));
    const ended = { status: 'completed', stopReason: 'end_turn' } as const;
    const tokens = { totalTokens: 5 };

    recording.opened(session);
    recording.sent('t1', 'hello', 0, [], 1);
    heard(
      usageUpdate('t1', 0.01),
      { type: 'result', turnId: 't1', result: { ...ended, usage: tokens } },
      { type: 'usage', turnId: 't1', usage: tokens },
      { type: 'cycle_started', turnId: 'c1', at: 2 },
      usageUpdate('c1', 0.015),
      { type: 'result', turnId: 'c1', result: ended },
      { type: 'cycle_started', turnId: 'c2', at: 3 },
      usageUpdate('c2'),
      { type: 'result', turnId: 'c2', result: ended },
    );
    await recording.flushed();

    const entries = await readPast(recording.path!);

    expect(
      entries.flatMap((entry) => (entry.type === 'usage' ? [entry] : [])),
    ).toStrictEqual([
      {
        type: 'usage',
        turnId: 't1',
        usage: { totalTokens: 5 },
        model: 'm',
        cost: { amount: 0.01, currency: 'USD' },
      },
      {
        type: 'usage',
        turnId: 'c1',
        usage: {},
        model: 'm',
        cost: { amount: expect.closeTo(0.005, 9) as number, currency: 'USD' },
      },
    ]);
  }));

test("a cost that comes after the next turn began is that turn's, so each is counted once", () =>
  withDir(async (dir) => {
    const recording = new FileRecording(dir, () => {});

    const heard = (...events: ConversationEvent[]) =>
      events.forEach((event) => recording.heard(event));
    const cancelled = {
      status: 'cancelled',
      stopReason: 'cancelled',
    } as const;

    recording.opened(session);
    recording.sent('t1', 'one', 0, [], 1);
    heard({ type: 'result', turnId: 't1', result: cancelled });
    recording.sent('t2', 'two', 0, [], 2);
    // Both turns' cost, the first's late.
    heard(usageUpdate('t2', 0.02), {
      type: 'result',
      turnId: 't2',
      result: { status: 'completed', stopReason: 'end_turn' },
    });
    await recording.flushed();

    expect(costs(await readPast(recording.path!))).toStrictEqual([
      { model: 'm', cost: { amount: 0.02, currency: 'USD' } },
    ]);
  }));
