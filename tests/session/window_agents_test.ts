import { describe, expect, test } from 'bun:test';
import type { ConversationEvent } from '../../src/session/conversation.ts';
import {
  failedSince,
  failureOf,
  repliedSince,
} from '../../src/session/waits.ts';
import {
  agentOf,
  attend,
  attentionOrder,
  childEnded,
  childName,
  closeChild,
  isLead,
  MAX_CHILDREN,
  movePick,
  namedChild,
  notifiedName,
  openChild,
  pick,
  runName,
  shownKey,
  type WindowAgents,
} from '../../src/session/window_agents.ts';
import {
  asked,
  ended,
  failed,
  goTo,
  heard,
  list,
  opened,
  prompt,
  up,
  waitOf,
  withChildren,
} from './window_agents_helpers.ts';

test('the attention order is the oldest waits first, then the oldest unseen', () => {
  let tabs = opened('a', 'b', 'c', 'd', 'e');

  tabs = heard(tabs, 1, [up, prompt('t'), ended('t')], 0); // replied at 2000
  tabs = heard(tabs, 2, [up, prompt('t'), asked('t', 'p')], 10_000); // 12000
  tabs = heard(tabs, 3, [up, prompt('t'), failed('t')], 1000); // failed at 3000
  tabs = heard(tabs, 4, [up, prompt('t'), asked('t', 'p')], 5000); // 7000

  expect(attentionOrder(tabs)).toStrictEqual([4, 2, 1, 3]);
});

test('an agent that waits and has an unseen reply counts once, as waiting', () => {
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

  expect(first.picked).toStrictEqual(2);
  expect(second.picked).toStrictEqual(1);
  expect(attend(second)?.picked).toStrictEqual(2);
});

test('attention reaches every one of three lasting waits, in order, and round again', () => {
  let tabs = opened('a', 'b', 'c', 'd');

  tabs = heard(tabs, 1, [up, prompt('t'), asked('t', 'p')], 0);
  tabs = heard(tabs, 2, [up, prompt('t'), asked('t', 'p')], 10_000);
  tabs = heard(tabs, 3, [up, prompt('t'), asked('t', 'p')], 20_000);

  const fronts: number[] = [];

  for (let n = 0; n < 6; n++) {
    tabs = attend(tabs)!;

    fronts.push(tabs.picked!);
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

    fronts.push(tabs.picked!);
  }

  // Seen once, the reply and the failure leave the order; the waits stay.
  expect(fronts).toStrictEqual([4, 2, 1, 3, 4, 2]);
});

test('attention from a waiting agent picked by hand goes to the next wait', () => {
  let tabs = opened('a', 'b', 'c');

  tabs = heard(tabs, 1, [up, prompt('t'), asked('t', 'p')], 0);
  tabs = heard(tabs, 2, [up, prompt('t'), asked('t', 'p')], 5000);
  tabs = goTo(tabs, 2);

  expect(attend(tabs)?.picked).toStrictEqual(1);
  expect(attend(goTo(tabs, 1))?.picked).toStrictEqual(2);
});

test('attention clears what it goes to, and says when nothing else waits', () => {
  let tabs = opened('a', 'b');

  tabs = heard(tabs, 1, [up, prompt('t'), ended('t')]);

  const there = attend(tabs)!;

  expect(there.picked).toStrictEqual(1);
  expect(waitOf(there, 1)!.unseen).toStrictEqual(undefined);
  expect(attend(there)).toStrictEqual(undefined);
  expect(attend(opened('a', 'b'))).toStrictEqual(undefined);
});

test('a child opens under the next key, takes the next colour, and leaves the pick alone', () => {
  const tabs = withChildren(opened('claude'), 'parser', 'docs');

  expect(tabs.children.map(({ key, colour }) => [key, colour])).toStrictEqual([
    [2, 0],
    [3, 1],
  ]);
  expect(tabs.picked).toStrictEqual(1);
  expect(tabs.nextKey).toStrictEqual(4);
  expect(agentOf(tabs, 3)?.child?.name).toStrictEqual('docs');
  expect(agentOf(tabs, 1)?.child).toStrictEqual(undefined);
  expect(agentOf(tabs, 1)?.main?.agent).toStrictEqual('claude');
});

test('a session holds eight children at most', () => {
  const names = Array.from({ length: MAX_CHILDREN }, (_, i) => `c${i}`);
  const tabs = withChildren(opened('claude'), ...names);

  expect(
    openChild(tabs, { id: 'x', name: 'x', runtime: 'codex', openedAt: 0 }, ''),
  ).toStrictEqual(undefined);
});

test('a child is named as asked, or by its runtime, numbered past the first, never main or chord', () => {
  const tab = withChildren(opened('claude'), 'codex');

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
  let tabs = withChildren(opened('claude'), 'parser', 'docs');

  expect(list(tabs)).toStrictEqual(['main*', 'parser', 'docs']);

  tabs = movePick(tabs, 1)!;

  expect(list(tabs)).toStrictEqual(['main', 'parser*', 'docs']);
  expect(shownKey(tabs)).toStrictEqual(2);

  tabs = movePick(movePick(tabs, 1)!, 1)!;

  expect(list(tabs)).toStrictEqual(['main', 'parser', 'docs*']);
  expect(movePick(pick(tabs, 1), -1)).toStrictEqual(undefined);
});

test('closing a child keeps it among the closed, and a pick on it goes back to main; the colours stay', () => {
  let tabs = withChildren(opened('claude'), 'parser', 'docs');

  tabs = closeChild(pick(tabs, 2), 2);
  tabs = withChildren(tabs, 'review');

  const tab = tabs;

  expect(tab.picked).toStrictEqual(1);
  expect(tab.closed.map(({ name }) => name)).toStrictEqual(['parser']);
  expect(tab.children.map(({ name, colour }) => [name, colour])).toStrictEqual([
    ['docs', 1],
    ['review', 2],
  ]);
});

test("a child's message, reply and wait are its own", () => {
  let tabs = withChildren(opened('claude'), 'parser', 'docs');

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
  // A message between agents wants no one.
  expect(attentionOrder(tabs)).toStrictEqual([]);

  tabs = heard(tabs, 3, [up, prompt('d'), asked('d', 'p')], 5000);

  expect(attentionOrder(tabs)).toStrictEqual([3]);

  // Picking a child sees its marks; attending reaches the one that waits.
  expect(agentOf(pick(tabs, 2), 2)?.child?.wait.unseen).toStrictEqual(
    undefined,
  );
  expect(shownKey(attend(tabs)!)).toStrictEqual(3);
});

test('main, shown, hears a turn of its own end unseen by no one, and a child not shown as unseen', () => {
  let tabs = withChildren(opened('claude'), 'parser');

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
  expect(waitOf(tabs, 1)!.unseen).toStrictEqual(undefined);
});

test("a team's members open after their lead, and only main's own children count against the eight", () => {
  const names = Array.from({ length: MAX_CHILDREN - 1 }, (_, i) => `c${i}`);
  let tabs = withChildren(opened('claude'), 'parser');

  tabs = openChild(
    tabs,
    {
      id: 'lead',
      name: 'bugfix',
      runtime: 'claude',
      team: 'bugfix',
      openedAt: 0,
    },
    '',
  )!.agents;
  tabs = withChildren(tabs, ...names.slice(1));

  for (const member of ['tester', 'coder']) {
    tabs = openChild(
      tabs,
      {
        id: member,
        name: member,
        runtime: 'claude',
        team: 'bugfix',
        lead: 'lead',
        openedAt: 0,
      },
      '',
    )!.agents;
  }

  const tab = tabs;

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
    openChild(tabs, { id: 'x', name: 'x', runtime: 'codex', openedAt: 0 }, ''),
  ).toStrictEqual(undefined);
});

test("a team's second run is numbered, and a closed run's number is not given again", () => {
  const lead = (tabs: WindowAgents<string>, id: string, name: string) =>
    openChild(
      tabs,
      {
        id,
        name,
        runtime: 'claude',
        team: 'bugfix',
        openedAt: 0,
      },
      '',
    )!.agents;
  let tabs = lead(opened('claude'), 'one', 'bugfix');

  expect(runName(tabs, 'bugfix')).toStrictEqual('bugfix 2');

  tabs = lead(tabs, 'two', 'bugfix 2');
  tabs = closeChild(tabs, agentOf(tabs, 3)!.child!.key);

  expect(runName(tabs, 'bugfix')).toStrictEqual('bugfix 3');
  expect(runName(tabs, 'review')).toStrictEqual('review');
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
  const lead = (tabs: WindowAgents<string>, id: string, name: string) =>
    openChild(
      tabs,
      {
        id,
        name,
        runtime: 'claude',
        team: 'bugfix',
        openedAt: 0,
      },
      '',
    )!.agents;
  const tester = (tabs: WindowAgents<string>, id: string, of: string) =>
    openChild(
      tabs,
      {
        id,
        name: 'tester',
        runtime: 'claude',
        team: 'bugfix',
        lead: of,
        openedAt: 0,
      },
      '',
    )!.agents;
  let tabs = tester(lead(opened('claude'), 'one', 'bugfix'), 't1', 'one');
  const first = () => tabs.children.find((c) => c.id === 't1')!;

  expect(namedChild(tabs, first())).toStrictEqual('tester');

  tabs = tester(lead(tabs, 'two', 'bugfix 2'), 't2', 'two');

  const tab = tabs;

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

describe('CHD-264 tester: child failure lifecycle', () => {
  test('showing the parent does not acknowledge a child; picking it clears only its failure and a later failure gets a fresh time', () => {
    const base = withChildren(opened('a', 'b'), 'parser', 'docs');
    const both = heard(
      heard(base, 3, [up, prompt('p'), failed('p')]),
      4,
      [up, prompt('d'), failed('d')],
      5000,
    );
    const parent = pick(both, 1);

    expect(attentionOrder(parent)).toStrictEqual([3, 4]);

    const seen = pick(parent, 3);

    expect(agentOf(seen, 3)?.child?.wait.unseen).toBeUndefined();
    expect(attentionOrder(seen)).toStrictEqual([4]);
    expect(
      agentOf(pick(pick(seen, 2), 1), 3)?.child?.wait.unseen,
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
    const base = withChildren(opened('a', 'b'), 'parser');
    const gone = heard(base, 3, [
      up,
      prompt('p'),
      failed('p'),
      { type: 'disconnected', turnId: 'p' },
    ]);
    const seen = pick(gone, 3);
    const returned = pick(pick(seen, 2), 1);
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
  const wait = waitOf(replied, 1)!;

  expect(waitOf(asked, 1)!.unseen?.kind).toStrictEqual('message');
  expect(wait.unseen).toStrictEqual({
    kind: 'replied',
    since: 1000,
    repliedAt: 24_000,
  });
  expect(repliedSince(wait)).toStrictEqual(24_000);

  // A second reply before a look is the newest, and names the age; the
  // news still began with the message.
  const again = heard(replied, 1, [prompt('t2'), ended('t2')], 40_000);

  expect(repliedSince(waitOf(again, 1)!)).toStrictEqual(41_000);
  expect(waitOf(again, 1)!.unseen?.since).toStrictEqual(1000);
});

describe('CHD-364 tester: separate reply and attention clocks', () => {
  const message = (turnId: string): ConversationEvent => ({
    type: 'prompt',
    turnId,
    text: 'hi',
    at: 0,
    from: { name: 'main', reachable: true },
  });

  test('each later reply moves its age but leaves the oldest child first for attention', () => {
    const base = withChildren(opened('fake'), 'parser', 'docs');
    const first = heard(
      heard(base, 2, [up, message('p')], 1000),
      2,
      [ended('p')],
      10_000,
    );
    const other = heard(first, 3, [up, prompt('d'), ended('d')], 20_000);
    const latest = heard(other, 2, [prompt('next'), ended('next')], 50_000);
    const wait = agentOf(latest, 2)!.child!.wait;

    expect(repliedSince(wait)).toBe(51_000);
    expect(wait.unseen?.since).toBe(2000);
    expect(attentionOrder(latest)).toStrictEqual([2, 3]);

    const there = attend(latest)!;

    expect(shownKey(there)).toBe(2);
    expect(repliedSince(agentOf(there, 2)!.child!.wait)).toBeUndefined();
    expect(shownKey(attend(there)!)).toBe(3);
  });

  test('a cancelled turn does not move a previous unseen reply clock', () => {
    const first = heard(opened('a', 'b'), 1, [
      up,
      prompt('first'),
      ended('first'),
    ]);
    const cancelled = heard(
      first,
      1,
      [
        prompt('next'),
        { type: 'cancel', turnId: 'next', at: 50_000 },
        ended('next'),
      ],
      50_000,
    );

    expect(repliedSince(waitOf(cancelled, 1)!)).toBe(2000);
    expect(waitOf(cancelled, 1)!.unseen?.since).toBe(2000);
  });

  test('replies after a failure cannot replace its first failure time, or expose a reply age', () => {
    const first = heard(opened('a', 'b'), 1, [
      up,
      message('first'),
      ended('first'),
    ]);
    const failure = heard(first, 1, [prompt('bad'), failed('bad')], 10_000);
    const after = heard(
      failure,
      1,
      [
        prompt('later'),
        ended('later'),
        prompt('bad-again'),
        failed('bad-again'),
      ],
      20_000,
    );
    const wait = waitOf(after, 1)!;

    expect(failureOf(wait)).toBe('turn');
    expect(failedSince(wait)).toBe(11_000);
    expect(repliedSince(wait)).toBeUndefined();
    expect(wait.unseen?.since).toBe(1000);
  });
});

test("from an agent put in front by hand, attention goes first to the longest wait behind it, as the status line names it, then walks on (the owner's Q46)", () => {
  let tabs = opened('a', 'b', 'c');

  // a has waited longest, b asks later, c has a reply not yet seen.
  tabs = heard(tabs, 1, [up, prompt('t'), asked('t', 'p')], 0);
  tabs = heard(tabs, 2, [up, prompt('t'), asked('t', 'p')], 5000);
  // b in front by hand, so c's end behind it is news.
  tabs = goTo(tabs, 2);
  tabs = heard(tabs, 3, [up, prompt('t'), ended('t')], 9000);

  const first = attend(tabs)!;

  expect(first.picked).toStrictEqual(1);
  // From there it walks as ever: the next wait, then the unseen reply.
  expect(attend(first)?.picked).toStrictEqual(2);
  expect(attend(attend(first)!)?.picked).toStrictEqual(3);
});

describe('CHD-431 Q46 tester: attention after a hand pick', () => {
  function withChild(): { tabs: WindowAgents<string>; child: number } {
    const openedChild = openChild(
      opened('main', 'other', 'quiet'),
      { id: 'worker', name: 'worker', runtime: 'fake', openedAt: 0 },
      'child conversation',
    )!;
    let tabs = heard(openedChild.agents, 1, [up, prompt('a'), asked('a', 'a')]);

    tabs = heard(tabs, 2, [up, prompt('b'), asked('b', 'b')], 5000);
    tabs = heard(tabs, openedChild.key, [up, prompt('c'), ended('c')], 9000);

    return { tabs, child: openedChild.key };
  }

  test('a hand-picked child reaches the oldest wait and then walks across tabs', () => {
    const { tabs, child } = withChild();
    const first = attend(pick(tabs, child))!;
    const second = attend(first)!;

    expect(shownKey(first)).toBe(1);
    expect(shownKey(second)).toBe(2);
    expect(shownKey(attend(second)!)).toBe(1);
  });

  test('picking a waiting child excludes itself and names the oldest other wait', () => {
    const { tabs, child } = withChild();
    const waiting = heard(tabs, child, [prompt('d'), asked('d', 'd')], 15000);
    const first = attend(pick(waiting, child))!;
    const second = attend(first)!;
    const third = attend(second)!;

    expect([shownKey(first), shownKey(second), shownKey(third)]).toEqual([
      1,
      2,
      child,
    ]);
    expect(shownKey(attend(third)!)).toBe(1);
  });

  test('another hand pick resets a previous walk to the oldest remaining wait', () => {
    const { tabs, child } = withChild();
    const walked = attend(attend(pick(tabs, child))!)!;

    expect(shownKey(walked)).toBe(2);
    expect(shownKey(attend(pick(walked, 3))!)).toBe(1);
    expect(shownKey(attend(pick(walked, 1))!)).toBe(2);
  });

  test('without waits, unseen replies and failures are visited once in age order', () => {
    let tabs = heard(opened('a', 'b', 'quiet'), 1, [
      up,
      prompt('a'),
      ended('a'),
    ]);

    tabs = heard(tabs, 2, [up, prompt('b'), failed('b')], 5000);

    const first = attend(pick(tabs, 3))!;
    const second = attend(first)!;

    expect(shownKey(first)).toBe(1);
    expect(shownKey(second)).toBe(2);
    expect(attend(second)).toBeUndefined();
  });
});

describe('CHD-493 U3 tester: closed child keys never become a new child', () => {
  test('late connection, permission and result leave a same-named replacement idle and main picked', () => {
    const initial = opened('fake', 'other');
    const closed = closeChild(initial, 2);
    const replacement = openChild(
      closed,
      { id: 'replacement', name: 'other', runtime: 'fake', openedAt: 1 },
      'replacement conversation',
    )!.agents;
    const late = heard(replacement, 2, [
      up,
      prompt('old-turn'),
      asked('old-turn', 'old-permission'),
      ended('old-turn'),
    ]);

    expect(late.main?.key).toBe(1);
    expect(late.picked).toBe(1);
    expect(late.children.map(({ key, name }) => [key, name])).toStrictEqual([
      [3, 'other'],
    ]);
    expect(agentOf(late, 2)).toBeUndefined();
    expect(attentionOrder(late)).toStrictEqual([]);
    expect(late.children[0]?.wait).toStrictEqual(replacement.children[0]?.wait);
    expect(late.closed.map(({ name }) => name)).toStrictEqual(['other']);
  });
});
