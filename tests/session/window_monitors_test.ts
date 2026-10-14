import { expect, test } from 'bun:test';
import type {
  MonitorArgs,
  RunningMonitor,
} from '../../src/session/monitors.ts';
import {
  noTabs,
  openChild,
  openTab,
  type Tabs,
} from '../../src/session/tabs.ts';
import {
  monitorsIn,
  type MonitorsKeeper,
  startMonitorIn,
  stopMonitorIn,
} from '../../src/session/window_monitors.ts';

/** A conversation's monitors as the test keeps them: started, and stopped. */
class Keeper implements MonitorsKeeper {
  monitors: RunningMonitor[] = [];
  readonly cwds: string[] = [];

  constructor(readonly name: string) {}

  startMonitor(args: MonitorArgs, cwd: string) {
    const id = `m${this.monitors.length + 1}`;

    this.cwds.push(cwd);

    this.monitors = [
      ...this.monitors,
      {
        id,
        description: args.description,
        command: args.command,
        startedAt: 0,
        timeoutMs: 600_000,
        events: 0,
      },
    ];

    return { id, description: args.description, timeout_ms: 600_000 };
  }

  stopMonitor(id: string) {
    const monitor = this.monitors.find((each) => each.id === id);

    if (monitor === undefined) {
      return { error: `No running monitor ${id} of yours` };
    }

    this.monitors = this.monitors.filter((each) => each !== monitor);

    return { id, description: monitor.description, events: 0, ran_ms: 0 };
  }
}

const ARGS: MonitorArgs = { command: 'tail -f log', description: 'log' };

/** Two tabs; the first with children a1 and a2. */
function window() {
  const parent = new Keeper('parent');
  const one = new Keeper('one');
  const two = new Keeper('two');
  const other = new Keeper('other');
  let tabs: Tabs<Keeper> = noTabs();
  const first = openTab(tabs, 'fake', parent)!;

  tabs = first.tabs;

  for (const [id, keeper] of [
    ['a1', one],
    ['a2', two],
  ] as const) {
    tabs = openChild(
      tabs,
      first.key,
      {
        id,
        name: keeper.name,
        runtime: 'fake',
        openedAt: 0,
      },
      keeper,
    )!.tabs;
  }

  const second = openTab(tabs, 'fake', other)!;

  return {
    tabs: second.tabs,
    first: first.key,
    second: second.key,
    parent,
    one,
    two,
    other,
  };
}

test('a tab and its children share the eight; another tab has its own', () => {
  const { tabs, first, second, parent, one, two, other } = window();
  const start = (caller: { key: number; agent?: string }) =>
    startMonitorIn(tabs, caller, ARGS, '/work');

  for (let i = 0; i < 3; i++) {
    start({ key: first });
    start({ key: first, agent: 'a1' });
  }

  start({ key: first, agent: 'a2' });
  start({ key: first, agent: 'a2' });

  expect(
    [parent, one, two].map((keeper) => keeper.monitors.length),
  ).toStrictEqual([3, 3, 2]);

  const refused = {
    error: 'This session has 8 monitors running; stop_monitor one first',
  };

  expect(start({ key: first })).toStrictEqual(refused);
  expect(start({ key: first, agent: 'a1' })).toStrictEqual(refused);
  expect(start({ key: first, agent: 'a2' })).toStrictEqual(refused);
  expect(two.monitors.length).toStrictEqual(2);

  // Another tab counts only its own.
  expect(start({ key: second })).toStrictEqual({
    id: 'm1',
    description: 'log',
    timeout_ms: 600_000,
  });
  expect(other.monitors.length).toStrictEqual(1);

  // One stopped makes room again, for any of the tab's sessions.
  stopMonitorIn(tabs, { key: first, agent: 'a1' }, 'm1');
  expect('error' in start({ key: first, agent: 'a2' })).toStrictEqual(false);
  expect(parent.cwds).toStrictEqual(['/work', '/work', '/work']);
});

test('a caller lists and stops only its own monitors; a task has none', () => {
  const { tabs, first, parent, one } = window();

  startMonitorIn(tabs, { key: first }, { ...ARGS, description: 'mine' }, '/w');
  startMonitorIn(
    tabs,
    { key: first, agent: 'a1' },
    { ...ARGS, description: 'theirs' },
    '/w',
  );

  const listed = (caller: { key: number; agent?: string; task?: string }) =>
    monitorsIn(tabs, caller).map(({ description }) => description);

  expect(listed({ key: first })).toStrictEqual(['mine']);
  expect(listed({ key: first, agent: 'a1' })).toStrictEqual(['theirs']);
  expect(listed({ key: first, agent: 'a2' })).toStrictEqual([]);
  expect(listed({ key: first, task: 't1' })).toStrictEqual([]);

  // Both are m1, each in its own conversation: a2 reaches neither.
  expect(stopMonitorIn(tabs, { key: first, agent: 'a2' }, 'm1')).toStrictEqual({
    error: 'No running monitor m1 of yours',
  });
  expect(stopMonitorIn(tabs, { key: first, agent: 'a1' }, 'm1')).toStrictEqual({
    id: 'm1',
    description: 'theirs',
    events: 0,
    ran_ms: 0,
  });
  expect(listed({ key: first })).toStrictEqual(['mine']);
  expect(parent.monitors.length).toStrictEqual(1);
  expect(one.monitors.length).toStrictEqual(0);

  const closed = { error: 'This session has closed' };

  expect(
    startMonitorIn(tabs, { key: first, task: 't1' }, ARGS, '/w'),
  ).toStrictEqual(closed);
  expect(stopMonitorIn(tabs, { key: first, task: 't1' }, 'm1')).toStrictEqual(
    closed,
  );
  expect(
    startMonitorIn(tabs, { key: first, agent: 'a9' }, ARGS, '/w'),
  ).toStrictEqual(closed);
  expect(startMonitorIn(tabs, { key: 99 }, ARGS, '/w')).toStrictEqual(closed);
});
