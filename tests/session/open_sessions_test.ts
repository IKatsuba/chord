import { execFile } from 'node:child_process';
import { expect, test } from 'bun:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import type { Wait } from '../../src/notify.ts';
import {
  Conversation,
  type ConversationEvent,
} from '../../src/session/conversation.ts';
import { OpenSessions } from '../../src/session/open_sessions.ts';
import { openSession, type Session } from '../../src/session/session.ts';
import { tabOf } from '../../src/session/tabs.ts';
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

test('two sessions run on the fake agent at once, a wait in one leaves the other alone, and closing both leaves no agent', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'chord-tabs-'));
  const sessions: Session[] = [];
  const heard: { key: number; event: ConversationEvent; wait?: Wait }[] = [];
  const open = new OpenSessions<Conversation>({
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
  const conversation = (key: number) => tabOf(open.tabs, key)!.conversation;
  const wait = (key: number) => tabOf(open.tabs, key)!.wait;

  try {
    const first = open.open('fake')!;
    const second = open.open('fake')!;

    await until(() =>
      [first, second].every((key) =>
        of(key).some((event) => event.type === 'connected'),
      ),
    );
    expect(sessions.length).toStrictEqual(2);
    expect(open.tabs.front).toStrictEqual(second);

    // The first, behind, asks for permission and its turn waits on it.
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

    // The second, in front, takes a whole turn meanwhile, and nothing of the
    // first's wait reaches it.
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
    expect(open.tabs.front).toStrictEqual(first);
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

    expect(open.tabs.tabs).toStrictEqual([]);
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

test('a tab closed on its own still has its agent waited for by closeAll', async () => {
  const closes: (() => void)[] = [];
  const open = new OpenSessions({
    conversation: () => ({
      start: () => {},
      close: () => new Promise<void>((resolve) => closes.push(resolve)),
    }),
    heard: () => {},
  });

  open.open('a');
  open.open('b');

  void open.close(1);

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
  const open = new OpenSessions({
    conversation: () => ({
      start: () => {},
      close: () =>
        new Promise<void>((resolve, reject) =>
          closes.push({ resolve, reject }),
        ),
    }),
    heard: () => {},
  });

  return { open, closes };
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
  const { open, closes } = deferredCloses();

  open.open('a');

  const alone = open.close(1).catch((error: Error) => error.message);
  const all = failures(open.closeAll());

  closes[0]!.reject(new Error('agent exit not observed'));

  expect(await alone).toStrictEqual('agent exit not observed');
  expect(await all).toStrictEqual(['agent exit not observed']);
});

test('an earlier close that failed before closeAll is still in its failure, once', async () => {
  const { open, closes } = deferredCloses();

  open.open('a');

  const alone = open.close(1).catch(() => {});

  closes[0]!.reject(new Error('agent exit not observed'));
  await alone;

  expect(await failures(open.closeAll())).toStrictEqual([
    'agent exit not observed',
  ]);
  expect(await failures(open.closeAll())).toStrictEqual([]);
});

test("closeAll reports an earlier failure beside an open tab's, after waiting for every agent", async () => {
  const { open, closes } = deferredCloses();

  open.open('a');
  open.open('b');
  open.open('c');

  void open.close(1).catch(() => {});

  let settled = false;
  const all = failures(open.closeAll()).finally(() => (settled = true));

  expect(closes.length).toStrictEqual(3);
  closes[0]!.reject(new Error('a did not exit'));
  closes[2]!.reject(new Error('c did not exit'));
  await new Promise((resolve) => setTimeout(resolve, 0));
  expect(settled).toStrictEqual(false);
  closes[1]!.resolve();

  expect((await all).sort()).toStrictEqual([
    'a did not exit',
    'c did not exit',
  ]);
});

test('past nine, open starts nothing', () => {
  let made = 0;
  const open = new OpenSessions({
    conversation: () => {
      made++;

      return { start: () => {}, close: () => Promise.resolve() };
    },
    heard: () => {},
  });

  for (let n = 0; n < 9; n++) {
    open.open('fake');
  }

  expect(open.open('fake')).toStrictEqual(undefined);
  expect(made).toStrictEqual(9);
  expect(open.goTo(3)).toStrictEqual(true);
  expect(open.goTo(10)).toStrictEqual(false);
  expect(open.tabs.front).toStrictEqual(3);
});

test('a child opens in its tab, its events heard under its own key; closing the tab closes it, and closeAll waits for it', async () => {
  const started: string[] = [];
  const closes: (() => void)[] = [];
  const heard: number[] = [];
  const emits = new Map<string, (event: ConversationEvent) => void>();
  const driven = (name: string) => ({
    start: () => started.push(name),
    close: () => new Promise<void>((resolve) => closes.push(resolve)),
  });
  const open = new OpenSessions({
    conversation: (agent) => driven(agent),
    heard: (key) => heard.push(key),
  });
  const tab = open.open('claude')!;
  const child = open.openChild(
    tab,
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
    open.tabs.tabs[0]!.children[0]!.conversation,
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

test("a busy session closed once its turn reported a cost still reports that turn's end as it closes, and the window keeps it (CHD-373)", async () => {
  const dir = await mkdtemp(join(tmpdir(), 'chord-tabs-'));
  const heard: { key: number; event: ConversationEvent }[] = [];
  const closing: { key: number; event: ConversationEvent }[] = [];
  const open = new OpenSessions<Conversation>({
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
    const key = open.open('fake')!;

    await until(() => heard.some(({ event }) => event.type === 'connected'));
    tabOf(open.tabs, key)!.conversation.send('costwait');
    await until(() =>
      heard.some(
        ({ event }) =>
          event.type === 'update' &&
          event.update.sessionUpdate === 'usage_update',
      ),
    );

    // As the window closes a busy tab: cancelled, held, then closed.
    const seen = heard.length;

    tabOf(open.tabs, key)!.conversation.interrupt();

    const closed = open.close(key);
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
    const before = heard
      .slice(0, held)
      .map(({ key: at, event }): WindowedAction => ({
        type: 'in_session',
        key: at,
        action: event,
      }));
    const after: WindowedAction[] = [
      {
        type: 'spend_closing',
        key,
        place: { tab: key, name: 'main', kind: 'main', agent: 'fake' },
      },
      { type: 'session_closed', key, front: key },
      ...closing.map(({ key: at, event }): WindowedAction => ({
        type: 'closing_heard',
        key: at,
        event,
      })),
      { type: 'spend_closed', key },
    ];
    const window = [...before, ...after].reduce(
      reduceWindowed,
      windowed(initialAppState, key),
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
