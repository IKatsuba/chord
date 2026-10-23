import { execFile } from 'node:child_process';
import { describe, expect, test } from 'bun:test';
import { until as boundedUntil } from './conversation_fake.ts';
import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import type { Wait } from '../../src/notify.ts';
import {
  Conversation,
  type ConversationEvent,
} from '../../src/session/conversation.ts';
import { OpenAgents } from '../../src/session/open_agents.ts';
import { openSession, type Session } from '../../src/session/session.ts';
import { agentOf } from '../../src/session/window_agents.ts';
import {
  initialAppState,
  reduceWindowed,
  windowed,
  type WindowedAction,
} from '../../src/ui/app/state.ts';
import { fakeAgentCommand } from '../fixtures/fake.ts';

function isAlive(pid: number): Promise<boolean> {
  return new Promise((resolve) => {
    execFile('ps', ['-p', String(pid)], (error) => resolve(error === null));
  });
}

async function until(check: () => boolean): Promise<void> {
  while (!check()) {
    await new Promise((resolve) => setTimeout(resolve, 10));
  }
}

test('main and a child run on the fake agent at once, a wait in one leaves the other alone, and closing both leaves no agent', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'chord-agents-'));
  const sessions: Session[] = [];
  const heard: { key: number; event: ConversationEvent; wait?: Wait }[] = [];
  const open = new OpenAgents<Conversation>({
    conversation: (agent, emit) =>
      new Conversation(async () => {
        const session = await openSession({
          agent,
          cwd: dir,
          agentCommand: fakeAgentCommand(),
        });

        sessions.push(session);

        return session;
      }, emit),
    heard: (key, event, wait) =>
      heard.push({ key, event, ...(wait ? { wait } : {}) }),
  });
  const of = (key: number) =>
    heard.filter((each) => each.key === key).map(({ event }) => event);
  const conversation = (key: number) => open.conversationOf(key)!;
  const wait = (key: number) => {
    const found = agentOf(open.agents, key);

    return (found?.child ?? found?.main)!.wait;
  };

  try {
    // main is picked; the child, not shown, is the one that asks.
    const second = open.start('fake')!;
    const first = open.openChild(
      { id: 'parser', name: 'parser', runtime: 'fake', openedAt: 0 },
      (emit) =>
        new Conversation(async () => {
          const session = await openSession({
            agent: 'fake',
            cwd: dir,
            agentCommand: fakeAgentCommand(),
          });

          sessions.push(session);

          return session;
        }, emit),
    )!;

    await until(() =>
      [first, second].every((key) =>
        of(key).some((event) => event.type === 'connected'),
      ),
    );
    expect(sessions.length).toStrictEqual(2);
    expect(open.agents.picked).toStrictEqual(second);

    // The child, not shown, asks for permission and its turn waits on it.
    conversation(first).send('permission');
    await until(() => wait(first).asking !== undefined);

    const requested = of(first).find(
      (event) => event.type === 'permission_requested',
    );

    expect(wait(first).asking?.on.kind).toStrictEqual('permission');
    expect(
      heard
        .filter((each) => each.wait !== undefined)
        .map(({ key, wait }) => [key, wait?.kind]),
    ).toStrictEqual([[first, 'permission']]);

    // main, shown, takes a whole turn meanwhile, and nothing of the child's
    // wait reaches it.
    conversation(second).send('text');
    await until(() => of(second).some((event) => event.type === 'result'));
    expect(wait(second).asking).toStrictEqual(undefined);
    expect(wait(second).unseen).toStrictEqual(undefined);
    expect(
      of(second).some((event) => event.type === 'permission_requested'),
    ).toStrictEqual(false);
    expect(wait(first).asking?.on.kind).toStrictEqual('permission');
    expect(wait(first).working !== undefined).toBeTruthy();

    // ctrl+x a goes to it, and the answer lets its turn end.
    expect(open.attend()).toStrictEqual(true);
    expect(open.agents.picked).toStrictEqual(first);
    assert(requested?.type === 'permission_requested');
    conversation(first).choose(
      requested.permission.id,
      requested.permission.options[0]!.optionId,
    );
    await until(() => of(first).some((event) => event.type === 'result'));
    expect(wait(first).asking).toStrictEqual(undefined);
    expect(wait(first).unseen).toStrictEqual(undefined);
    expect(open.attend()).toStrictEqual(false);
  } finally {
    const pids = sessions.flatMap((session) => [...session.agentPids]);

    await open.closeAll();

    expect(open.agents.main).toStrictEqual(undefined);
    expect(open.agents.children).toStrictEqual([]);
    expect(pids.length).toStrictEqual(2);

    for (const session of sessions) {
      expect(session.agentPids.size).toStrictEqual(0);
    }

    for (const pid of pids) {
      expect(!(await isAlive(pid)), `agent ${pid} still running`).toBeTruthy();
    }

    await rm(dir, { recursive: true });
  }
});

/** A child named `name`, made by `make`. */
function child<C extends { start(): void; close(): Promise<void> }>(
  open: OpenAgents<C>,
  name: string,
  make: () => C,
): number {
  return open.openChild({ id: name, name, runtime: 'fake', openedAt: 0 }, () =>
    make(),
  )!;
}

test('a child closed on its own still has its agent waited for by closeAll', async () => {
  const closes: (() => void)[] = [];
  const driven = () => ({
    start: () => {},
    close: () => new Promise<void>((resolve) => closes.push(resolve)),
  });
  const open = new OpenAgents({ conversation: driven, heard: () => {} });

  open.start('a');

  void open.closeChild(child(open, 'b', driven));

  let all = false;
  const closing = open.closeAll().then(() => (all = true));

  expect(closes.length).toStrictEqual(2);
  closes[1]!();
  await new Promise((resolve) => setTimeout(resolve, 0));
  expect(all).toStrictEqual(false);
  closes[0]!();
  await closing;
  expect(all).toStrictEqual(true);
});

/** Stand-ins whose closes the test settles one by one, in opening order. */
function deferredCloses() {
  const closes: { resolve: () => void; reject: (error: Error) => void }[] = [];
  const make = () => ({
    start: () => {},
    close: () =>
      new Promise<void>((resolve, reject) => closes.push({ resolve, reject })),
  });
  const open = new OpenAgents({ conversation: make, heard: () => {} });

  return { open, closes, make };
}

async function failures(closing: Promise<void>): Promise<string[]> {
  try {
    await closing;

    return [];
  } catch (error) {
    assert(error instanceof AggregateError);

    return error.errors.map((each: Error) => each.message);
  }
}

test('an earlier close that fails while closeAll waits is in its failure', async () => {
  const { open, closes, make } = deferredCloses();

  open.start('a');

  const alone = open
    .closeChild(child(open, 'b', make))
    .catch((error: Error) => error.message);
  const all = failures(open.closeAll());

  closes[0]!.reject(new Error('agent exit not observed'));
  closes[1]!.resolve();

  expect(await alone).toStrictEqual('agent exit not observed');
  expect(await all).toStrictEqual(['agent exit not observed']);
});

test('an earlier close that failed before closeAll is still in its failure, once', async () => {
  const { open, closes, make } = deferredCloses();

  open.start('a');

  const alone = open.closeChild(child(open, 'b', make)).catch(() => {});

  closes[0]!.reject(new Error('agent exit not observed'));
  await alone;

  const first = failures(open.closeAll());

  closes[1]!.resolve();
  expect(await first).toStrictEqual(['agent exit not observed']);
  expect(await failures(open.closeAll())).toStrictEqual([]);
});

test("closeAll reports an earlier failure beside an open agent's, after waiting for every agent", async () => {
  const { open, closes, make } = deferredCloses();

  open.start('a');

  child(open, 'c', make);
  void open.closeChild(child(open, 'b', make)).catch(() => {});

  let settled = false;
  const all = failures(open.closeAll()).finally(() => (settled = true));

  // b's close came first; a and c closed with closeAll.
  expect(closes.length).toStrictEqual(3);
  closes[0]!.reject(new Error('b did not exit'));
  closes[2]!.reject(new Error('c did not exit'));
  await new Promise((resolve) => setTimeout(resolve, 0));
  expect(settled).toStrictEqual(false);
  closes[1]!.resolve();

  expect((await all).sort()).toStrictEqual([
    'b did not exit',
    'c did not exit',
  ]);
});

test('a child opens beside main, its events heard under its own key, and closeAll closes both and waits for them', async () => {
  const started: string[] = [];
  const closes: (() => void)[] = [];
  const heard: number[] = [];
  const emits = new Map<string, (event: ConversationEvent) => void>();
  const driven = (name: string) => ({
    start: () => started.push(name),
    close: () => new Promise<void>((resolve) => closes.push(resolve)),
  });
  const open = new OpenAgents({
    conversation: (agent) => driven(agent),
    heard: (key) => heard.push(key),
  });

  open.start('claude');

  const child = open.openChild(
    {
      id: '7f3a9c2e',
      name: 'parser',
      runtime: 'codex',
      openedAt: 0,
    },
    (emit) => {
      emits.set('parser', emit);

      return driven('parser');
    },
  )!;

  expect(started).toStrictEqual(['claude', 'parser']);
  emits.get('parser')!({ type: 'connected', sessionId: 's' });
  expect(heard).toStrictEqual([child]);
  expect(open.conversationOf(child)).toStrictEqual(
    open.agents.children[0]!.conversation,
  );

  open.pick(child);
  expect(open.front).toStrictEqual(open.conversationOf(child));

  let all = false;
  const closing = open.closeAll().then(() => (all = true));

  expect(closes.length).toStrictEqual(2);
  closes[0]!();
  await new Promise((resolve) => setTimeout(resolve, 0));
  expect(all).toStrictEqual(false);
  closes[1]!();
  await closing;
  expect(all).toStrictEqual(true);
});

test("a busy child closed once its turn reported a cost still reports that turn's end as it closes, and the window keeps it (CHD-373)", async () => {
  const dir = await mkdtemp(join(tmpdir(), 'chord-agents-'));
  const heard: { key: number; event: ConversationEvent }[] = [];
  const closing: { key: number; event: ConversationEvent }[] = [];
  const open = new OpenAgents<Conversation>({
    conversation: (agent, emit) =>
      new Conversation(
        () =>
          openSession({ agent, cwd: dir, agentCommand: fakeAgentCommand() }),
        emit,
      ),
    heard: (key, event) => heard.push({ key, event }),
    closingHeard: (key, event) => closing.push({ key, event }),
  });

  try {
    const tab = open.start('fake')!;
    const key = open.openChild(
      { id: 'other', name: 'other', runtime: 'fake', openedAt: 0 },
      (emit) =>
        new Conversation(
          () =>
            openSession({
              agent: 'fake',
              cwd: dir,
              agentCommand: fakeAgentCommand(),
            }),
          emit,
        ),
    )!;

    await until(() =>
      heard.some(
        ({ key: at, event }) => at === key && event.type === 'connected',
      ),
    );
    open.conversationOf(key)!.send('costwait');
    await until(() =>
      heard.some(
        ({ event }) =>
          event.type === 'update' &&
          event.update.sessionUpdate === 'usage_update',
      ),
    );

    // As the window closes a busy child: cancelled, held, then closed.
    const seen = heard.length;

    open.conversationOf(key)!.interrupt();

    const closed = open.closeChild(key);
    const held = heard.length;

    await closed;

    // The turn's end, its cost with it, came only once it had closed.
    expect(
      heard.slice(seen).some(({ event }) => event.type === 'usage'),
    ).toBeFalsy();
    expect(
      closing.find(({ event }) => event.type === 'usage')?.event,
    ).toMatchObject({ cost: { amount: 0.01, currency: 'USD' } });

    // The window takes those in as sessions.ts dispatches them.
    const before = [
      { type: 'agent_opened', key },
      ...heard.slice(0, held).map(({ key: at, event }): WindowedAction => ({
        type: 'in_session',
        key: at,
        action: event,
      })),
    ] satisfies WindowedAction[];
    const after: WindowedAction[] = [
      {
        type: 'spend_closing',
        key,
        place: { name: 'other', kind: 'agent', runtime: 'fake' },
      },
      { type: 'session_closed', key, front: tab },
      ...closing.map(({ key: at, event }): WindowedAction => ({
        type: 'closing_heard',
        key: at,
        event,
      })),
      { type: 'spend_closed', key },
    ];
    const window = [...before, ...after].reduce(
      reduceWindowed,
      windowed(initialAppState, tab),
    );

    expect(window.window.keptSpend?.[0]?.part.figure?.cost).toStrictEqual({
      amount: 0.01,
      currency: 'USD',
    });
    expect(window.closing).toStrictEqual({});
  } finally {
    await open.closeAll();
    await rm(dir, { recursive: true });
  }
});

describe('CHD-493 U3 tester: one main conversation across child activity', () => {
  test('repeated starts during connection and after a child closes never construct another main', async () => {
    const dir = await mkdtemp(join(tmpdir(), 'chord-one-main-'));
    const sessions: Session[] = [];
    const heard: { key: number; event: ConversationEvent }[] = [];
    let constructed = 0;
    const make = (emit: (event: ConversationEvent) => void) =>
      new Conversation(async () => {
        const session = await openSession({
          agent: 'fake',
          cwd: dir,
          agentCommand: fakeAgentCommand(),
        });

        sessions.push(session);

        return session;
      }, emit);
    const open = new OpenAgents({
      conversation: (_agent, emit) => {
        constructed++;

        return make(emit);
      },
      heard: (key, event) => heard.push({ key, event }),
    });

    try {
      const first = open.start('fake')!;
      const main = open.conversationOf(first);

      expect(open.start('codex')).toBeUndefined();
      await boundedUntil(() =>
        heard.some(
          ({ key, event }) => key === first && event.type === 'connected',
        ),
      );
      expect(constructed).toBe(1);
      expect(sessions).toHaveLength(1);

      const other = open.openChild(
        { id: 'other', name: 'other', runtime: 'fake', openedAt: 0 },
        (emit) => make(emit),
      )!;

      await boundedUntil(() =>
        heard.some(
          ({ key, event }) => key === other && event.type === 'connected',
        ),
      );
      open.pick(other);
      expect(open.start('codex')).toBeUndefined();
      expect(open.front).toBe(open.conversationOf(other));
      await open.closeChild(other);
      expect(open.front).toBe(main);
      expect(open.start('codex')).toBeUndefined();
      expect(open.agents.main?.key).toBe(first);
      expect(open.conversationOf(first)).toBe(main);
      expect(constructed).toBe(1);
      expect(sessions).toHaveLength(2);
    } finally {
      await open.closeAll();

      for (const session of sessions) {
        expect(session.agentPids.size).toBe(0);
      }

      await rm(dir, { recursive: true, force: true });
    }
  });
});
