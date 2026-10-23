import { describe, expect, test } from 'bun:test';
import type { ConversationEvent } from '../../src/session/conversation.ts';
import {
  failedSince,
  failureOf,
  repliedSince,
} from '../../src/session/waits.ts';
import { attend, hear, pick } from '../../src/session/window_agents.ts';
import {
  asked,
  ended,
  failed,
  goTo,
  heard,
  opened,
  prompt,
  settled,
  up,
  waitOf,
  withChildren,
} from './window_agents_helpers.ts';

test('a permission behind is a wait on that tab alone, from when it came', () => {
  const tabs = heard(opened('a', 'b'), 1, [
    up,
    prompt('t1'),
    asked('t1', 'p1'),
  ]);
  const seen = hear(tabs, 1, asked('t1', 'p2'), 9000);

  expect(waitOf(tabs, 1)!.asking).toStrictEqual({
    on: { kind: 'permission', title: 'Write notes.txt' },
    since: 2000,
  });
  expect(waitOf(tabs, 1)!.working).toStrictEqual(0);
  expect(waitOf(tabs, 2)!.asking).toStrictEqual(undefined);
  // A second request while one is open is the same wait.
  expect(seen.wait).toStrictEqual(undefined);
  expect(waitOf(seen.agents, 1)!.asking?.since).toStrictEqual(2000);
});

test('a wait is said once, as notify classes it', () => {
  const tabs = heard(opened('a', 'b'), 1, [up, prompt('t1')]);

  expect(hear(tabs, 1, asked('t1', 'p1'), 0).wait).toStrictEqual({
    kind: 'permission',
    title: 'Write notes.txt',
  });
  expect(hear(tabs, 1, ended('t1'), 0).wait).toStrictEqual({
    kind: 'turn_ended',
  });
  expect(hear(tabs, 9, ended('t1'), 0).agents).toStrictEqual(tabs);
});

test('a form or link waits as input', () => {
  const tabs = heard(opened('a', 'b'), 1, [
    up,
    prompt('t1'),
    {
      type: 'elicitation_requested',
      turnId: 't1',
      elicitation: {
        id: 'e1',
        mode: 'url',
        message: 'Sign in',
        url: 'https://example.com/login',
      },
    },
  ]);

  expect(waitOf(tabs, 1)!.asking?.on).toStrictEqual({
    kind: 'input',
    message: 'Sign in',
    mode: 'url',
  });
});

test('an answered permission stops the wait, and the turn goes on', () => {
  const tabs = heard(opened('a', 'b'), 1, [
    up,
    prompt('t1'),
    asked('t1', 'p1'),
    settled('t1', 'p1'),
  ]);

  expect(waitOf(tabs, 1)!.asking).toStrictEqual(undefined);
  expect(waitOf(tabs, 1)!.working).toStrictEqual(0);
});

test('a permission in front is still a wait, and switching away and back keeps it', () => {
  const tabs = heard(opened('a'), 1, [up, prompt('t1'), asked('t1', 'p1')]);
  const away = goTo(withChildren(tabs, 'b'), tabs.nextKey);

  expect(waitOf(away, 1)!.asking?.since).toStrictEqual(2000);
  expect(waitOf(pick(away, 1), 1)!.asking?.since).toStrictEqual(2000);
});

test('a turn ending behind is unseen until the person goes to it', () => {
  const tabs = heard(opened('a', 'b'), 1, [up, prompt('t1'), ended('t1')]);

  expect(waitOf(tabs, 1)!.unseen).toStrictEqual({
    kind: 'replied',
    since: 2000,
    repliedAt: 2000,
  });
  expect(waitOf(tabs, 1)!.working).toStrictEqual(undefined);
  expect(waitOf(goTo(tabs, 1), 1)!.unseen).toStrictEqual(undefined);
});

test('a turn ending in front is not unseen', () => {
  const tabs = heard(opened('a', 'b'), 2, [up, prompt('t1'), ended('t1')]);

  expect(waitOf(tabs, 2)!.unseen).toStrictEqual(undefined);
});

test('a failed turn or an agent that never came up is unseen as failed, each with its cause', () => {
  const turn = heard(opened('a', 'b'), 1, [up, prompt('t1'), failed('t1')]);
  const start = heard(opened('a', 'b'), 1, [
    {
      type: 'connect_failed',
      message: 'no such agent',
    },
  ]);
  const later = heard(turn, 1, [prompt('t2'), ended('t2')], 5000);

  expect(waitOf(turn, 1)!.unseen).toStrictEqual({
    kind: 'failed',
    since: 2000,
    failure: 'turn',
    failedAt: 2000,
  });
  expect(waitOf(start, 1)!.unseen).toStrictEqual({
    kind: 'failed',
    since: 0,
    failure: 'start',
    failedAt: 0,
  });
  // A reply after it does not hide the failure, nor move when it began.
  expect(waitOf(later, 1)!.unseen).toStrictEqual({
    kind: 'failed',
    since: 2000,
    failure: 'turn',
    failedAt: 2000,
  });
});

test('a failed turn counts its time from the failure, not from older news not yet seen', () => {
  const message: ConversationEvent = {
    type: 'prompt',
    turnId: 'm',
    text: 'hi',
    at: 0,
    from: { name: 'main', reachable: true },
  };
  // A reply at 2 s, then a turn that fails a minute later.
  const replied = heard(opened('a', 'b'), 1, [up, prompt('t1'), ended('t1')]);
  const afterReply = heard(replied, 1, [prompt('t2'), failed('t2')], 61_000);
  const afterMessage = heard(
    heard(opened('a', 'b'), 1, [up, message]),
    1,
    [prompt('t2'), failed('t2')],
    61_000,
  );

  for (const tabs of [afterReply, afterMessage]) {
    const wait = waitOf(tabs, 1)!;

    expect(failedSince(wait)).toStrictEqual(62_000);
    // The first news still sets its place in the order.
    expect(wait.unseen!.since < 62_000).toStrictEqual(true);
  }
});

test('an exit is unseen news even with no turn failed: idle, or after a reply; seen once it clears, and the agent stays exited', () => {
  const gone: ConversationEvent = { type: 'disconnected', turnId: '' };
  const idleExit = heard(opened('a', 'b'), 1, [up, gone], 5000);
  const afterReply = heard(
    heard(opened('a', 'b'), 1, [up, prompt('t1'), ended('t1')]),
    1,
    [gone],
    9000,
  );

  expect(waitOf(idleExit, 1)!.unseen).toStrictEqual({
    kind: 'failed',
    since: 6000,
    failure: 'exited',
    failedAt: 6000,
  });
  expect(failureOf(waitOf(afterReply, 1)!)).toStrictEqual('exited');
  // The reply came first, so the tab keeps its place in the order.
  expect(waitOf(afterReply, 1)!.unseen?.since).toStrictEqual(2000);

  const seen = waitOf(goTo(idleExit, 1), 1)!;

  expect([seen.unseen, failureOf(seen), seen.exited]).toStrictEqual([
    undefined,
    undefined,
    true,
  ]);
});

test("an exit after a failed turn, or one that cuts a turn short, is the failure's cause: the agent went", () => {
  const exitedAfter = heard(opened('a', 'b'), 1, [
    up,
    prompt('t1'),
    failed('t1'),
    { type: 'disconnected', turnId: 't1' },
  ]);
  const cutShort = heard(opened('a', 'b'), 1, [
    up,
    prompt('t1'),
    { type: 'disconnected', turnId: 't1' },
    failed('t1'),
  ]);

  for (const tabs of [exitedAfter, cutShort]) {
    const wait = waitOf(tabs, 1)!;

    expect([wait.unseen?.failure, failureOf(wait), wait.exited]).toStrictEqual([
      'exited',
      'exited',
      true,
    ]);
  }

  // A failed turn alone leaves the agent open.
  expect(
    failureOf(
      waitOf(heard(opened('a', 'b'), 1, [up, prompt('t1'), failed('t1')]), 1)!,
    ),
  ).toStrictEqual('turn');
});

test('a cancelled turn, or one a queued prompt follows, is not unseen', () => {
  const cancelled = heard(opened('a', 'b'), 1, [
    up,
    prompt('t1'),
    { type: 'cancel', turnId: 't1', at: 0 },
    ended('t1'),
  ]);
  const queued = heard(opened('a', 'b'), 1, [
    up,
    prompt('t1'),
    { type: 'queued', turnId: 't2', text: 'next' },
    ended('t1'),
  ]);

  expect(waitOf(cancelled, 1)!.unseen).toStrictEqual(undefined);
  expect(waitOf(queued, 1)!.unseen).toStrictEqual(undefined);
});

test("a turn ending leaves its permissions waiting, between turns (the owner's Q44)", () => {
  const tabs = heard(opened('a', 'b'), 1, [
    up,
    prompt('t1'),
    asked('t1', 'p1'),
    ended('t1'),
  ]);

  expect(waitOf(tabs, 1)!.asking?.since).toStrictEqual(2000);
  // The turn's end is news too, behind the wait.
  expect(waitOf(tabs, 1)!.unseen?.kind).toStrictEqual('replied');
});

test('/clear starts the tab over with nothing waiting', () => {
  const tabs = heard(opened('a', 'b'), 1, [
    up,
    prompt('t1'),
    asked('t1', 'p1'),
    { type: 'cleared' },
  ]);

  expect(waitOf(tabs, 1)!.asking).toStrictEqual(undefined);
  expect(waitOf(tabs, 1)!.working).toStrictEqual(undefined);
  expect(waitOf(tabs, 1)!.watch.live).toStrictEqual(false);
});

describe("a task's permission across the turn that started it (CHD-266)", () => {
  function taskAsked(turnId: string, id: string): ConversationEvent {
    return {
      type: 'permission_requested',
      turnId,
      permission: { id, subagentId: 'task-1', options: [] },
      at: 0,
    };
  }

  test('keeps the wait and attention after the turn ends, until answered', () => {
    let tabs = heard(opened('a', 'b'), 1, [
      up,
      prompt('t1'),
      taskAsked('t1', 'p1'),
      ended('t1'),
    ]);

    expect(waitOf(tabs, 1)!.asking).toStrictEqual({
      on: { kind: 'permission', title: undefined, subagentId: 'task-1' },
      since: 2000,
    });
    expect(attend(tabs)?.picked).toStrictEqual(1);

    tabs = heard(tabs, 1, [settled('t1', 'p1')], 9000);

    expect(waitOf(tabs, 1)!.asking).toStrictEqual(undefined);
  });

  test('a later request after the answer waits again', () => {
    const tabs = heard(opened('a', 'b'), 1, [
      up,
      prompt('t1'),
      taskAsked('t1', 'p1'),
      ended('t1'),
      settled('t1', 'p1'),
      taskAsked('t1', 'p2'),
    ]);

    expect(waitOf(tabs, 1)!.asking?.since).toStrictEqual(5000);
    expect(attend(tabs)?.picked).toStrictEqual(1);
  });

  test('a withdrawn one, as when its task is cancelled, leaves nothing waiting', () => {
    const tabs = heard(opened('a', 'b'), 1, [
      up,
      prompt('t1'),
      taskAsked('t1', 'p1'),
      ended('t1'),
      {
        type: 'permission_settled',
        turnId: 't1',
        id: 'p1',
        answer: { type: 'withdrawn' },
      },
    ]);

    expect(waitOf(tabs, 1)!.asking).toStrictEqual(undefined);
  });
});

describe('CHD-266 tester: settled task attention', () => {
  test('a task form retains attention across result and exposes the original reply after withdrawal', () => {
    const form: ConversationEvent = {
      type: 'elicitation_requested',
      turnId: 't1',
      elicitation: {
        id: 'form',
        subagentId: 'task',
        mode: 'form',
        message: 'Which suite?',
        schema: {},
      },
    };
    const waiting = heard(opened('a', 'b'), 1, [
      up,
      prompt('t1'),
      form,
      ended('t1'),
    ]);

    expect(waitOf(waiting, 1)!.asking).toStrictEqual({
      on: { kind: 'input', message: 'Which suite?', subagentId: 'task' },
      since: 2000,
    });
    expect(attend(waiting)?.picked).toBe(1);

    const done = heard(
      waiting,
      1,
      [
        {
          type: 'elicitation_settled',
          turnId: 't1',
          id: 'form',
          answer: { type: 'withdrawn' },
        },
      ],
      9000,
    );

    expect(waitOf(done, 1)!.asking).toBeUndefined();
    expect(repliedSince(waitOf(done, 1)!)).toBe(3000);
    expect(waitOf(done, 1)!.unseen).toMatchObject({
      kind: 'replied',
      since: 3000,
    });
  });

  test('clear removes attention and a later between request starts a fresh asking age', () => {
    const request: ConversationEvent = {
      type: 'permission_requested',
      turnId: 't1',
      between: true,
      permission: { id: 'p', options: [] },
    };
    const waiting = heard(opened('a', 'b'), 1, [up, request, ended('t1')]);
    const cleared = heard(waiting, 1, [{ type: 'cleared' }], 5000);

    expect(waitOf(cleared, 1)!.asking).toBeUndefined();
    expect(waitOf(cleared, 1)!.unseen).toBeUndefined();

    const later = heard(
      cleared,
      1,
      [up, { ...request, permission: { id: 'new', options: [] } }],
      7000,
    );

    expect(waitOf(later, 1)!.asking?.since).toBe(8000);
    expect(attend(later)?.picked).toBe(1);
  });
});

describe('a wait names the oldest request still open (CHD-431)', () => {
  function taskAsked(id: string, subagentId: string): ConversationEvent {
    return {
      type: 'permission_requested',
      turnId: 't1',
      permission: { id, subagentId, options: [] },
      at: 0,
    };
  }

  function taskForm(id: string, subagentId: string): ConversationEvent {
    return {
      type: 'elicitation_requested',
      turnId: 't1',
      elicitation: {
        id,
        mode: 'url',
        message: 'Sign in',
        url: 'https://example.com',
        subagentId,
      },
    };
  }

  /** The tab's wait after `events`, and whether the last one rang. */
  function after(events: readonly ConversationEvent[]) {
    const tabs = heard(opened('a', 'b'), 1, [
      up,
      prompt('t1'),
      ...events.slice(0, -1),
    ]);
    const last = hear(tabs, 1, events.at(-1)!, 9000);

    return { asking: waitOf(last.agents, 1)!.asking, rang: last.wait };
  }

  test("once one task's request is answered, the other's, from when the wait began, ringing nothing", () => {
    for (const [first, second] of [
      ['a', 'b'],
      ['b', 'a'],
    ] as const) {
      const { asking, rang } = after([
        taskAsked('pa', 'task-a'),
        taskAsked('pb', 'task-b'),
        settled('t1', first === 'a' ? 'pa' : 'pb'),
      ]);

      expect(asking?.on).toMatchObject({ subagentId: `task-${second}` });
      expect(asking?.since).toStrictEqual(2000);
      expect(rang).toStrictEqual(undefined);
    }
  });

  test("once the agent's own is answered, its task's", () => {
    const { asking } = after([
      asked('t1', 'own'),
      taskAsked('pt', 'task-a'),
      settled('t1', 'own'),
    ]);

    expect(asking?.on).toStrictEqual({
      kind: 'permission',
      title: undefined,
      subagentId: 'task-a',
    });
  });

  test("a task's permission comes before another's form opened earlier, as the box shows it", () => {
    const { asking, rang } = after([
      taskForm('fa', 'task-a'),
      taskAsked('pb', 'task-b'),
    ]);

    expect(asking?.on).toStrictEqual({
      kind: 'permission',
      title: undefined,
      subagentId: 'task-b',
    });
    // From when the form came, and the permission rings nothing.
    expect(asking?.since).toStrictEqual(2000);
    expect(rang).toStrictEqual(undefined);

    // Once the permission is answered, the form is on screen again.
    const answered = after([
      taskForm('fa', 'task-a'),
      taskAsked('pb', 'task-b'),
      settled('t1', 'pb'),
    ]);

    expect(answered.asking?.on).toMatchObject({
      kind: 'input',
      subagentId: 'task-a',
    });
  });

  test("once a task's permission is answered, its form after it, as input", () => {
    const { asking } = after([
      taskAsked('pt', 'task-a'),
      taskForm('ft', 'task-a'),
      settled('t1', 'pt'),
    ]);

    expect(asking?.on).toStrictEqual({
      kind: 'input',
      message: 'Sign in',
      mode: 'url',
      subagentId: 'task-a',
    });
  });
});

describe('CHD-431 tester: requester changes keep one wait', () => {
  const input = (id: string, mode: 'form' | 'url'): ConversationEvent => ({
    type: 'elicitation_requested',
    turnId: 't',
    elicitation:
      mode === 'form'
        ? { id, mode, message: id, schema: {}, subagentId: id }
        : { id, mode, message: id, url: 'https://example.com', subagentId: id },
  });
  const permission = (id: string, lasting = true): ConversationEvent => ({
    type: 'permission_requested',
    turnId: 't',
    permission: { id, options: [], subagentId: id },
    ...(lasting ? { at: 0 } : {}),
  });

  test('two permissions precede older form/link requests, and each withdrawal reveals the next without ringing or changing age', () => {
    let tabs = heard(opened('a', 'b'), 1, [
      up,
      prompt('t'),
      input('form', 'form'),
      input('link', 'url'),
      permission('p1'),
      permission('p2'),
    ]);

    for (const [type, id, next] of [
      ['permission_settled', 'p1', 'p2'],
      ['permission_settled', 'p2', 'form'],
      ['elicitation_settled', 'form', 'link'],
      ['elicitation_settled', 'link', undefined],
    ] as const) {
      const result = hear(
        tabs,
        1,
        { type, turnId: 't', id, answer: { type: 'withdrawn' } },
        9000,
      );

      tabs = result.agents;

      expect(result.wait).toBeUndefined();
      expect(waitOf(tabs, 1)!.asking?.on.subagentId).toBe(next);
      expect(waitOf(tabs, 1)!.asking?.since).toBe(
        next === undefined ? undefined : 2000,
      );
    }
  });

  test('a result keeps an untimestamped permission ahead of a lasting input, including after cancel', () => {
    for (const cancelled of [false, true]) {
      const events: ConversationEvent[] = [
        up,
        prompt('t'),
        input('form', 'form'),
        permission('adapter', false),
      ];

      if (cancelled) {
        events.push({ type: 'cancel', turnId: 't', at: 8000 });
      }

      const tabs = heard(opened('a', 'b'), 1, events);
      const next = hear(
        tabs,
        1,
        cancelled
          ? {
              type: 'result',
              turnId: 't',
              result: { status: 'cancelled', stopReason: 'cancelled' },
            }
          : ended('t'),
        9000,
      ).agents;

      expect(waitOf(next, 1)!.asking).toStrictEqual({
        on: { kind: 'permission', title: undefined, subagentId: 'adapter' },
        since: 2000,
      });
      expect([...waitOf(next, 1)!.watch.asked.keys()]).toStrictEqual([
        'form',
        'adapter',
      ]);
    }
  });

  test('clear erases requester metadata only in its own tab and a fresh request starts a new age', () => {
    const both = heard(
      heard(opened('a', 'b', 'c'), 1, [up, input('first', 'url')]),
      2,
      [up, permission('second')],
      4000,
    );
    const cleared = hear(both, 1, { type: 'cleared' }, 9000).agents;

    expect(waitOf(cleared, 1)!.watch.asked.size).toBe(0);
    expect(waitOf(cleared, 1)!.asking).toBeUndefined();
    expect(waitOf(cleared, 2)!.asking?.on.subagentId).toBe('second');

    const again = heard(cleared, 1, [up, input('fresh', 'form')], 10000);

    expect(waitOf(again, 1)!.asking?.since).toBe(11000);
    expect(waitOf(again, 1)!.asking?.on.subagentId).toBe('fresh');
  });
});

test("an agent's own cycle behind works as a turn does until its end (CHD-426)", () => {
  const cycle = { type: 'cycle_started', turnId: 'c1', at: 5000 } as const;
  const working = heard(opened('a', 'b'), 1, [
    up,
    prompt('t1'),
    ended('t1'),
    cycle,
  ]);

  expect(waitOf(working, 1)!.working).toStrictEqual(5000);
  expect(waitOf(heard(working, 1, [ended('c1')]), 1)?.working).toStrictEqual(
    undefined,
  );
});

test("an agent's wait keeps when it last stopped working: when it came up, then each turn's end, a running turn keeping the last (CHD-471)", () => {
  const tabs = opened('fake');
  const stopped = (events: readonly ConversationEvent[]) =>
    heard(tabs, 1, events, 1000).main!.wait.stopped;

  expect(tabs.main!.wait.stopped).toBe(undefined);
  // Came up at 1000.
  expect(stopped([up])).toBe(1000);
  // Its turn began at 2000 and ended at 3000.
  expect(stopped([up, prompt('t1'), ended('t1')])).toBe(3000);
  // While the next runs, it still last stopped at 3000.
  expect(stopped([up, prompt('t1'), ended('t1'), prompt('t2')])).toBe(3000);
  expect(stopped([up, prompt('t1'), failed('t1')])).toBe(3000);
});

describe('CHD-471 tester: stop time and seen marks', () => {
  test('showing an agent clears only its unseen mark while its next turn keeps working', () => {
    let tabs = heard(
      opened('a', 'b'),
      1,
      [up, prompt('first'), ended('first')],
      1000,
    );
    const stopped = waitOf(tabs, 1)!.stopped;

    expect(waitOf(tabs, 1)!.unseen?.kind).toBe('replied');

    tabs = heard(tabs, 1, [prompt('second')], 9000);

    expect(waitOf(tabs, 1)!.unseen?.kind).toBe('replied');

    const working = waitOf(tabs, 1)!.working;

    expect(working).toBeDefined();

    tabs = pick(tabs, 1);

    expect(waitOf(tabs, 1)!.unseen).toBeUndefined();
    expect(waitOf(tabs, 1)!.working).toBe(working);
    expect(waitOf(tabs, 1)!.stopped).toBe(stopped);
  });

  test('reconnect preserves an existing stop, and a cycle end establishes a new one', () => {
    let tabs = heard(opened('a', 'b'), 1, [up], 1000);

    tabs = heard(tabs, 1, [up], 4000);

    expect(waitOf(tabs, 1)!.stopped).toBe(1000);

    tabs = heard(
      tabs,
      1,
      [{ type: 'cycle_started', turnId: 'cycle', at: 5000 }],
      5000,
    );

    expect(waitOf(tabs, 1)!.stopped).toBe(1000);

    tabs = heard(tabs, 1, [ended('cycle')], 8000);

    expect(waitOf(tabs, 1)!.stopped).toBe(8000);
  });
});
