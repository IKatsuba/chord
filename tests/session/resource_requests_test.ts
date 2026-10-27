import { describe, expect, test } from 'bun:test';
import { getEventListeners } from 'node:events';
import {
  ResourceRequests,
  RESOURCE_REQUEST_MS,
} from '../../src/session/resource_requests.ts';

function fixture() {
  let now = 100;
  let released = 0;
  const timers = new Map<() => void, number>();
  const calls: { agents: readonly string[]; signal: AbortSignal }[] = [];
  const requests = new ResourceRequests(
    (agents, signal) => {
      calls.push({ agents, signal });

      return () => {
        released += 1;
      };
    },
    {
      now: () => now,
      after: (milliseconds, release) => {
        timers.set(release, now + milliseconds);

        return () => {
          timers.delete(release);
        };
      },
    },
  );
  const caller = {};
  const generation = {};
  const abort = new AbortController();
  const request = () => ({
    caller,
    generation,
    agents: ['codex'],
    signal: abort.signal,
    valid: () => true,
    admittedAt: now,
  });

  return {
    requests,
    request,
    calls,
    timers,
    abort,
    released: () => released,
    advance: (milliseconds: number) => {
      now += milliseconds;

      for (const [release, at] of timers) {
        if (at <= now) {
          timers.delete(release);
          release();
        }
      }
    },
  };
}

test('same normalized filter retains once, refreshes cancellation listener and never extends expiry', () => {
  const f = fixture();
  const next = new AbortController();

  f.requests.retain({ ...f.request(), agents: ['codex', 'claude', 'codex'] });
  f.advance(20_000);
  f.requests.retain({
    ...f.request(),
    agents: ['claude', 'codex'],
    signal: next.signal,
  });
  expect(f.calls).toHaveLength(1);
  expect(f.calls[0]?.agents).toEqual(['claude', 'codex']);
  expect(f.timers.size).toBe(1);
  expect(getEventListeners(f.abort.signal, 'abort')).toHaveLength(0);
  expect(getEventListeners(next.signal, 'abort')).toHaveLength(1);
  f.abort.abort();
  expect(f.released()).toBe(0);
  f.advance(10_000);
  expect(f.released()).toBe(1);
  expect(f.calls[0]?.signal.aborted).toBe(true);
  expect(f.timers.size).toBe(0);
  expect(getEventListeners(next.signal, 'abort')).toHaveLength(0);
  next.abort();
  f.requests.close();
  expect(f.released()).toBe(1);
});

test('expiry works with no active turn and does not release independent owners', () => {
  const f = fixture();
  const other = new AbortController();

  f.requests.retain(f.request());
  f.requests.retain({ ...f.request(), caller: {}, signal: other.signal });
  f.requests.release(f.request().caller);
  expect(f.released()).toBe(1);
  expect(f.calls[1]?.signal.aborted).toBe(false);
  f.advance(RESOURCE_REQUEST_MS);
  expect(f.released()).toBe(2);
  expect(f.timers.size).toBe(0);
});

test('replacement and actual terminal identities cannot release a later owner', () => {
  const f = fixture();
  const next = new AbortController();

  f.requests.retain({ ...f.request(), turnId: 'old' });

  const staleExpiry = [...f.timers.keys()][0]!;

  f.requests.retain({
    ...f.request(),
    generation: {},
    agents: ['claude'],
    signal: next.signal,
    turnId: 'new',
  });
  expect(f.released()).toBe(1);
  staleExpiry();
  f.abort.abort();
  f.requests.ended(f.request().caller, 'old');
  expect(f.released()).toBe(1);
  expect(f.calls[1]?.signal.aborted).toBe(false);
  f.requests.ended(f.request().caller, 'new');
  expect(f.released()).toBe(2);
  expect(f.timers.size).toBe(0);
});

test('filter replacement and empty filter release prior interest without a new retain', () => {
  const f = fixture();

  f.requests.retain(f.request());
  f.requests.retain({ ...f.request(), agents: ['claude'] });
  expect(f.released()).toBe(1);
  expect(f.calls).toHaveLength(2);
  f.requests.retain({ ...f.request(), agents: [] });
  expect(f.released()).toBe(2);
  expect(f.calls).toHaveLength(2);
  expect(f.timers.size).toBe(0);
});

test('late, invalid and cancelled admissions cannot attach interest', () => {
  const f = fixture();
  const early = f.request();

  f.advance(RESOURCE_REQUEST_MS);
  f.requests.retain(early);
  f.requests.retain({ ...f.request(), valid: () => false });
  f.abort.abort();
  f.requests.retain(f.request());
  expect(f.calls).toHaveLength(0);
  expect(f.timers.size).toBe(0);
});

test('cancellation during retain drains returned resources once without retaining a timer', () => {
  const abort = new AbortController();
  let releases = 0;
  let cancelledTimer = 0;
  const requests = new ResourceRequests(
    () => {
      abort.abort();

      return () => {
        releases += 1;
      };
    },
    {
      now: () => 10,
      after: () => () => {
        cancelledTimer += 1;
      },
    },
  );

  requests.retain({
    caller: {},
    generation: {},
    agents: ['codex'],
    signal: abort.signal,
    valid: () => true,
    admittedAt: 10,
  });
  requests.close();
  expect(releases).toBe(1);
  expect(cancelledTimer).toBe(1);
  expect(getEventListeners(abort.signal, 'abort')).toHaveLength(0);
});

test('a throwing retain removes the current owner and its listener', () => {
  const abort = new AbortController();
  let cancelledTimer = 0;
  const requests = new ResourceRequests(
    () => {
      throw new Error('fixture');
    },
    {
      now: () => 10,
      after: () => () => {
        cancelledTimer += 1;
      },
    },
  );

  expect(() =>
    requests.retain({
      caller: {},
      generation: {},
      agents: ['codex'],
      signal: abort.signal,
      valid: () => true,
      admittedAt: 10,
    }),
  ).toThrow('fixture');
  expect(getEventListeners(abort.signal, 'abort')).toHaveLength(0);
  expect(cancelledTimer).toBe(1);
  requests.close();
  expect(cancelledTimer).toBe(1);
});

test('the existing service receives live caller validity without owning unrelated generations', () => {
  let valid = true;
  let check: (() => boolean) | undefined;
  const requests = new ResourceRequests(
    (_agents, _signal, current) => {
      check = current;

      return () => {};
    },
    { now: () => 10, after: () => () => {} },
  );
  const caller = {};

  requests.retain({
    caller,
    generation: {},
    agents: ['codex'],
    signal: new AbortController().signal,
    valid: () => valid,
    admittedAt: 10,
  });
  expect(check?.()).toBe(true);

  valid = false;

  expect(check?.()).toBe(false);
  requests.release(caller);

  valid = true;

  expect(check?.()).toBe(false);
});

test('invalid late admissions cannot release a replacement generation or its expiry', () => {
  const f = fixture();
  const old = f.request();

  f.requests.retain({ ...old, turnId: 'old' });
  f.advance(20_000);
  f.requests.retain({
    ...f.request(),
    generation: {},
    agents: ['claude'],
    turnId: 'replacement',
  });
  f.advance(10_000);

  const cancelled = new AbortController();

  cancelled.abort();
  f.requests.retain({
    ...f.request(),
    generation: old.generation,
    valid: () => false,
  });
  f.requests.retain({
    ...f.request(),
    generation: old.generation,
    signal: cancelled.signal,
  });
  f.requests.retain(old);
  f.requests.retain({
    ...f.request(),
    generation: old.generation,
    agents: [],
    valid: () => false,
  });
  f.requests.ended(old.caller, 'old');
  expect(f.calls).toHaveLength(2);
  expect(f.released()).toBe(1);
  expect(f.calls[1]?.signal.aborted).toBe(false);
  expect(f.timers.size).toBe(1);
  f.advance(19_999);
  expect(f.released()).toBe(1);
  f.advance(1);
  expect(f.released()).toBe(2);
  expect(f.timers.size).toBe(0);
});

describe('CHD-533 tester: factual request ownership boundaries', () => {
  test('an actual turn adopted by a repeated filter ends only its owner without moving expiry', () => {
    const f = fixture();
    const next = new AbortController();

    f.requests.retain(f.request());

    const originalExpiry = [...f.timers.keys()][0]!;
    const deadline = [...f.timers.values()][0]!;

    f.advance(RESOURCE_REQUEST_MS - 1);
    f.requests.retain({
      ...f.request(),
      signal: next.signal,
      turnId: 'actual-turn',
    });
    expect(f.calls).toHaveLength(1);
    expect([...f.timers.values()]).toEqual([deadline]);
    f.requests.ended(f.request().caller, 'unrelated-turn');
    expect(f.released()).toBe(0);
    f.requests.ended(f.request().caller, 'actual-turn');
    expect(f.released()).toBe(1);
    expect(getEventListeners(next.signal, 'abort')).toHaveLength(0);
    f.requests.retain({ ...f.request(), turnId: 'next-turn' });
    originalExpiry();
    f.requests.ended(f.request().caller, 'actual-turn');
    expect(f.calls[1]?.signal.aborted).toBe(false);
    expect(f.released()).toBe(1);
    f.requests.close();
    expect(f.released()).toBe(2);
    expect(f.timers.size).toBe(0);
  });

  test('synchronous loss of validity drains a returned retain without caller abort', () => {
    let valid = true;
    let releases = 0;
    let cancelledTimers = 0;
    let resourceSignal: AbortSignal | undefined;
    const caller = new AbortController();
    const requests = new ResourceRequests(
      (_agents, signal) => {
        resourceSignal = signal;
        valid = false;

        return () => {
          releases++;
        };
      },
      {
        now: () => 10,
        after: () => () => {
          cancelledTimers++;
        },
      },
    );

    requests.retain({
      caller: {},
      generation: {},
      agents: ['codex'],
      signal: caller.signal,
      valid: () => valid,
      admittedAt: 10,
    });
    expect(caller.signal.aborted).toBe(false);
    expect(resourceSignal?.aborted).toBe(true);
    expect(getEventListeners(caller.signal, 'abort')).toHaveLength(0);
    expect(releases).toBe(1);
    expect(cancelledTimers).toBe(1);
    requests.close();
    requests.close();
    expect(releases).toBe(1);
    expect(cancelledTimers).toBe(1);
  });
});
