import { afterEach, describe, expect, jest, test } from 'bun:test';
import type {
  InteractionUpdate,
  RunResult,
  SDKMessage,
  SendOptions,
} from '@cursor/sdk';
import type { SessionUpdate } from '@agentclientprotocol/sdk/unstable';
import { CursorError } from '../src/errors.ts';
import type { PortRun } from '../src/port.ts';
import { Turn } from '../src/turn.ts';

const ID = 'bc-1';
const LINK = `https://cursor.com/agents/${ID}`;

afterEach(() => {
  jest.useRealTimers();
});

/** A promise with its settlers outside. */
function deferred<T>() {
  let resolve!: (value: T) => void;
  let reject!: (error: unknown) => void;
  const promise = new Promise<T>((yes, no) => {
    resolve = yes;
    reject = no;
  });

  return { promise, resolve, reject };
}

/** A run whose wait, cancel and stream the test drives. */
function fakeRun() {
  const result = deferred<RunResult>();
  const queue: SDKMessage[] = [];
  let wake = () => undefined as void;
  let streamError: unknown;
  let ended = false;
  const cancels: number[] = [];
  let cancelAnswer = (): Promise<void> => Promise.resolve();
  const run: PortRun = {
    id: 'run-1',
    agentId: ID,
    supports: () => true,
    unsupportedReason: () => undefined,
    conversation: () => Promise.resolve([]),
    wait: () => result.promise,
    cancel: () => {
      cancels.push(Date.now());

      return cancelAnswer();
    },
    async *stream() {
      for (;;) {
        if (queue.length > 0) {
          yield queue.shift()!;
          continue;
        }

        if (streamError !== undefined) {
          throw streamError;
        }

        if (ended) {
          return;
        }

        await new Promise<void>((resolve) => {
          wake = resolve;
        });
      }
    },
  };

  return {
    run,
    cancels,
    finish: (value: Partial<RunResult> = {}) =>
      result.resolve({ id: 'run-1', status: 'finished', ...value }),
    message: (message: SDKMessage) => {
      queue.push(message);
      wake();
    },
    fail: (error: unknown) => {
      streamError = error;

      wake();
    },
    end: () => {
      ended = true;

      wake();
    },
    cancelWith: (answer: () => Promise<void>) => {
      cancelAnswer = answer;
    },
  };
}

/** A turn over `fake`, its send held until `release`, recording what it drew. */
function turnOver(fake: ReturnType<typeof fakeRun>, bound = 10_000) {
  const drawn: SessionUpdate[] = [];
  const sent = deferred<void>();
  let onDelta: NonNullable<SendOptions['onDelta']> | undefined;
  const turn = new Turn({
    agentId: ID,
    bound,
    send: async (delta) => {
      onDelta = delta;

      await sent.promise;

      return fake.run;
    },
    artifacts: () => Promise.resolve([]),
    emit: (update) => {
      drawn.push(update);

      return Promise.resolve();
    },
  });

  return {
    turn,
    drawn,
    release: () => sent.resolve(),
    delta: (update: InteractionUpdate) => onDelta!({ update }),
    texts: () =>
      drawn.flatMap((update) =>
        update.sessionUpdate === 'agent_message_chunk' &&
        update.content.type === 'text'
          ? [update.content.text]
          : [],
      ),
  };
}

/** Lets pending promise callbacks run. */
const settle = () => new Promise((resolve) => setImmediate(resolve));

test('a finished run ends the turn with its usage and its end lines', async () => {
  const fake = fakeRun();
  const at = turnOver(fake);
  const answer = at.turn.run();

  at.release();
  await settle();
  await at.delta({ type: 'text-delta', text: 'Done.' });
  fake.finish({
    usage: {
      inputTokens: 1,
      outputTokens: 2,
      cacheReadTokens: 0,
      cacheWriteTokens: 0,
      totalTokens: 3,
    },
    git: { branches: [{ repoUrl: 'https://github.com/a/b', branch: 'x' }] },
  });

  expect(await answer).toEqual({
    stopReason: 'end_turn',
    usage: {
      totalTokens: 3,
      inputTokens: 1,
      outputTokens: 2,
      cachedReadTokens: 0,
      cachedWriteTokens: 0,
    },
  });
  expect(at.texts()).toEqual(['Done.', 'Pushed to x on github.com/a/b.']);
});

test('the model a run used is reported', async () => {
  const fake = fakeRun();
  const models: unknown[] = [];
  const turn = new Turn({
    agentId: ID,
    send: () => Promise.resolve(fake.run),
    artifacts: () => Promise.resolve([]),
    emit: () => Promise.resolve(),
    ran: (model) => models.push(model),
  });
  const answer = turn.run();

  await settle();
  fake.finish({ model: { id: 'composer-2' } });
  await answer;
  expect(models).toEqual([{ id: 'composer-2' }]);
});

test("a run that errs fails the turn with the SDK's message", async () => {
  const fake = fakeRun();
  const at = turnOver(fake);
  const answer = at.turn.run();

  at.release();
  fake.finish({
    status: 'error',
    error: { message: 'The VM ran out of disk' },
  });
  await expect(answer).rejects.toMatchObject({
    code: -32603,
    message: 'The VM ran out of disk',
  });
});

test('a send that fails fails the turn with its error', async () => {
  const error = new CursorError('busy', 'Agent has an active run');
  const turn = new Turn({
    agentId: ID,
    send: () => Promise.reject(error),
    artifacts: () => Promise.resolve([]),
    emit: () => Promise.resolve(),
  });

  await expect(turn.run()).rejects.toBe(error);
});

describe('cancel', () => {
  test('before send gives a run: held, then applied to it', async () => {
    const fake = fakeRun();
    const at = turnOver(fake);
    const answer = at.turn.run();

    at.turn.cancel();
    expect(fake.cancels).toEqual([]);
    at.release();
    await settle();
    expect(fake.cancels).toHaveLength(1);
    fake.finish({ status: 'cancelled' });
    expect(await answer).toEqual({ stopReason: 'cancelled' });
  });

  test('during the run: forwards what arrives until it ends, then cancelled once', async () => {
    const fake = fakeRun();
    const at = turnOver(fake);
    const answer = at.turn.run();

    at.release();
    await settle();
    at.turn.cancel();
    expect(fake.cancels).toHaveLength(1);
    await at.delta({ type: 'text-delta', text: 'stopping' });
    expect(at.texts()).toEqual(['stopping']);
    // A run Cursor reports finished after a cancel is still answered cancelled.
    fake.finish({ status: 'finished' });
    expect(await answer).toEqual({ stopReason: 'cancelled' });
  });

  test('twice, or after the answer, does nothing', async () => {
    const fake = fakeRun();
    const at = turnOver(fake);
    const answer = at.turn.run();

    at.release();
    await settle();
    at.turn.cancel();
    at.turn.cancel();
    expect(fake.cancels).toHaveLength(1);
    fake.finish({ status: 'cancelled' });
    await answer;
    at.turn.cancel();
    expect(fake.cancels).toHaveLength(1);
  });

  test('unconfirmed within the bound: the line, then cancelled', async () => {
    jest.useFakeTimers();

    const fake = fakeRun();
    const at = turnOver(fake);
    const answer = at.turn.run();

    at.release();
    await settle();
    at.turn.cancel();
    jest.advanceTimersByTime(9_999);
    await settle();
    expect(at.texts()).toEqual([]);
    jest.advanceTimersByTime(1);
    expect(await answer).toEqual({ stopReason: 'cancelled' });
    expect(at.texts()).toEqual([
      `Cursor did not confirm the stop; the run may still be going: ${LINK}`,
    ]);
  });

  test('a cancel Cursor refuses answers at once, unconfirmed', async () => {
    const fake = fakeRun();
    const at = turnOver(fake);

    fake.cancelWith(() =>
      Promise.reject(new CursorError('network', 'Service unavailable')),
    );

    const answer = at.turn.run();

    at.release();
    await settle();
    at.turn.cancel();
    expect(await answer).toEqual({ stopReason: 'cancelled' });
    expect(at.texts()).toEqual([
      `Cursor did not confirm the stop; the run may still be going: ${LINK}`,
    ]);
  });
});

test("an answered turn's late events are dropped, so turn A never draws into turn B", async () => {
  const first = fakeRun();
  const a = turnOver(first);
  const answerA = a.turn.run();

  a.release();
  await settle();
  first.finish();
  await answerA;

  const lateDelta = a.delta({ type: 'text-delta', text: 'late' });

  first.message({
    type: 'task',
    agent_id: ID,
    run_id: 'run-1',
    text: 'late task',
  });
  await lateDelta;
  await settle();
  expect(a.texts()).toEqual([]);
});

describe('the stream', () => {
  test('draws status, task and request lines', async () => {
    const fake = fakeRun();
    const at = turnOver(fake);
    const answer = at.turn.run();

    at.release();
    await settle();
    fake.message({
      type: 'status',
      agent_id: ID,
      run_id: 'r',
      status: 'CREATING',
    });
    fake.message({
      type: 'status',
      agent_id: ID,
      run_id: 'r',
      status: 'RUNNING',
    });
    fake.message({ type: 'task', agent_id: ID, run_id: 'r', text: 'Planning' });
    fake.message({
      type: 'request',
      agent_id: ID,
      run_id: 'r',
      request_id: 'r-81c2',
    });
    await settle();
    fake.finish();
    await answer;
    expect(at.texts()).toEqual([
      "Cursor is starting the agent's machine…",
      'Planning',
      `Cursor's agent is waiting for input or approval (request r-81c2). This adapter cannot answer it; Esc stops the run.\n${LINK}`,
    ]);
  });

  test('lost to the network: the turn fails with the link', async () => {
    const fake = fakeRun();
    const at = turnOver(fake);
    const answer = at.turn.run();

    at.release();
    await settle();
    fake.fail(new CursorError('network', 'Connection reset'));
    await expect(answer).rejects.toMatchObject({
      code: -32603,
      message: `Lost the connection to Cursor; the agent keeps running there: ${LINK}. Reopen the session to see where it got to.`,
    });
  });

  test("failing otherwise: the turn fails with the stream's error", async () => {
    const fake = fakeRun();
    const at = turnOver(fake);
    const answer = at.turn.run();
    const error = new CursorError('rate-limit', 'Too many requests');

    at.release();
    await settle();
    fake.fail(error);
    await expect(answer).rejects.toBe(error);
  });

  test('ending before the run leaves the answer to wait()', async () => {
    const fake = fakeRun();
    const at = turnOver(fake);
    const answer = at.turn.run();

    at.release();
    await settle();
    fake.end();
    await settle();
    fake.finish();
    expect((await answer).stopReason).toBe('end_turn');
  });
});
