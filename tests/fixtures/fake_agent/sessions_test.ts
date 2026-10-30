import { describe, expect, test } from 'bun:test';
import process from 'node:process';
import { tmpdir } from 'node:os';
import { openSession, type Session } from '../../../src/session/session.ts';
import { fakeAgentCommand } from '../fake.ts';
import { steeredInto, steers } from './sessions.ts';

test('a wait for a steered message settles on one, and stops listening (CHD-470)', async () => {
  const waiting = steeredInto('s1', new AbortController().signal);

  steers.emit('s1');
  await waiting.steered;
  waiting.stop();
  expect(steers.listenerCount('s1')).toBe(0);
});

test('a wait the turn ends before awaiting stops listening and raises nothing unhandled (CHD-470)', async () => {
  const unhandled: unknown[] = [];
  const heard = (reason: unknown) => unhandled.push(reason);

  process.on('unhandledRejection', heard);

  try {
    // Cancelled while it set up, never awaited.
    const turn = new AbortController();
    const cancelled = steeredInto('s2', turn.signal);

    turn.abort();
    cancelled.stop();

    // Its setup threw: stopped, never awaited.
    steeredInto('s3', new AbortController().signal).stop();

    await new Promise((resolve) => setTimeout(resolve, 20));

    expect(unhandled).toStrictEqual([]);
    expect(steers.listenerCount('s2') + steers.listenerCount('s3')).toBe(0);
    await expect(cancelled.steered).rejects.toThrow();
  } finally {
    process.off('unhandledRejection', heard);
  }
});

describe('CHD-470 tester: steering waiter isolation and cancellation', () => {
  test('an already cancelled turn installs no steering or error listener', async () => {
    const errors = steers.listenerCount('error');
    const turn = new AbortController();

    turn.abort();

    const waiting = steeredInto('tester-pre-cancelled', turn.signal);

    try {
      await expect(waiting.steered).rejects.toThrow();
      expect(steers.listenerCount('tester-pre-cancelled')).toBe(0);
      expect(steers.listenerCount('error')).toBe(errors);
    } finally {
      waiting.stop();
    }
  });

  test('steering one session leaves another pending until that turn is cancelled', async () => {
    const errors = steers.listenerCount('error');
    const first = steeredInto('tester-first', new AbortController().signal);
    const turn = new AbortController();
    const second = steeredInto('tester-second', turn.signal);
    let settled = false;

    void second.steered.then(
      () => {
        settled = true;
      },
      () => {
        settled = true;
      },
    );

    try {
      steers.emit('tester-first');
      await first.steered;
      await Promise.resolve();
      expect(settled).toBe(false);
      expect(steers.listenerCount('tester-second')).toBe(1);
      turn.abort();
      await expect(second.steered).rejects.toThrow();
      expect(steers.listenerCount('tester-first')).toBe(0);
      expect(steers.listenerCount('tester-second')).toBe(0);
      expect(steers.listenerCount('error')).toBe(errors);
    } finally {
      first.stop();
      second.stop();
    }
  });

  test('repeated cleanup of an abandoned setup does not detach a new waiter for the same session', async () => {
    const errors = steers.listenerCount('error');
    const old = steeredInto('tester-reused', new AbortController().signal);
    const current = steeredInto('tester-reused', new AbortController().signal);

    try {
      old.stop();
      old.stop();
      await expect(old.steered).rejects.toThrow();
      expect(steers.listenerCount('tester-reused')).toBe(1);
      steers.emit('tester-reused');
      await current.steered;
      expect(steers.listenerCount('tester-reused')).toBe(0);
      expect(steers.listenerCount('error')).toBe(errors);
    } finally {
      old.stop();
      current.stop();
    }
  });
});

describe("what the screenshots ask of the fake's sessions (CHD-560)", () => {
  const SOURCE = '11111111-1111-4111-8111-111111111111';
  /** What `read` finds of a session opened with `flags`, closed after. */
  const opened = async <T>(
    flags: readonly string[],
    read: (session: Session) => T,
    fork?: string,
  ): Promise<T> => {
    const session = await openSession({
      agent: 'fake',
      cwd: tmpdir(),
      agentCommand: fakeAgentCommand(undefined, ...flags),
      ...(fork === undefined ? {} : { fork }),
    });

    try {
      return read(session);
    } finally {
      await session.close();
    }
  };

  const modes = (session: Session) =>
    session.modes()?.available.map(({ id }) => id);
  const model = (session: Session) => session.models()?.current;

  test('its modes are the three, and --auto-mode adds auto after them', async () => {
    expect(await opened([], modes)).toEqual(['default', 'acceptEdits', 'plan']);
    expect(await opened(['--auto-mode'], modes)).toEqual([
      'default',
      'acceptEdits',
      'plan',
      'auto',
    ]);
  });

  test('a fork is on its first model, and on the one --fork-model names', async () => {
    expect(await opened(['--fork'], model, SOURCE)).toBe('fake-large');
    expect(
      await opened(['--fork', '--fork-model', 'fake-small'], model, SOURCE),
    ).toBe('fake-small');
  });
});

describe('CHD-560 U2 tester: screenshot flag isolation', () => {
  const source = '22222222-2222-4222-8222-222222222222';
  const withFlags = async <T>(
    env: readonly string[],
    flags: readonly string[],
    read: (session: Session) => Promise<T> | T,
    fork?: string,
  ): Promise<T> => {
    const session = await openSession({
      agent: 'fake',
      cwd: tmpdir(),
      agentCommand: [
        'env',
        '-u',
        'CHORD_FAKE_AUTO_MODE',
        '-u',
        'CHORD_FAKE_FORK_MODEL',
        ...env,
        ...fakeAgentCommand(undefined, ...flags),
      ],
      ...(fork === undefined ? {} : { fork }),
    });

    try {
      return await read(session);
    } finally {
      await session.close();
      await session.exited;
      expect(session.agentPids.size).toBe(0);
    }
  };

  test('environment-enabled auto is selectable while another process keeps the default modes', async () => {
    await Promise.all([
      withFlags(['CHORD_FAKE_AUTO_MODE=1'], [], async (session) => {
        expect(session.modes()?.available.map(({ id }) => id)).toStrictEqual([
          'default',
          'acceptEdits',
          'plan',
          'auto',
        ]);
        await session.setMode('auto');
        expect(session.modes()?.current).toBe('auto');
      }),
      withFlags([], [], (session) => {
        expect(session.modes()?.available.map(({ id }) => id)).toStrictEqual([
          'default',
          'acceptEdits',
          'plan',
        ]);
        expect(session.modes()?.current).toBe('default');
      }),
    ]);
  });

  test('only the documented environment value enables auto, while the flag still enables it', async () => {
    for (const value of ['0', 'true']) {
      expect(
        await withFlags([`CHORD_FAKE_AUTO_MODE=${value}`], [], (session) =>
          session.modes()?.available.some(({ id }) => id === 'auto'),
        ),
      ).toBe(false);
    }

    expect(
      await withFlags(['CHORD_FAKE_AUTO_MODE=0'], ['--auto-mode'], (session) =>
        session.modes()?.available.some(({ id }) => id === 'auto'),
      ),
    ).toBe(true);
  });

  test('the fork model environment affects forks only and the explicit flag wins', async () => {
    const model = (session: Session) => session.models()?.current;
    const env = ['CHORD_FAKE_FORK_MODEL=fake-small'];

    expect(await withFlags(env, ['--fork'], model, source)).toBe('fake-small');
    expect(await withFlags(env, ['--fork'], model)).toBe('fake-large');
    expect(
      await withFlags(
        env,
        ['--fork', '--fork-model', 'fake-large'],
        model,
        source,
      ),
    ).toBe('fake-large');
    expect(await withFlags([], ['--fork'], model, source)).toBe('fake-large');
  });
});
