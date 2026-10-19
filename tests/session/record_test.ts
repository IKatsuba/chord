import { describe, expect, test } from 'bun:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { turnCost } from '../../src/session/prices.ts';
import {
  Conversation,
  type ConversationEvent,
} from '../../src/session/conversation.ts';
import {
  FileRecording,
  readPast,
  recordActions,
  type RecordEntry,
} from '../../src/session/record.ts';
import { openSession, type Session } from '../../src/session/session.ts';
import { readRecords, type Resume } from '../../src/session/sessions.ts';
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

describe('CHD-373 S3a tester: live and recorded turn costs', () => {
  test('an explicit zero is kept in live usage, JSON and replay, followed by only the next increment', () =>
    withDir(async (dir) => {
      const heard: ConversationEvent[] = [];

      await recordSession({
        stateDir: join(dir, 'state'),
        cwd: dir,
        command: fakeAgentCommand(undefined, '--cost-from', '-0.0125'),
        prompts: ['text', 'text'],
        agent: 'claude',
        heard: (event) => heard.push(event),
      });

      const entries = await readPast((await theRecord(dir)).path);
      const live = heard.filter((event) => event.type === 'usage');
      const replayed = recordActions(entries).filter(
        (event) => event.type === 'usage',
      );

      expect(live.map((event) => event.cost)).toStrictEqual([
        { amount: 0, currency: 'USD' },
        { amount: 0.0125, currency: 'USD' },
      ]);
      expect(costs(entries)).toStrictEqual([turn(0), turn(0.0125)]);
      expect(replayed.map((event) => event.cost)).toStrictEqual(
        live.map((event) => event.cost),
      );
      expect(
        live.every(
          (event) =>
            event.estimated === undefined && event.uncounted === undefined,
        ),
      ).toBe(true);
    }));

  test('a resumed per-session zero stays explicit and the later increment is counted once', () =>
    withDir(async (dir) => {
      const entries = await resumed(dir, {
        agent: 'kilo',
        prompts: ['text'],
        first: ['--cost-from', '-0.0125'],
        flags: ['--cost-from', '-0.0125'],
      });

      expect(costs(entries)).toStrictEqual([turn(0), turn(0), turn(0.0125)]);
      expect(entries.filter((entry) => entry.type === 'opened')).toHaveLength(
        2,
      );
      expect(
        recordActions(entries).filter((entry) => entry.type === 'usage'),
      ).toHaveLength(3);
    }));

  test('simultaneous conversations keep their cumulative readings and turn costs apart', async () => {
    await Promise.all(
      [0, 0.2].map((from) =>
        withDir(async (dir) => {
          const events: ConversationEvent[] = [];

          await recordSession({
            stateDir: join(dir, 'state'),
            cwd: dir,
            command: fakeAgentCommand(undefined, '--cost-from', String(from)),
            prompts: ['text', 'text'],
            agent: 'claude',
            heard: (event) => events.push(event),
          });

          const entries = await readPast((await theRecord(dir)).path);
          const amounts = events
            .filter((event) => event.type === 'usage')
            .map((event) => event.cost?.amount);

          expect(amounts).toHaveLength(2);
          expect(amounts[0]).toBeCloseTo(from + 0.0125, 9);
          expect(amounts[1]).toBeCloseTo(0.0125, 9);
          expect(costs(entries)).toStrictEqual([
            turn(from + 0.0125),
            turn(0.0125),
          ]);
        }),
      ),
    );
  });

  test('clear starts a new cost baseline without changing the old record', () =>
    withDir(async (dir) => {
      const sessions: Session[] = [];
      const events: ConversationEvent[] = [];
      const failures: string[] = [];
      const recording = new FileRecording(join(dir, 'state'), (message) =>
        failures.push(message),
      );
      const conversation = new Conversation(
        async () => {
          const session = await openSession({
            agent: 'claude',
            cwd: dir,
            agentCommand: fakeAgentCommand(
              undefined,
              '--cost-from',
              sessions.length === 0 ? '0.2' : '-0.0125',
            ),
          });

          sessions.push(session);

          return session;
        },
        (event) => events.push(event),
        Date.now,
        {},
        recording,
      );
      const wait = async (check: () => boolean) => {
        const deadline = Date.now() + 10000;

        while (!check()) {
          assert(
            Date.now() < deadline,
            'expected conversation cost transition',
          );
          await new Promise((resolve) => setTimeout(resolve, 10));
        }
      };

      const usages = () => events.filter((event) => event.type === 'usage');

      try {
        conversation.start();
        await wait(() => events.some((event) => event.type === 'connected'));
        conversation.send('text');
        await wait(() => usages().length === 1);
        conversation.send('text');
        await wait(() => usages().length === 2);
        await recording.flushed();

        const oldPath = recording.path;

        assert(oldPath !== undefined);

        const old = await readPast(oldPath);

        conversation.clear();
        await wait(
          () =>
            events.filter((event) => event.type === 'connected').length === 2,
        );
        conversation.send('text');
        await wait(() => usages().length === 3);
        await recording.flushed();
        assert(recording.path !== undefined && recording.path !== oldPath);
        expect(costs(old)).toStrictEqual([turn(0.2125), turn(0.0125)]);
        expect(costs(await readPast(recording.path))).toStrictEqual([turn(0)]);
        expect(await readPast(oldPath)).toStrictEqual(old);
        expect(usages().at(-1)?.cost).toStrictEqual({
          amount: 0,
          currency: 'USD',
        });
      } finally {
        await conversation.close();
      }

      expect(failures).toStrictEqual([]);

      for (const session of sessions) {
        await session.exited;
        expect(session.agentPids.size).toBe(0);
      }
    }));
});

describe("CHD-373 S3a: the fake's own cycle with a cost, and a cost held for the next prompt", () => {
  /** The cycle's figures, a `usage` event with no tokens. */
  const cycleEnded = (event: ConversationEvent) =>
    event.type === 'usage' && Object.keys(event.usage).length === 0;

  async function played(
    dir: string,
    flags: string[],
    prompts: string[],
    more: { agent?: string; resume?: Resume; waits?: boolean } = {},
  ): Promise<RecordEntry[]> {
    const { agent = 'claude', resume, waits = true } = more;

    await recordSession({
      stateDir: join(dir, 'state'),
      cwd: dir,
      command: fakeAgentCommand(undefined, ...flags),
      prompts,
      agent,
      ...(resume === undefined ? {} : { resume }),
      ...(waits ? { until: cycleEnded } : {}),
    });

    return await readPast((await theRecord(dir)).path);
  }

  const cycled = (amount: number) => ({
    model: 'fake-large',
    cost: { amount: expect.closeTo(amount, 9), currency: 'USD' },
  });

  test("a Claude cycle after a turn has a line of its own with what it added to the session's cost", () =>
    withDir(async (dir) => {
      const entries = await played(
        dir,
        ['--adapter', 'claude', '--cycle-cost', '0.005'],
        ['claudecycle'],
      );

      expect(costs(entries)).toStrictEqual([turn(0.0125), cycled(0.005)]);
    }));

  test('a cycle whose usage repeats the cost as it was says it cost nothing', () =>
    withDir(async (dir) => {
      const entries = await played(
        dir,
        ['--adapter', 'claude', '--cycle-cost', '0'],
        ['claudecycle'],
      );

      expect(costs(entries)).toStrictEqual([turn(0.0125), cycled(0)]);
    }));

  test('a cycle in a resumed session with no prompt sent is kept in its record, as its opening counts it', () =>
    withDir(async (dir) => {
      const id = await recordSession({
        stateDir: join(dir, 'state'),
        cwd: dir,
        command: fakeAgentCommand(),
        prompts: ['text'],
        agent: 'claude',
      });
      const record = await theRecord(dir);
      const entries = await played(
        dir,
        [
          '--resume-only',
          '--adapter',
          'claude',
          '--cycle-on-resume',
          '--cycle-cost',
          '0.005',
        ],
        [],
        { resume: { sessionId: id, cwd: dir, record: record.path } },
      );

      expect(entries.filter((entry) => entry.type === 'opened')).toHaveLength(
        2,
      );

      // No prompt went in the second opening.
      const again = entries.findLastIndex((entry) => entry.type === 'opened');

      expect(
        entries.slice(again).some((entry) => entry.type === 'prompt'),
      ).toBe(false);
      // Claude's counts from each opening: the cycle's first cost is its own.
      expect(costs(entries)).toStrictEqual([turn(0.0125), cycled(0.005)]);
    }));

  test("a turn's cost that comes once the next prompt has begun is the next turn's, so each is counted once", () =>
    withDir(async (dir) => {
      const entries = await played(dir, ['--cost-at-next'], ['text', 'text'], {
        waits: false,
      });

      // The first turn's cost came with the second; the second's own is
      // held for a prompt that never came.
      expect(costs(entries)).toStrictEqual([
        { model: 'fake-large' },
        turn(0.0125),
      ]);
    }));
});
