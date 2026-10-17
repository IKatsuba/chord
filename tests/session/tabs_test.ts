import { describe, expect, test } from 'bun:test';
import type { ConversationEvent } from '../../src/session/conversation.ts';
import {
  agentOf,
  askingChild,
  attend,
  attentionOrder,
  childEnded,
  childName,
  closeChild,
  closeTab,
  failedSince,
  failureOf,
  frontTab,
  goTo,
  hear,
  isLead,
  listStart,
  MAX_CHILDREN,
  MAX_TABS,
  mergedWait,
  movePick,
  namedChild,
  nextTab,
  noTabs,
  notifiedName,
  openChild,
  openTab,
  pick,
  position,
  previousTab,
  repliedSince,
  runName,
  show,
  shownKey,
  tabName,
  tabOf,
  type Tabs,
  waitingChild,
} from '../../src/session/tabs.ts';

/** Tabs for `agents`, opened in order, the last in front. */
function opened(...agents: string[]): Tabs<string> {
  return agents.reduce(
    (tabs, agent) => openTab(tabs, agent, `conversation of ${agent}`)!.tabs,
    noTabs<string>(),
  );
}

/** The tabs as `1 fake*`, the front marked: what a test can read at once. */
function strip(tabs: Tabs<string>): string[] {
  return tabs.tabs.map(
    (tab, index) =>
      `${index + 1} ${tab.agent}${tab.key === tabs.front ? '*' : ''}`,
  );
}

/** Plays events into tab `key`, each a second after the last from `at`. */
function heard(
  tabs: Tabs<string>,
  key: number,
  events: readonly ConversationEvent[],
  at = 0,
): Tabs<string> {
  return events.reduce(
    (tabs, event, index) => hear(tabs, key, event, at + index * 1000).tabs,
    tabs,
  );
}

const up: ConversationEvent = { type: 'connected', sessionId: 's' };

function prompt(turnId: string): ConversationEvent {
  return { type: 'prompt', turnId, text: 'hi', at: 0 };
}

function asked(turnId: string, id: string): ConversationEvent {
  return {
    type: 'permission_requested',
    turnId,
    permission: { id, title: 'Write notes.txt', options: [] },
  };
}

function settled(turnId: string, id: string): ConversationEvent {
  return {
    type: 'permission_settled',
    turnId,
    id,
    answer: { type: 'chosen', optionId: 'allow' },
  };
}

function ended(turnId: string): ConversationEvent {
  return {
    type: 'result',
    turnId,
    result: { status: 'completed', stopReason: 'end_turn' },
  };
}

function failed(turnId: string): ConversationEvent {
  return {
    type: 'result',
    turnId,
    result: { status: 'failed', error: { message: 'boom' } },
  };
}

test('a new tab goes to the end of the strip and comes to the front', () => {
  const tabs = opened('fake', 'claude', 'codex');

  expect(strip(tabs)).toStrictEqual(['1 fake', '2 claude', '3 codex*']);
  expect(frontTab(tabs)?.conversation).toStrictEqual('conversation of codex');
});

test('a tenth tab is refused and the nine stay as they were', () => {
  const nine = opened(...Array.from({ length: MAX_TABS }, () => 'fake'));

  expect(nine.tabs.length).toStrictEqual(9);
  expect(openTab(nine, 'fake', 'tenth')).toStrictEqual(undefined);
  expect(openTab(closeTab(nine, 3), 'fake', 'ninth')?.key).toStrictEqual(10);
});

test('closing the front tab brings the one to its left forward', () => {
  const tabs = goTo(opened('a', 'b', 'c'), 2);

  expect(strip(closeTab(tabs, 2))).toStrictEqual(['1 a*', '2 c']);
});

test('closing the first tab while in front brings the one to its right forward', () => {
  const tabs = goTo(opened('a', 'b', 'c'), 1);

  expect(strip(closeTab(tabs, 1))).toStrictEqual(['1 b*', '2 c']);
});

test('closing a tab behind leaves the front where it is', () => {
  const tabs = opened('a', 'b', 'c');

  expect(strip(closeTab(tabs, 1))).toStrictEqual(['1 b', '2 c*']);
});

test('closing the last tab leaves none in front', () => {
  const tabs = closeTab(opened('a'), 1);

  expect(tabs.tabs).toStrictEqual([]);
  expect(tabs.front).toStrictEqual(undefined);
  expect(nextTab(tabs)).toStrictEqual(tabs);
});

test('tabs to the right of a closed one move down a number, and their keys stay', () => {
  const tabs = closeTab(opened('a', 'b', 'c', 'd'), 2);

  expect(strip(tabs)).toStrictEqual(['1 a', '2 c', '3 d*']);
  expect(position(tabs, 3)).toStrictEqual(2);
  expect(position(tabs, 2)).toStrictEqual(undefined);
  // The number names the place in the strip, not the session.
  expect(frontTab(goTo(tabs, 2))?.agent).toStrictEqual('c');
  expect(tabName(tabs, 4)).toStrictEqual('d (3)');
});

test('next and previous wrap round the strip', () => {
  const tabs = opened('a', 'b', 'c');

  expect(strip(nextTab(tabs))).toStrictEqual(['1 a*', '2 b', '3 c']);
  expect(strip(previousTab(tabs))).toStrictEqual(['1 a', '2 b*', '3 c']);
  expect(strip(previousTab(nextTab(tabs)))).toStrictEqual(strip(tabs));
});

test('going to a number with no tab does nothing', () => {
  const tabs = opened('a', 'b');

  expect(goTo(tabs, 3)).toStrictEqual(tabs);
  expect(goTo(tabs, 0)).toStrictEqual(tabs);
  expect(strip(goTo(tabs, 1))).toStrictEqual(['1 a*', '2 b']);
});

test('a notification names the tab only once there is more than one', () => {
  expect(tabName(opened('fake'), 1)).toStrictEqual('fake');
  expect(tabName(opened('fake', 'claude'), 2)).toStrictEqual('claude (2)');
  expect(tabName(opened('fake'), 7)).toStrictEqual(undefined);
});

test('a permission behind is a wait on that tab alone, from when it came', () => {
  const tabs = heard(opened('a', 'b'), 1, [
    up,
    prompt('t1'),
    asked('t1', 'p1'),
  ]);
  const seen = hear(tabs, 1, asked('t1', 'p2'), 9000);

  expect(tabOf(tabs, 1)?.wait.asking).toStrictEqual({
    on: { kind: 'permission', title: 'Write notes.txt' },
    since: 2000,
  });
  expect(tabOf(tabs, 1)?.wait.working).toStrictEqual(0);
  expect(tabOf(tabs, 2)?.wait.asking).toStrictEqual(undefined);
  // A second request while one is open is the same wait.
  expect(seen.wait).toStrictEqual(undefined);
  expect(tabOf(seen.tabs, 1)?.wait.asking?.since).toStrictEqual(2000);
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
  expect(hear(tabs, 9, ended('t1'), 0).tabs).toStrictEqual(tabs);
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

  expect(tabOf(tabs, 1)?.wait.asking?.on).toStrictEqual({
    kind: 'input',
    message: 'Sign in',
  });
});

test('an answered permission stops the wait, and the turn goes on', () => {
  const tabs = heard(opened('a', 'b'), 1, [
    up,
    prompt('t1'),
    asked('t1', 'p1'),
    settled('t1', 'p1'),
  ]);

  expect(tabOf(tabs, 1)?.wait.asking).toStrictEqual(undefined);
  expect(tabOf(tabs, 1)?.wait.working).toStrictEqual(0);
});

test('a permission in front is still a wait, and switching away and back keeps it', () => {
  const tabs = heard(opened('a'), 1, [up, prompt('t1'), asked('t1', 'p1')]);
  const away = openTab(tabs, 'b', 'b')!.tabs;

  expect(tabOf(away, 1)?.wait.asking?.since).toStrictEqual(2000);
  expect(tabOf(show(away, 1), 1)?.wait.asking?.since).toStrictEqual(2000);
});

test('a turn ending behind is unseen until the person goes to it', () => {
  const tabs = heard(opened('a', 'b'), 1, [up, prompt('t1'), ended('t1')]);

  expect(tabOf(tabs, 1)?.wait.unseen).toStrictEqual({
    kind: 'replied',
    since: 2000,
    repliedAt: 2000,
  });
  expect(tabOf(tabs, 1)?.wait.working).toStrictEqual(undefined);
  expect(tabOf(goTo(tabs, 1), 1)?.wait.unseen).toStrictEqual(undefined);
  expect(tabOf(nextTab(tabs), 1)?.wait.unseen).toStrictEqual(undefined);
});

test('a turn ending in front is not unseen', () => {
  const tabs = heard(opened('a', 'b'), 2, [up, prompt('t1'), ended('t1')]);

  expect(tabOf(tabs, 2)?.wait.unseen).toStrictEqual(undefined);
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

  expect(tabOf(turn, 1)?.wait.unseen).toStrictEqual({
    kind: 'failed',
    since: 2000,
    failure: 'turn',
    failedAt: 2000,
  });
  expect(tabOf(start, 1)?.wait.unseen).toStrictEqual({
    kind: 'failed',
    since: 0,
    failure: 'start',
    failedAt: 0,
  });
  // A reply after it does not hide the failure, nor move when it began.
  expect(tabOf(later, 1)?.wait.unseen).toStrictEqual({
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
    const wait = tabOf(tabs, 1)!.wait;

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

  expect(tabOf(idleExit, 1)!.wait.unseen).toStrictEqual({
    kind: 'failed',
    since: 6000,
    failure: 'exited',
    failedAt: 6000,
  });
  expect(failureOf(tabOf(afterReply, 1)!.wait)).toStrictEqual('exited');
  // The reply came first, so the tab keeps its place in the order.
  expect(tabOf(afterReply, 1)!.wait.unseen?.since).toStrictEqual(2000);

  const seen = tabOf(goTo(idleExit, 1), 1)!.wait;

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
    const wait = tabOf(tabs, 1)!.wait;

    expect([wait.unseen?.failure, failureOf(wait), wait.exited]).toStrictEqual([
      'exited',
      'exited',
      true,
    ]);
  }

  // A failed turn alone leaves the agent open.
  expect(
    failureOf(
      tabOf(heard(opened('a', 'b'), 1, [up, prompt('t1'), failed('t1')]), 1)!
        .wait,
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

  expect(tabOf(cancelled, 1)?.wait.unseen).toStrictEqual(undefined);
  expect(tabOf(queued, 1)?.wait.unseen).toStrictEqual(undefined);
});

test('a turn ending closes the wait on its permissions', () => {
  const tabs = heard(opened('a', 'b'), 1, [
    up,
    prompt('t1'),
    asked('t1', 'p1'),
    ended('t1'),
  ]);

  expect(tabOf(tabs, 1)?.wait.asking).toStrictEqual(undefined);
  expect(tabOf(tabs, 1)?.wait.unseen?.kind).toStrictEqual('replied');
});

test('/clear starts the tab over with nothing waiting', () => {
  const tabs = heard(opened('a', 'b'), 1, [
    up,
    prompt('t1'),
    asked('t1', 'p1'),
    { type: 'cleared' },
  ]);

  expect(tabOf(tabs, 1)?.wait.asking).toStrictEqual(undefined);
  expect(tabOf(tabs, 1)?.wait.working).toStrictEqual(undefined);
  expect(tabOf(tabs, 1)?.wait.watch.live).toStrictEqual(false);
});

test('the attention order is the oldest waits first, then the oldest unseen', () => {
  let tabs = opened('a', 'b', 'c', 'd', 'e');

  tabs = heard(tabs, 1, [up, prompt('t'), ended('t')], 0); // replied at 2000
  tabs = heard(tabs, 2, [up, prompt('t'), asked('t', 'p')], 10_000); // 12000
  tabs = heard(tabs, 3, [up, prompt('t'), failed('t')], 1000); // failed at 3000
  tabs = heard(tabs, 4, [up, prompt('t'), asked('t', 'p')], 5000); // 7000

  expect(attentionOrder(tabs)).toStrictEqual([4, 2, 1, 3]);
});

test('a tab that waits and has an unseen reply counts once, as waiting', () => {
  let tabs = opened('a', 'b', 'c');

  tabs = heard(tabs, 1, [up, prompt('t'), ended('t')], 0);
  tabs = heard(tabs, 1, [prompt('u'), asked('u', 'p')], 50_000);
  tabs = heard(tabs, 2, [up, prompt('t'), asked('t', 'p')], 0);

  expect(attentionOrder(tabs)).toStrictEqual([2, 1]);
});

test('attention goes to the longest wait, and again to the next, round the queue', () => {
  let tabs = opened('a', 'b', 'c');

  tabs = heard(tabs, 1, [up, prompt('t'), asked('t', 'p')], 5000);
  tabs = heard(tabs, 2, [up, prompt('t'), asked('t', 'p')], 0);

  const first = attend(tabs)!;
  const second = attend(first)!;

  expect(first.front).toStrictEqual(2);
  expect(second.front).toStrictEqual(1);
  expect(attend(second)?.front).toStrictEqual(2);
});

test('attention reaches every one of three lasting waits, in order, and round again', () => {
  let tabs = opened('a', 'b', 'c', 'd');

  tabs = heard(tabs, 1, [up, prompt('t'), asked('t', 'p')], 0);
  tabs = heard(tabs, 2, [up, prompt('t'), asked('t', 'p')], 10_000);
  tabs = heard(tabs, 3, [up, prompt('t'), asked('t', 'p')], 20_000);

  const fronts: number[] = [];

  for (let n = 0; n < 6; n++) {
    tabs = attend(tabs)!;

    fronts.push(tabs.front!);
  }

  expect(fronts).toStrictEqual([1, 2, 3, 1, 2, 3]);
});

test('attention walks the waits, then the unseen, then round to the waits', () => {
  let tabs = opened('a', 'b', 'c', 'd', 'e');

  tabs = heard(tabs, 1, [up, prompt('t'), ended('t')], 0); // replied at 2000
  tabs = heard(tabs, 2, [up, prompt('t'), asked('t', 'p')], 10_000);
  tabs = heard(tabs, 3, [up, prompt('t'), failed('t')], 1000); // failed at 3000
  tabs = heard(tabs, 4, [up, prompt('t'), asked('t', 'p')], 5000);

  const fronts: number[] = [];

  for (let n = 0; n < 6; n++) {
    tabs = attend(tabs)!;

    fronts.push(tabs.front!);
  }

  // Seen once, the reply and the failure leave the order; the waits stay.
  expect(fronts).toStrictEqual([4, 2, 1, 3, 4, 2]);
});

test('attention goes on to the next of tied waits after a tab to the left closes', () => {
  let tabs = opened('a', 'b', 'c', 'd', 'e');

  for (const key of [1, 2, 3, 4]) {
    tabs = heard(tabs, key, [up, prompt('t'), asked('t', 'p')], 100);
  }

  tabs = attend(attend(tabs)!)!;

  expect(tabs.front).toStrictEqual(2);

  tabs = closeTab(tabs, 1);

  expect(attentionOrder(tabs)).toStrictEqual([2, 3, 4]);
  expect(attend(tabs)?.front).toStrictEqual(3);
});

test('attention goes on to the next of tied unseen replies after a tab to the left closes', () => {
  let tabs = opened('a', 'b', 'c', 'd', 'e');

  for (const key of [1, 2, 3, 4]) {
    tabs = heard(tabs, key, [up, prompt('t'), ended('t')], 100);
  }

  tabs = attend(attend(tabs)!)!;

  // Both seen, so tab 2 in front has no place left in the order.
  expect(tabs.front).toStrictEqual(2);
  expect(attentionOrder(tabs)).toStrictEqual([3, 4]);

  tabs = closeTab(tabs, 1);

  expect(attend(tabs)?.front).toStrictEqual(3);
});

test('attention from a waiting tab put in front by hand goes to the next wait', () => {
  let tabs = opened('a', 'b', 'c');

  tabs = heard(tabs, 1, [up, prompt('t'), asked('t', 'p')], 0);
  tabs = heard(tabs, 2, [up, prompt('t'), asked('t', 'p')], 5000);
  tabs = goTo(tabs, 2);

  expect(attend(tabs)?.front).toStrictEqual(1);
  expect(attend(goTo(tabs, 1))?.front).toStrictEqual(2);
});

test('attention clears what it goes to, and says when nothing else waits', () => {
  let tabs = opened('a', 'b');

  tabs = heard(tabs, 1, [up, prompt('t'), ended('t')]);

  const there = attend(tabs)!;

  expect(there.front).toStrictEqual(1);
  expect(tabOf(there, 1)?.wait.unseen).toStrictEqual(undefined);
  expect(attend(there)).toStrictEqual(undefined);
  expect(attend(opened('a', 'b'))).toStrictEqual(undefined);
});

test('the sessions picker starts on the tab that waits, or the one after the front', () => {
  const tabs = opened('fake', 'claude', 'codex');

  // None waits: the one after the front, round to the first.
  expect(listStart(tabs)).toStrictEqual(1);
  expect(listStart(goTo(tabs, 1))).toStrictEqual(2);

  const waiting = heard(goTo(tabs, 1), 2, [up, prompt('t'), asked('t', 'p')]);

  expect(listStart(waiting)).toStrictEqual(2);
  expect(listStart(noTabs())).toStrictEqual(undefined);
});

/** Tab `tabKey` with children `names` opened in it, in order. */
function withChildren(
  tabs: Tabs<string>,
  tabKey: number,
  ...names: string[]
): Tabs<string> {
  return names.reduce(
    (tabs, name) =>
      openChild(
        tabs,
        tabKey,
        {
          id: `id-${name}`,
          name,
          runtime: 'codex',
          openedAt: 0,
        },
        `conversation of ${name}`,
      )!.tabs,
    tabs,
  );
}

/** The front tab's agents as `main*`, the pick marked. */
function list(tabs: Tabs<string>): string[] {
  const tab = frontTab(tabs)!;

  return [{ key: tab.key, name: 'main' }, ...tab.children].map(
    ({ key, name }) => `${name}${key === tab.picked ? '*' : ''}`,
  );
}

test('a child opens in its tab under the next key, takes the next colour, and leaves the pick and the strip alone', () => {
  const tabs = withChildren(opened('claude', 'codex'), 1, 'parser', 'docs');
  const tab = tabOf(tabs, 1)!;

  expect(strip(tabs)).toStrictEqual(['1 claude', '2 codex*']);
  expect(tab.children.map(({ key, colour }) => [key, colour])).toStrictEqual([
    [3, 0],
    [4, 1],
  ]);
  expect(tab.picked).toStrictEqual(1);
  expect(tabs.nextKey).toStrictEqual(5);
  expect(agentOf(tabs, 4)?.child?.name).toStrictEqual('docs');
  expect(agentOf(tabs, 1)?.child).toStrictEqual(undefined);
});

test('a session holds eight children at most', () => {
  const names = Array.from({ length: MAX_CHILDREN }, (_, i) => `c${i}`);
  const tabs = withChildren(opened('claude'), 1, ...names);

  expect(
    openChild(
      tabs,
      1,
      { id: 'x', name: 'x', runtime: 'codex', openedAt: 0 },
      '',
    ),
  ).toStrictEqual(undefined);
});

test('a child is named as asked, or by its runtime, numbered past the first, never main or chord', () => {
  const tab = tabOf(withChildren(opened('claude'), 1, 'codex'), 1)!;

  expect(childName(tab, 'parser', 'codex')).toStrictEqual('parser');
  expect(childName(tab, undefined, 'codex')).toStrictEqual('codex 2');
  expect(childName(tab, ' ', 'gemini')).toStrictEqual('gemini');
  expect(childName(tab, 'main', 'codex')).toStrictEqual('main 2');
});

test("a child's agent that exits tells its parent its last words, and how to open it again", () => {
  const exited: ConversationEvent = {
    type: 'disconnected',
    turnId: 't1',
    at: 0,
  };

  expect(
    childEnded('parser', exited, 'out of memory reading tests/parse.'),
  ).toStrictEqual(
    "parser's agent exited: out of memory reading tests/parse. open_agent " +
      'opens it again.',
  );
  expect(childEnded('parser', exited, '')).toStrictEqual(
    "parser's agent exited. open_agent opens it again.",
  );
});

test("a child's turn that fails tells its parent, unless the agent went, which its exit tells", () => {
  const failed: ConversationEvent = {
    type: 'result',
    turnId: 't1',
    result: {
      status: 'failed',
      error: { message: 'The fake agent failed on purpose.' },
    },
  };

  expect(childEnded('parser', failed, undefined)).toStrictEqual(
    "parser's turn failed: The fake agent failed on purpose. It is still " +
      'open; send_message reaches it.',
  );
  expect(childEnded('parser', failed, 'killed')).toStrictEqual(undefined);
  expect(
    childEnded(
      'parser',
      {
        type: 'result',
        turnId: 't1',
        result: { status: 'completed', stopReason: 'end_turn' },
      },
      undefined,
    ),
  ).toStrictEqual(undefined);
});

test('picking moves down the list and stops at its end; above main the focus goes back', () => {
  let tabs = withChildren(opened('claude'), 1, 'parser', 'docs');

  expect(list(tabs)).toStrictEqual(['main*', 'parser', 'docs']);

  tabs = movePick(tabs, 1)!;

  expect(list(tabs)).toStrictEqual(['main', 'parser*', 'docs']);
  expect(shownKey(tabs)).toStrictEqual(2);

  tabs = movePick(movePick(tabs, 1)!, 1)!;

  expect(list(tabs)).toStrictEqual(['main', 'parser', 'docs*']);
  expect(movePick(pick(tabs, 1), -1)).toStrictEqual(undefined);
});

test('closing a child keeps it among the closed, and a pick on it goes back to main; the colours stay', () => {
  let tabs = withChildren(opened('claude'), 1, 'parser', 'docs');

  tabs = closeChild(pick(tabs, 2), 2);
  tabs = withChildren(tabs, 1, 'review');

  const tab = tabOf(tabs, 1)!;

  expect(tab.picked).toStrictEqual(1);
  expect(tab.closed.map(({ name }) => name)).toStrictEqual(['parser']);
  expect(tab.children.map(({ name, colour }) => [name, colour])).toStrictEqual([
    ['docs', 1],
    ['review', 2],
  ]);
});

test("a child's message, reply and wait are its own; the tab's glyph takes the most urgent of its agents", () => {
  let tabs = withChildren(opened('claude'), 1, 'parser', 'docs');

  tabs = heard(tabs, 2, [
    up,
    {
      type: 'prompt',
      turnId: 't',
      text: 'hi',
      at: 0,
      from: { name: 'main', reachable: true },
    },
  ]);

  expect(agentOf(tabs, 2)?.child?.wait.unseen?.kind).toStrictEqual('message');
  // By the name its row gives.
  expect(agentOf(tabs, 2)?.child?.wait.unseen?.from).toStrictEqual('@main');
  // A message between agents is no wait of the tab's.
  expect(mergedWait(tabOf(tabs, 1)!).unseen).toStrictEqual(undefined);
  expect(attentionOrder(tabs)).toStrictEqual([]);

  tabs = heard(tabs, 3, [up, prompt('d'), asked('d', 'p')], 5000);

  expect(mergedWait(tabOf(tabs, 1)!).asking?.since).toStrictEqual(7000);
  expect(askingChild(tabOf(tabs, 1)!)?.name).toStrictEqual('docs');
  expect(attentionOrder(tabs)).toStrictEqual([3]);

  // Picking a child sees its marks; attending reaches the one that waits.
  expect(agentOf(pick(tabs, 2), 2)?.child?.wait.unseen).toStrictEqual(
    undefined,
  );
  expect(shownKey(attend(tabs)!)).toStrictEqual(3);
});

test('the tab in front on main hears a turn of its own end unseen by no one, and a child behind it as unseen', () => {
  let tabs = withChildren(opened('claude'), 1, 'parser');

  tabs = heard(tabs, 2, [
    up,
    prompt('t'),
    {
      type: 'result',
      turnId: 't',
      result: { status: 'completed', stopReason: 'end_turn' },
    },
  ]);

  expect(agentOf(tabs, 2)?.child?.wait.unseen?.kind).toStrictEqual('replied');
  expect(tabOf(tabs, 1)?.wait.unseen).toStrictEqual(undefined);
});

test('closing a tab takes its children with it', () => {
  const tabs = closeTab(
    withChildren(opened('claude', 'codex'), 1, 'parser'),
    1,
  );

  expect(agentOf(tabs, 3)).toStrictEqual(undefined);
  expect(strip(tabs)).toStrictEqual(['1 codex*']);
});

test("a team's members open after their lead, and only main's own children count against the eight", () => {
  const names = Array.from({ length: MAX_CHILDREN - 1 }, (_, i) => `c${i}`);
  let tabs = withChildren(opened('claude'), 1, 'parser');

  tabs = openChild(
    tabs,
    1,
    {
      id: 'lead',
      name: 'bugfix',
      runtime: 'claude',
      team: 'bugfix',
      openedAt: 0,
    },
    '',
  )!.tabs;
  tabs = withChildren(tabs, 1, ...names.slice(1));

  for (const member of ['tester', 'coder']) {
    tabs = openChild(
      tabs,
      1,
      {
        id: member,
        name: member,
        runtime: 'claude',
        team: 'bugfix',
        lead: 'lead',
        openedAt: 0,
      },
      '',
    )!.tabs;
  }

  const tab = tabOf(tabs, 1)!;

  expect(tab.children.map((child) => child.name)).toStrictEqual([
    'parser',
    'bugfix',
    'tester',
    'coder',
    ...names.slice(1),
  ]);
  // Colours go by the order they opened, not by where they stand.
  expect(tab.children.map((child) => child.colour).slice(0, 4)).toStrictEqual([
    0,
    1,
    MAX_CHILDREN,
    MAX_CHILDREN + 1,
  ]);
  expect(tab.children.filter(isLead).map((child) => child.name)).toStrictEqual([
    'bugfix',
  ]);
  expect(
    openChild(
      tabs,
      1,
      { id: 'x', name: 'x', runtime: 'codex', openedAt: 0 },
      '',
    ),
  ).toStrictEqual(undefined);
});

test("a team's second run is numbered, and a closed run's number is not given again", () => {
  const lead = (tabs: Tabs<string>, id: string, name: string) =>
    openChild(
      tabs,
      1,
      {
        id,
        name,
        runtime: 'claude',
        team: 'bugfix',
        openedAt: 0,
      },
      '',
    )!.tabs;
  let tabs = lead(opened('claude'), 'one', 'bugfix');

  expect(runName(tabOf(tabs, 1)!, 'bugfix')).toStrictEqual('bugfix 2');

  tabs = lead(tabs, 'two', 'bugfix 2');
  tabs = closeChild(tabs, agentOf(tabs, 3)!.child!.key);

  expect(runName(tabOf(tabs, 1)!, 'bugfix')).toStrictEqual('bugfix 3');
  expect(runName(tabOf(tabs, 1)!, 'review')).toStrictEqual('review');
});

test("a lead's agent that exits tells main its members are closed and how to start the team again", () => {
  expect(
    childEnded(
      'bugfix',
      { type: 'disconnected', turnId: 't1', at: 0 },
      'killed',
      true,
    ),
  ).toStrictEqual(
    "bugfix's lead exited: killed. Its members are closed; run_team " +
      'starts the team again.',
  );
});

test('a member is named with its run only while another run has one of its name', () => {
  const lead = (tabs: Tabs<string>, id: string, name: string) =>
    openChild(
      tabs,
      1,
      {
        id,
        name,
        runtime: 'claude',
        team: 'bugfix',
        openedAt: 0,
      },
      '',
    )!.tabs;
  const tester = (tabs: Tabs<string>, id: string, of: string) =>
    openChild(
      tabs,
      1,
      {
        id,
        name: 'tester',
        runtime: 'claude',
        team: 'bugfix',
        lead: of,
        openedAt: 0,
      },
      '',
    )!.tabs;
  let tabs = tester(lead(opened('claude'), 'one', 'bugfix'), 't1', 'one');
  const first = () => tabOf(tabs, 1)!.children.find((c) => c.id === 't1')!;

  expect(namedChild(tabOf(tabs, 1)!, first())).toStrictEqual('tester');

  tabs = tester(lead(tabs, 'two', 'bugfix 2'), 't2', 'two');

  const tab = tabOf(tabs, 1)!;

  expect(namedChild(tab, first())).toStrictEqual('tester · bugfix');
  expect(
    namedChild(
      tab,
      tab.children.find((c) => c.id === 't2')!,
    ),
  ).toStrictEqual('tester · bugfix 2');
  expect(
    namedChild(
      tab,
      tab.children.find((c) => c.id === 'two')!,
    ),
  ).toStrictEqual('bugfix 2');

  // A notification names the run whoever shares the name.
  const key = (id: string) => tab.children.find((c) => c.id === id)!.key;

  expect(notifiedName(tabs, key('t1'))).toStrictEqual('tester (bugfix)');
  expect(notifiedName(tabs, key('t2'))).toStrictEqual('tester (bugfix 2)');
  expect(notifiedName(tabs, key('two'))).toStrictEqual('bugfix 2');
  expect(notifiedName(tabs, 1)).toStrictEqual('claude');
});

test("the child a tab's wait belongs to: the one asking, else the one whose failure is oldest; none for the tab's own", () => {
  let tabs = withChildren(opened('claude'), 1, 'parser', 'docs');

  tabs = heard(tabs, 2, [up, prompt('p'), failed('p')]);

  expect(waitingChild(tabOf(tabs, 1)!)?.name).toStrictEqual('parser');

  tabs = heard(tabs, 3, [up, prompt('d'), asked('d', 'q')], 5000);

  expect(waitingChild(tabOf(tabs, 1)!)?.name).toStrictEqual('docs');
  expect(
    waitingChild(
      tabOf(heard(opened('claude'), 1, [up, prompt('t'), failed('t')]), 1)!,
    ),
  ).toStrictEqual(undefined);
});

describe('CHD-264 tester: child failure lifecycle', () => {
  test('showing the parent does not acknowledge a child; picking it clears only its failure and a later failure gets a fresh time', () => {
    const base = withChildren(opened('a', 'b'), 1, 'parser', 'docs');
    const both = heard(
      heard(base, 3, [up, prompt('p'), failed('p')]),
      4,
      [up, prompt('d'), failed('d')],
      5000,
    );
    const parent = show(both, 1);

    expect(attentionOrder(parent)).toStrictEqual([3, 4]);

    const seen = pick(parent, 3);

    expect(agentOf(seen, 3)?.child?.wait.unseen).toBeUndefined();
    expect(attentionOrder(seen)).toStrictEqual([4]);
    expect(
      agentOf(show(show(seen, 2), 1), 3)?.child?.wait.unseen,
    ).toBeUndefined();

    const later = heard(
      pick(seen, 1),
      3,
      [prompt('next'), failed('next')],
      20_000,
    );

    expect(failedSince(agentOf(later, 3)!.child!.wait)).toBe(21_000);
    expect(attentionOrder(later)).toStrictEqual([4, 3]);
  });

  test('acknowledging an exited child clears attention while preserving its exited state across tab switches', () => {
    const base = withChildren(opened('a', 'b'), 1, 'parser');
    const gone = heard(base, 3, [
      up,
      prompt('p'),
      failed('p'),
      { type: 'disconnected', turnId: 'p' },
    ]);
    const seen = pick(gone, 3);
    const returned = show(show(seen, 2), 1);
    const wait = agentOf(returned, 3)!.child!.wait;

    expect(wait.exited).toBe(true);
    expect(wait.unseen).toBeUndefined();
    expect(attentionOrder(returned)).toStrictEqual([]);
    expect(agentOf(returned, 3)?.child?.conversation).toBe(
      'conversation of parser',
    );
  });
});

test('a reply to a message counts its age from the reply, while the message keeps its place in the order (CHD-364)', () => {
  const message: ConversationEvent = {
    type: 'prompt',
    turnId: 'm',
    text: 'hi',
    at: 0,
    from: { name: 'main', reachable: true },
  };
  // The message at 1 s starts a turn that answers 23 s later.
  const asked = heard(opened('a', 'b'), 1, [up, message]);
  const replied = heard(asked, 1, [ended('m')], 24_000);
  const wait = tabOf(replied, 1)!.wait;

  expect(tabOf(asked, 1)!.wait.unseen?.kind).toStrictEqual('message');
  expect(wait.unseen).toStrictEqual({
    kind: 'replied',
    since: 1000,
    repliedAt: 24_000,
  });
  expect(repliedSince(wait)).toStrictEqual(24_000);

  // A second reply before a look is the newest, and names the age; the
  // news still began with the message.
  const again = heard(replied, 1, [prompt('t2'), ended('t2')], 40_000);

  expect(repliedSince(tabOf(again, 1)!.wait)).toStrictEqual(41_000);
  expect(tabOf(again, 1)!.wait.unseen?.since).toStrictEqual(1000);
});
