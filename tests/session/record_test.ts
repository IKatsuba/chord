import { describe, expect, test } from 'bun:test';
import assert from 'node:assert/strict';
import { mkdir, mkdtemp, rm } from 'node:fs/promises';
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
import { TaskAgent } from '../../src/session/tasks.ts';
import {
  initialAppState,
  reduceWindowed,
  windowed,
  type WindowedAction,
} from '../../src/ui/app/state.ts';
import type { SessionUpdate } from '@agentclientprotocol/sdk';
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

    // The agent's own updates are left out: it says its commands just after
    // it opens, which the record writes before the first prompt or after it,
    // as they come (CHD-467).
    expect(
      entries
        .filter((entry) => entry.type !== 'update')
        .map((entry) => entry.type)
        .slice(0, 4),
    ).toStrictEqual(['session', 'opened', 'state', 'prompt']);
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
    const usage = entries.flatMap((entry) =>
      entry.type === 'usage' ? [entry] : [],
    );
    const turns = [...new Set(usage.map((entry) => entry.turnId))];

    // Each turn's last line has its cost: written again with it where the
    // cost came after the answer, or once where it came first, which of the
    // two the wire decides (CHD-467); the after-the-answer path itself is
    // pinned by TurnCosts' own tests.
    expect(turns).toHaveLength(2);

    for (const id of turns) {
      const lines = usage.filter((entry) => entry.turnId === id);

      expect('cost' in lines.at(-1)!, id).toBe(true);
      expect(lines.length, id).toBeLessThanOrEqual(2);
    }

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

describe('CHD-373 S3a tester: causal wire costs through Conversation', () => {
  for (const [agent, increment, expected] of [
    ['kilo', '0.005', 0.005],
    ['kilo', '0', 0],
    ['fake', '0.005', undefined],
  ] as const) {
    test(`${agent}: a no-prompt resumed cycle with increment ${increment} keeps its live and recorded attribution`, () =>
      withDir(async (dir) => {
        const id = await recordSession({
          stateDir: join(dir, 'state'),
          cwd: dir,
          command: fakeAgentCommand(),
          prompts: ['text'],
          agent,
        });
        const record = await theRecord(dir);
        const events: ConversationEvent[] = [];

        await recordSession({
          stateDir: join(dir, 'state'),
          cwd: dir,
          agent,
          resume: { sessionId: id, cwd: dir, record: record.path },
          prompts: [],
          command: fakeAgentCommand(
            undefined,
            '--resume-only',
            '--adapter',
            'claude',
            '--cycle-on-resume',
            '--cycle-cost',
            increment,
            '--cost-from',
            '0.0125',
          ),
          heard: (event) => events.push(event),
          until: (event) =>
            event.type === 'usage' && Object.keys(event.usage).length === 0,
        });

        const entries = await readPast(record.path);
        const start = events.find((event) => event.type === 'cycle_started');

        assert(start?.type === 'cycle_started');

        const live = events
          .filter((event) => event.type === 'usage')
          .filter((event) => event.turnId === start.turnId);
        const written = entries.filter(
          (entry) => entry.type === 'usage' && entry.turnId === start.turnId,
        );

        expect(live).toHaveLength(1);
        expect(written).toStrictEqual(live);
        expect(live[0]?.usage).toStrictEqual({});
        expect(live[0]?.model).toBe('fake-large');

        if (expected === undefined) {
          expect(live[0]?.cost).toBeUndefined();
          expect(live[0]?.uncounted).toBe(true);
        } else {
          expect(live[0]?.cost?.amount).toBeCloseTo(expected, 9);
          expect(live[0]?.cost?.currency).toBe('USD');
          expect(live[0]?.uncounted).toBeUndefined();
        }

        const opening = entries.findLastIndex(
          (entry) => entry.type === 'opened',
        );

        expect(entries.filter((entry) => entry.type === 'opened')).toHaveLength(
          2,
        );
        expect(
          entries.slice(opening).some((entry) => entry.type === 'prompt'),
        ).toBe(false);
        expect(
          events.some(
            (event) => event.type === 'result' && event.turnId === start.turnId,
          ),
        ).toBe(true);
      }));
  }

  test('four successive prompts attribute each causally released prior cost once to the following turn', () =>
    withDir(async (dir) => {
      const events: ConversationEvent[] = [];

      await recordSession({
        stateDir: join(dir, 'state'),
        cwd: dir,
        agent: 'claude',
        command: fakeAgentCommand(undefined, '--cost-at-next'),
        prompts: ['text', 'text', 'text', 'text'],
        heard: (event) => events.push(event),
      });

      const entries = await readPast((await theRecord(dir)).path);
      const prompts = events.filter((event) => event.type === 'prompt');
      const readings = events
        .filter((event) => event.type === 'update')
        .filter(
          (event) =>
            event.update.sessionUpdate === 'usage_update' &&
            event.update.cost !== undefined,
        );
      const live = events.filter((event) => event.type === 'usage');

      expect(prompts).toHaveLength(4);
      expect(readings).toHaveLength(3);
      expect(readings.map((event) => event.turnId)).toStrictEqual(
        prompts.slice(1).map((event) => event.turnId),
      );

      for (const [i, reading] of readings.entries()) {
        expect(events.indexOf(reading)).toBeGreaterThan(
          events.indexOf(prompts[i + 1]!),
        );
      }

      expect(live.map((event) => event.cost?.amount)).toEqual([
        undefined,
        expect.closeTo(0.0125, 9),
        expect.closeTo(0.0125, 9),
        expect.closeTo(0.0125, 9),
      ]);
      expect(costs(entries)).toStrictEqual([
        { model: 'fake-large' },
        turn(0.0125),
        turn(0.0125),
        turn(0.0125),
      ]);
      expect(
        recordActions(entries)
          .filter((entry) => entry.type === 'usage')
          .map((entry) => entry.cost),
      ).toStrictEqual(live.map((event) => event.cost));
    }));

  test('a cost released into a permission turn survives cancellation of that turn', () =>
    withDir(async (dir) => {
      const events: ConversationEvent[] = [];
      const failures: string[] = [];
      const recording = new FileRecording(join(dir, 'state'), (message) =>
        failures.push(message),
      );
      let owner: Session | undefined;
      const conversation = new Conversation(
        async () => {
          owner = await openSession({
            agent: 'claude',
            cwd: dir,
            agentCommand: fakeAgentCommand(undefined, '--cost-at-next'),
          });

          return owner;
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
            'expected cancellation cost transition',
          );
          await new Promise((resolve) => setTimeout(resolve, 10));
        }
      };

      try {
        conversation.start();
        await wait(() => events.some((event) => event.type === 'connected'));
        conversation.send('text');
        await wait(() => events.some((event) => event.type === 'usage'));
        conversation.send('permission');
        await wait(() =>
          events.some((event) => event.type === 'permission_requested'),
        );

        const prompt = events.findLast((event) => event.type === 'prompt');

        assert(prompt?.type === 'prompt');
        expect(
          events.some(
            (event) =>
              event.type === 'update' &&
              event.turnId === prompt.turnId &&
              event.update.sessionUpdate === 'usage_update' &&
              event.update.cost?.amount === 0.0125,
          ),
        ).toBe(true);
        conversation.interrupt();
        await wait(() =>
          events.some(
            (event) =>
              event.type === 'result' &&
              event.turnId === prompt.turnId &&
              event.result.status === 'cancelled',
          ),
        );
        await wait(() =>
          events.some(
            (event) => event.type === 'usage' && event.turnId === prompt.turnId,
          ),
        );
        await recording.flushed();
        assert(recording.path !== undefined);

        const entries = await readPast(recording.path);
        const live = events
          .filter((event) => event.type === 'usage')
          .filter((event) => event.turnId === prompt.turnId);

        expect(live).toHaveLength(1);
        expect(live[0]?.cost).toStrictEqual({
          amount: 0.0125,
          currency: 'USD',
        });
        expect(
          entries.filter(
            (entry) => entry.type === 'usage' && entry.turnId === prompt.turnId,
          ),
        ).toStrictEqual(live);
      } finally {
        await conversation.close();
      }

      assert(owner !== undefined);
      await owner.exited;
      expect(owner.agentPids.size).toBe(0);
      expect(failures).toStrictEqual([]);
    }));
});

describe("CHD-373 S3b: an older record's spend before it kept each turn's (the owner's Q62)", () => {
  const header: RecordEntry = {
    type: 'session',
    version: 1,
    sessionId: 's',
    agent: 'claude',
    cwd: '/',
    at: 1,
  };
  const costed = (turnId: string, amount: number): RecordEntry => ({
    type: 'update',
    turnId,
    update: {
      sessionUpdate: 'usage_update',
      used: 1,
      size: 2,
      cost: { amount, currency: 'USD' },
    },
  });
  const before = (actions: ReturnType<typeof recordActions>) =>
    actions.filter(
      (action) => action.type === 'usage' && action.before !== undefined,
    );

  test('a record written before openings were kept counts its last cost as one figure, as last reported', () => {
    expect(
      before(
        recordActions([
          header,
          costed('a', 0.01),
          { type: 'usage', turnId: 'a', usage: { totalTokens: 5 } },
          costed('b', 0.04),
        ]),
      ),
    ).toStrictEqual([
      {
        type: 'usage',
        turnId: 'history-before',
        usage: {},
        cost: { amount: 0.04, currency: 'USD' },
        before: {},
      },
    ]);
  });

  test('one that began keeping them later counts what came before its first opening, up to then, and its turns after on their own', () => {
    const actions = recordActions([
      header,
      costed('a', 0.04),
      { type: 'opened', at: 1_760_900_000_000 },
      costed('b', 0.05),
      {
        type: 'usage',
        turnId: 'b',
        usage: {},
        cost: { amount: 0.01, currency: 'USD' },
      },
    ]);

    expect(before(actions)).toStrictEqual([
      {
        type: 'usage',
        turnId: 'history-before',
        usage: {},
        cost: { amount: 0.04, currency: 'USD' },
        before: { until: 1_760_900_000_000 },
      },
    ]);
    expect(actions).toContainEqual({
      type: 'usage',
      turnId: 'history-b',
      usage: {},
      cost: { amount: 0.01, currency: 'USD' },
    });
  });

  test('a record that kept each turn from its first opening, or a cost a subagent sent, has nothing before', () => {
    expect(
      before(
        recordActions([header, { type: 'opened', at: 2 }, costed('a', 0.01)]),
      ),
    ).toStrictEqual([]);
    // A task's cost, under its id, is the task's, not the session's.
    expect(
      before(
        recordActions([
          header,
          { ...costed('a', 0.5), subagentId: 'task' } as RecordEntry,
          { type: 'opened', at: 2 },
        ]),
      ),
    ).toStrictEqual([]);
  });
});

describe('CHD-373 S3b tester: legacy zero is a reported baseline', () => {
  test('the last own zero supersedes earlier money and a later subagent cost cannot replace it', () => {
    const actions = recordActions([
      {
        type: 'session',
        version: 1,
        sessionId: 'legacy',
        agent: 'claude',
        cwd: '/',
        at: 1,
      },
      {
        type: 'update',
        turnId: 'old',
        update: {
          sessionUpdate: 'usage_update',
          used: 1,
          size: 2,
          cost: { amount: 4, currency: 'USD' },
        },
      },
      {
        type: 'update',
        turnId: 'zero',
        update: {
          sessionUpdate: 'usage_update',
          used: 1,
          size: 2,
          cost: { amount: 0, currency: 'USD' },
        },
      },
      {
        type: 'update',
        turnId: 'child',
        subagentId: 'task',
        update: {
          sessionUpdate: 'usage_update',
          used: 1,
          size: 2,
          cost: { amount: 50, currency: 'USD' },
        },
      },
      { type: 'opened', at: 100 },
    ]);

    expect(actions.filter((action) => action.type === 'usage')).toEqual([
      {
        type: 'usage',
        turnId: 'history-before',
        usage: {},
        cost: { amount: 0, currency: 'USD' },
        before: { until: 100 },
      },
    ]);
  });
});

describe('CHD-373 S3c: a turn running as its session is let go', () => {
  /** A conversation on the fake as Claude, recorded, and what it reports. */
  function opened(dir: string, agent = 'claude', flags: string[] = []) {
    const events: ConversationEvent[] = [];
    const recording = new FileRecording(join(dir, 'state'), () => {});

    const conversation = new Conversation(
      (signal) =>
        openSession({
          agent,
          cwd: dir,
          agentCommand: fakeAgentCommand(undefined, ...flags),
          signal,
        }),
      (event) => events.push(event),
      Date.now,
      {},
      recording,
    );
    const until = async (check: () => boolean) => {
      while (!check()) {
        await new Promise((resolve) => setTimeout(resolve, 10));
      }
    };

    conversation.start();

    return { events, recording, conversation, until };
  }

  test("/clear cancels the running turn, and its end, its cost said so far with it, goes into that session's record and is reported apart, once the old session has closed", () =>
    withDir(async (dir) => {
      const { events, recording, conversation, until } = opened(dir);

      try {
        await until(() => events.some((event) => event.type === 'connected'));
        conversation.send('costwait', 'costwait');
        await until(() =>
          events.some(
            (event) =>
              event.type === 'update' &&
              event.update.sessionUpdate === 'usage_update',
          ),
        );

        const turn = events.find((event) => event.type === 'prompt');
        const record = recording.path!;

        assert(turn?.type === 'prompt');
        await conversation.clear();

        const cleared = events.findIndex((event) => event.type === 'cleared');
        const retired = events.filter(
          (event) => event.type === 'retired_usage',
        );

        // After the clear, as the old session's, never as the new one's.
        expect(retired).toStrictEqual([
          {
            type: 'retired_usage',
            turnId: turn.turnId,
            usage: {},
            model: 'fake-large',
            cost: { amount: 0.01, currency: 'USD' },
          },
        ]);
        expect(events.indexOf(retired[0]!)).toBeGreaterThan(cleared);
        expect(events.some((event) => event.type === 'usage')).toBeFalsy();

        await recording.flushed();
        expect(costs(await readPast(record))).toStrictEqual([
          { model: 'fake-large', cost: { amount: 0.01, currency: 'USD' } },
        ]);
      } finally {
        await conversation.close();
      }
    }));

  test('a session cleared with no turn running is let go at once, and says nothing of cost', () =>
    withDir(async (dir) => {
      const { events, conversation, until } = opened(dir);

      try {
        await until(() => events.some((event) => event.type === 'connected'));
        conversation.send('text', 'text');
        await until(() => events.some((event) => event.type === 'result'));

        const started = performance.now();

        await conversation.clear();

        expect(performance.now() - started).toBeLessThan(2000);
        expect(
          events.some((event) => event.type === 'retired_usage'),
        ).toBeFalsy();
      } finally {
        await conversation.close();
      }
    }));

  /** A turn of `scenario` with its cost seen, then /clear, settled. */
  async function clearedIn(
    dir: string,
    scenario: string,
    { agent = 'claude', flags = [] as string[], seen = 'usage_update' } = {},
  ) {
    const opening = opened(dir, agent, flags);
    const { events, recording, conversation, until } = opening;

    await until(() => events.some((event) => event.type === 'connected'));
    conversation.send(scenario, scenario);
    await until(() =>
      events.some(
        (event) =>
          (seen === 'cycle_started' && event.type === 'cycle_started') ||
          (event.type === 'update' && event.update.sessionUpdate === seen),
      ),
    );

    const record = recording.path!;

    await conversation.clear();
    await recording.flushed();

    return { ...opening, record };
  }

  test("a cost said after the cancelled turn's answer, as Claude's adapter says it, is still that turn's, and its record keeps the cost too", () =>
    withDir(async (dir) => {
      const { events, conversation, record } = await clearedIn(
        dir,
        'costwaitlate',
      );

      try {
        const retired = events.flatMap((event) =>
          event.type === 'retired_usage' ? [event.cost?.amount] : [],
        );

        // The turn's last cost is the late one: said again after its 0.01
        // where it came after the answer, or alone where the wire brought it
        // first (CHD-467); the after-the-answer path itself is pinned by
        // TurnCosts' own tests.
        expect(retired.at(-1)).toBe(0.02);
        expect(retired.slice(0, -1).every((amount) => amount === 0.01)).toBe(
          true,
        );
        expect(retired.length).toBeLessThanOrEqual(2);

        const entries = await readPast(record);

        expect(costs(entries)).toStrictEqual([
          { model: 'fake-large', cost: { amount: 0.02, currency: 'USD' } },
        ]);
        expect(
          entries.some(
            (entry) =>
              entry.type === 'update' &&
              entry.update.sessionUpdate === 'usage_update' &&
              entry.update.cost?.amount === 0.02,
          ),
        ).toBeTruthy();
      } finally {
        await conversation.close();
      }
    }));

  test("an agent's own cycle cleared before the usage that ends it still counts that usage's cost, as its session's", () =>
    withDir(async (dir) => {
      const { events, conversation, record } = await clearedIn(
        dir,
        'claudecycle',
        {
          flags: ['--adapter', 'claude', '--cycle-cost', '0.005'],
          seen: 'cycle_started',
        },
      );

      try {
        const cycle = events.find((event) => event.type === 'cycle_started');

        expect(
          events.filter((event) => event.type === 'retired_usage'),
        ).toMatchObject([
          {
            turnId: cycle?.type === 'cycle_started' ? cycle.turnId : '',
            cost: { amount: expect.closeTo(0.005, 9), currency: 'USD' },
          },
        ]);
        expect(costs(await readPast(record)).at(-1)).toMatchObject({
          cost: { amount: expect.closeTo(0.005, 9) },
        });
      } finally {
        await conversation.close();
      }
    }));

  test('a resumed session of an agent that keeps its cost with the session counts on from the cost its let-go turn said last', () =>
    withDir(async (dir) => {
      const { conversation, record } = await clearedIn(dir, 'costwaitlate', {
        agent: 'kilo',
      });

      await conversation.close();

      const [past] = await readRecords(join(dir, 'state')).then((all) =>
        all.filter((each) => each.path === record),
      );

      assert(past !== undefined);
      // The agent goes on from 0.02, as kilo would.
      await recordSession({
        stateDir: join(dir, 'state'),
        cwd: dir,
        command: fakeAgentCommand(
          undefined,
          '--resume-only',
          '--cost-from',
          '0.02',
        ),
        prompts: ['text'],
        agent: 'kilo',
        resume: { sessionId: past.sessionId, cwd: dir, record },
      });

      expect(costs(await readPast(record))).toStrictEqual([
        { model: 'fake-large', cost: { amount: 0.02, currency: 'USD' } },
        turn(0.0125),
      ]);
    }));
});

describe('CHD-373 S3c: a task running as its parent is let go', () => {
  test("its ending, what it spent with it, is its parent's still: in the old record and kept once by the window, and nothing else of it reaches the new session", () =>
    withDir(async (dir) => {
      const events: ConversationEvent[] = [];
      const recording = new FileRecording(join(dir, 'state'), () => {});

      const conversation = new Conversation(
        (signal) =>
          openSession({
            agent: 'claude',
            cwd: dir,
            agentCommand: fakeAgentCommand(),
            signal,
          }),
        (event) => events.push(event),
        Date.now,
        {},
        recording,
      );
      const until = async (check: () => boolean) => {
        while (!check()) {
          await new Promise((resolve) => setTimeout(resolve, 10));
        }
      };

      let child: Conversation | undefined;

      conversation.start();

      try {
        await until(() => events.some((event) => event.type === 'connected'));
        conversation.send('text', 'text');
        await until(() => events.some((event) => event.type === 'result'));

        const task = new TaskAgent(
          {
            id: 'count',
            name: 'Count the cost',
            runtime: 'fake',
            prompt: 'costwait',
          },
          conversation.taskParent('count'),
          Date.now,
        );

        child = new Conversation(
          (signal) =>
            openSession({
              agent: 'fake',
              cwd: dir,
              agentCommand: fakeAgentCommand(),
              signal,
            }),
          (event) => task.heard(event),
        );

        conversation.adopt(task, child);
        await until(() =>
          events.some(
            (event) =>
              event.type === 'update' &&
              event.subagentId === 'count' &&
              event.update.sessionUpdate === 'usage_update',
          ),
        );

        const record = recording.path!;
        const cleared = events.length;

        await conversation.clear();
        await recording.flushed();

        const spentOf = (update: SessionUpdate) =>
          (update._meta?.['chord/spent'] as { cost?: unknown } | undefined)
            ?.cost;
        const endings = events
          .slice(cleared)
          .flatMap((event) =>
            event.type === 'retired_update' &&
            event.update.sessionUpdate === 'subagent_update'
              ? [spentOf(event.update)]
              : [],
          );

        expect(endings).toStrictEqual([{ amount: 0.01, currency: 'USD' }]);
        // Its line that it stopped never reaches the new session.
        expect(
          events
            .slice(cleared)
            .some(
              (event) =>
                event.type === 'update' && event.subagentId === 'count',
            ),
        ).toBeFalsy();
        expect(
          (await readPast(record)).filter(
            (entry) =>
              entry.type === 'update' &&
              entry.update.sessionUpdate === 'subagent_update' &&
              spentOf(entry.update) !== undefined,
          ),
        ).toHaveLength(1);

        // The window takes them in as sessions.ts does.
        const at = events.findIndex((event) => event.type === 'cleared');
        const actions: WindowedAction[] = [
          ...events.slice(0, at).map((event): WindowedAction => ({
            type: 'in_session',
            key: 1,
            action: event,
          })),
          {
            type: 'spend_closing',
            key: -1,
            from: 1,
            place: { tab: 1, name: 'main', kind: 'main', agent: 'claude' },
          },
          ...events.slice(at).map((event): WindowedAction =>
            event.type === 'retired_update'
              ? {
                  type: 'retired_heard',
                  from: 1,
                  event: {
                    type: 'update',
                    turnId: event.turnId,
                    update: event.update,
                  },
                }
              : event.type === 'retired_usage'
                ? {
                    type: 'retired_heard',
                    from: 1,
                    event: { ...event, type: 'usage' },
                  }
                : { type: 'in_session', key: 1, action: event },
          ),
          { type: 'spend_closed', key: -1 },
        ];
        const window = actions.reduce(
          reduceWindowed,
          windowed(initialAppState, 1),
        );
        const tasks = window.window.keptSpend?.[0]?.part.parts ?? [];

        expect(
          tasks.map((part) => [part.name, part.figure?.cost?.amount]),
        ).toStrictEqual([['Count the cost', 0.01]]);
      } finally {
        await child?.close();
        await conversation.close();
      }
    }));
});

describe('CHD-467 tester: answer and cost settlement in either wire order', () => {
  function completed(
    events: readonly ConversationEvent[],
    amounts: readonly number[],
  ) {
    const prompts = events.flatMap((event, index) =>
      event.type === 'prompt' &&
      event.into === undefined &&
      !event.turnId.startsWith('history-')
        ? [{ event, index }]
        : [],
    );

    expect(prompts).toHaveLength(amounts.length);

    for (const [at, { event, index }] of prompts.entries()) {
      const end = prompts[at + 1]?.index ?? events.length;
      const between = events.slice(index + 1, end);

      expect(
        between.some(
          (next) =>
            next.type === 'result' &&
            next.turnId === event.turnId &&
            next.result.status === 'completed',
        ),
      ).toBe(true);
      expect(
        between.some(
          (next) =>
            next.type === 'update' &&
            next.update.sessionUpdate === 'usage_update' &&
            Math.abs((next.update.cost?.amount ?? -1) - amounts[at]!) < 1e-9,
        ),
      ).toBe(true);
    }
  }

  test('each successive prompt waits for both prior arrivals and keeps a distinct final cost', () =>
    withDir(async (dir) => {
      const events: ConversationEvent[] = [];

      await recordSession({
        stateDir: join(dir, 'state'),
        cwd: dir,
        command: fakeAgentCommand(undefined, '--late-cost'),
        prompts: ['text', 'text', 'text', 'text'],
        agent: 'claude',
        lateCost: true,
        heard: (event) => events.push(event),
      });
      completed(events, [0.0125, 0.025, 0.0375, 0.05]);

      const entries = await readPast((await theRecord(dir)).path);
      const ids = new Set(
        entries.flatMap((entry) =>
          entry.type === 'usage' ? [entry.turnId] : [],
        ),
      );

      expect(ids.size).toBe(4);
      expect(costs(entries)).toEqual(
        Array.from({ length: 4 }, () => turn(0.0125)),
      );
    }));

  test('concurrent recordings cannot satisfy another session answer or cost wait', () =>
    withDir(async (dir) => {
      await Promise.all(
        [2, 3].map(async (count) => {
          const cwd = join(dir, `session-${count}`);
          const events: ConversationEvent[] = [];

          await mkdir(cwd);
          await recordSession({
            stateDir: join(cwd, 'state'),
            cwd,
            command: fakeAgentCommand(undefined, '--late-cost'),
            prompts: Array.from({ length: count }, () => 'text'),
            agent: 'claude',
            lateCost: true,
            heard: (event) => events.push(event),
          });
          completed(
            events,
            Array.from({ length: count }, (_, index) => (index + 1) * 0.0125),
          );
          expect(costs(await readPast((await theRecord(cwd)).path))).toEqual(
            Array.from({ length: count }, () => turn(0.0125)),
          );
        }),
      );
    }));

  test('resuming a recorded session keeps the prior baseline while waiting for each new answer and cost', () =>
    withDir(async (dir) => {
      const stateDir = join(dir, 'state');
      const id = await recordSession({
        stateDir,
        cwd: dir,
        command: fakeAgentCommand(undefined, '--late-cost'),
        prompts: ['text', 'text'],
        agent: 'kilo',
        lateCost: true,
      });
      const record = await theRecord(dir);
      const before = await readPast(record.path);
      const events: ConversationEvent[] = [];

      await recordSession({
        stateDir,
        cwd: dir,
        command: fakeAgentCommand(
          undefined,
          '--resume-only',
          '--late-cost',
          '--cost-from',
          '0.025',
        ),
        prompts: ['text', 'text'],
        agent: 'kilo',
        lateCost: true,
        resume: { sessionId: id, cwd: dir, record: record.path },
        heard: (event) => events.push(event),
      });
      completed(events, [0.0375, 0.05]);

      const after = await readPast(record.path);

      expect(after.slice(0, before.length)).toEqual(before);
      expect(costs(after)).toEqual(
        Array.from({ length: 4 }, () => turn(0.0125)),
      );
      expect(after.filter((entry) => entry.type === 'opened')).toHaveLength(2);
    }));

  test('each opening keeps its startup commands without fixing their position relative to the first prompt', () =>
    withDir(async (dir) => {
      const entries = await resumed(dir, { agent: 'claude' });
      const openings = entries.flatMap((entry, index) =>
        entry.type === 'opened' ? [index] : [],
      );

      expect(openings).toHaveLength(2);
      expect(entries.filter((entry) => entry.type === 'session')).toHaveLength(
        1,
      );

      for (const [at, index] of openings.entries()) {
        const own = entries.slice(index, openings[at + 1] ?? entries.length);
        const metadata = own
          .filter((entry) => entry.type !== 'update')
          .map((entry) => entry.type);
        const commands = own.filter(
          (entry) =>
            entry.type === 'update' &&
            entry.update.sessionUpdate === 'available_commands_update',
        );

        expect(metadata.slice(0, 3)).toEqual(['opened', 'state', 'prompt']);
        expect(own.filter((entry) => entry.type === 'prompt')).toHaveLength(2);
        expect(commands).toHaveLength(1);
      }

      expect(costs(entries)).toEqual(
        Array.from({ length: 4 }, () => turn(0.0125)),
      );
    }));
});
