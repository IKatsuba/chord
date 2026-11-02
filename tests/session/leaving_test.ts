import { describe, expect, test } from 'bun:test';
import process from 'node:process';
import { type GroupProcess, spawnGroup } from '../../src/platform/process.ts';
import {
  createLeaving,
  type LeaveExit,
  type LeaveOptions,
  type LeaveStep,
} from '../../src/session/leaving.ts';
import { until } from './conversation_fake.ts';

const NEVER = new Promise<void>(() => {});

function sleeper(): GroupProcess {
  return spawnGroup('sh', ['-c', 'sleep 60'], {
    cwd: process.cwd(),
    stdin: 'ignore',
    stdout: 'ignore',
    stderr: 'ignore',
  });
}

function setUp(options: Partial<LeaveOptions> = {}) {
  const lines: string[] = [];
  const exits: LeaveExit[] = [];
  const calls: string[] = [];
  const leaving = createLeaving({
    answer: () => calls.push('answer'),
    drained: () => Promise.resolve(),
    closeConnection: () => {
      calls.push('close');
    },
    steps: [],
    stderr: (line) => lines.push(line),
    exit: (how) => exits.push(how),
    ...options,
  });

  return { leaving, lines, exits, calls };
}

describe('leaving', () => {
  test('EOF sends no answers and exits 0 when clean', async () => {
    const { leaving, exits, calls, lines } = setUp();

    await leaving.leave({ kind: 'eof' });

    expect(calls).toEqual(['close']);
    expect(exits).toEqual([{ code: 0 }]);
    expect(lines).toEqual([]);
  });

  test('a signal answers first, then dies by that signal', async () => {
    const { leaving, exits, calls } = setUp();

    await leaving.leave({ kind: 'signal', signal: 'SIGTERM' });

    expect(calls).toEqual(['answer', 'close']);
    expect(exits).toEqual([{ signal: 'SIGTERM' }]);
  });

  test('a crash answers and exits 1; a broken connection does not answer', async () => {
    const crash = setUp();
    const broken = setUp();

    await crash.leaving.leave({ kind: 'crash' });
    await broken.leaving.leave({ kind: 'broken' });

    expect(crash.calls).toEqual(['answer', 'close']);
    expect(crash.exits).toEqual([{ code: 1 }]);
    expect(broken.calls).toEqual(['close']);
    expect(broken.exits).toEqual([{ code: 1 }]);
  });

  test('runs once, whatever asks again', async () => {
    const { leaving, exits, calls } = setUp();
    const first = leaving.leave({ kind: 'eof' });

    expect(leaving.leave({ kind: 'signal', signal: 'SIGINT' })).toBe(first);

    await first;

    expect(calls).toEqual(['close']);
    expect(exits).toEqual([{ code: 0 }]);
  });

  test('new work is refused from before the answers go', async () => {
    let seen = false;
    const holder: { leaving?: ReturnType<typeof createLeaving> } = {};
    const { leaving } = setUp({
      answer: () => {
        seen = holder.leaving?.started() ?? false;
      },
    });

    holder.leaving = leaving;

    expect(leaving.started()).toBe(false);

    await leaving.leave({ kind: 'signal', signal: 'SIGINT' });

    expect(seen).toBe(true);
  });

  test('a drain that never ends waits only its bound', async () => {
    const { leaving, calls, exits } = setUp({
      drained: () => NEVER,
      drainMs: 10,
    });

    await leaving.leave({ kind: 'signal', signal: 'SIGHUP' });

    expect(calls).toEqual(['answer', 'close']);
    expect(exits).toEqual([{ signal: 'SIGHUP' }]);
  });

  test('a drain that fails is kept, and the connection still closes', async () => {
    const { leaving, calls, exits, lines } = setUp({
      drained: () => Promise.reject(new Error('EPIPE')),
    });

    await leaving.leave({ kind: 'eof' });

    expect(calls).toEqual(['close']);
    expect(lines).toEqual(['chord: drain: EPIPE']);
    expect(exits).toEqual([{ code: 1 }]);
  });

  test('a stderr that throws does not stop the way out', async () => {
    const { leaving, exits } = setUp({
      stderr: () => {
        throw new Error('EPIPE');
      },
      steps: [
        {
          name: 'host',
          run: () => {
            throw new Error('no');
          },
        },
      ],
    });

    await leaving.leave({ kind: 'eof' });

    expect(exits).toEqual([{ code: 1 }]);
  });

  test('failure kept: each failure on stderr, the rest run, exit 1 on EOF', async () => {
    let ran = false;
    const { leaving, exits, lines } = setUp({
      steps: [
        {
          name: 'host',
          run: () => {
            throw new Error('flush failed');
          },
        },
        { name: 'probes', run: () => Promise.reject(new Error('stuck')) },
        {
          name: 'readers',
          run: () => {
            ran = true;
          },
        },
      ],
    });

    await leaving.leave({ kind: 'eof' });

    expect(ran).toBe(true);
    expect(lines).toEqual([
      'chord: host: flush failed',
      'chord: probes: stuck',
    ]);
    expect(exits).toEqual([{ code: 1 }]);
  });

  test('a failure under a signal still dies by the signal', async () => {
    const { leaving, exits } = setUp({
      answer: () => {
        throw new Error('no connection');
      },
    });

    await leaving.leave({ kind: 'signal', signal: 'SIGTERM' });

    expect(exits).toEqual([{ signal: 'SIGTERM' }]);
  });

  test('all settled: what the registry still holds has SIGKILL', async () => {
    const left = sleeper();

    await left.started;

    const { leaving, exits } = setUp();

    await leaving.leave({ kind: 'eof' });

    expect(exits).toEqual([{ code: 0 }]);

    await until(() => !left.alive());
  });
});

describe('expiry', () => {
  const expiries: [string, string][] = [
    ['task or child', 'task'],
    ['monitor', 'monitor'],
    ['collector', 'collector'],
    ['blocked flush', 'record'],
  ];

  for (const [kind, name] of expiries) {
    test(`expiry, ${kind}: stderr names it and its group, which dies`, async () => {
      const held = sleeper();

      await held.started;

      const hung: LeaveStep = { name, run: () => NEVER };
      const { leaving, exits, lines } = setUp({
        steps: [hung],
        leaveMs: 50,
      });
      const started = performance.now();

      await leaving.leave({ kind: 'eof' });

      expect(performance.now() - started).toBeLessThan(5_000);
      expect(lines).toEqual([
        `chord: not settled at the deadline: ${name}`,
        `chord: killed process group ${held.pid}`,
      ]);
      expect(exits).toEqual([{ code: 1 }]);

      await until(() => !held.alive());
    });
  }

  test('expiry, a signal still dies by it', async () => {
    const { leaving, exits } = setUp({
      steps: [{ name: 'host', run: () => NEVER }],
      leaveMs: 20,
    });

    await leaving.leave({ kind: 'signal', signal: 'SIGTERM' });

    expect(exits).toEqual([{ signal: 'SIGTERM' }]);
  });

  test('a collector closes before a hung host settles', async () => {
    let closed = false;
    const { leaving, lines } = setUp({
      steps: [
        { name: 'host', run: () => NEVER },
        {
          name: 'collector',
          run: () => {
            closed = true;
          },
        },
      ],
      leaveMs: 20,
    });

    await leaving.leave({ kind: 'eof' });

    expect(closed).toBe(true);
    expect(lines).toEqual(['chord: not settled at the deadline: host']);
  });

  test('a hung drain cannot hold the connection past its bound', async () => {
    const { leaving, calls, lines } = setUp({
      drained: () => NEVER,
      drainMs: 5,
      closeConnection: () => {
        calls.push('close');

        return NEVER;
      },
      leaveMs: 50,
    });

    await leaving.leave({ kind: 'eof' });

    expect(calls).toEqual(['close']);
    expect(lines).toEqual(['chord: not settled at the deadline: connection']);
  });

  test('a late settle after the deadline exits nothing more', async () => {
    const late = Promise.withResolvers<void>();
    const { leaving, exits } = setUp({
      steps: [{ name: 'host', run: () => late.promise }],
      leaveMs: 10,
    });

    await leaving.leave({ kind: 'eof' });

    late.resolve();

    await new Promise((resolve) => setTimeout(resolve, 5));

    expect(exits).toEqual([{ code: 1 }]);
  });
});
