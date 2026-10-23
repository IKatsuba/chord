import { expect, test } from 'bun:test';
import type {
  MonitorArgs,
  RunningMonitor,
} from '../../src/session/monitors.ts';
import {
  noAgents,
  openChild,
  openMain,
  type WindowAgents,
} from '../../src/session/window_agents.ts';
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

/** Main with children a1 and a2. */
function window() {
  const parent = new Keeper('parent');
  const one = new Keeper('one');
  const two = new Keeper('two');
  let agents: WindowAgents<Keeper> = openMain(noAgents(), 'fake', parent);
  const first = agents.main!.key;

  for (const [id, keeper] of [
    ['a1', one],
    ['a2', two],
  ] as const) {
    agents = openChild(
      agents,
      {
        id,
        name: keeper.name,
        runtime: 'fake',
        openedAt: 0,
      },
      keeper,
    )!.agents;
  }

  return { agents, first, parent, one, two };
}

test('main and its children share the eight', () => {
  const { agents, first, parent, one, two } = window();
  const start = (caller: { key: number; agent?: string }) =>
    startMonitorIn(agents, caller, ARGS, '/work');

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

  // One stopped makes room again, for any of the window's agents.
  stopMonitorIn(agents, { key: first, agent: 'a1' }, 'm1');
  expect('error' in start({ key: first, agent: 'a2' })).toStrictEqual(false);
  expect(parent.cwds).toStrictEqual(['/work', '/work', '/work']);
});

test('a caller lists and stops only its own monitors; a task has none', () => {
  const { agents, first, parent, one } = window();

  startMonitorIn(
    agents,
    { key: first },
    { ...ARGS, description: 'mine' },
    '/w',
  );
  startMonitorIn(
    agents,
    { key: first, agent: 'a1' },
    { ...ARGS, description: 'theirs' },
    '/w',
  );

  const listed = (caller: { key: number; agent?: string; task?: string }) =>
    monitorsIn(agents, caller).map(({ description }) => description);

  expect(listed({ key: first })).toStrictEqual(['mine']);
  expect(listed({ key: first, agent: 'a1' })).toStrictEqual(['theirs']);
  expect(listed({ key: first, agent: 'a2' })).toStrictEqual([]);
  expect(listed({ key: first, task: 't1' })).toStrictEqual([]);

  // Both are m1, each in its own conversation: a2 reaches neither.
  expect(
    stopMonitorIn(agents, { key: first, agent: 'a2' }, 'm1'),
  ).toStrictEqual({
    error: 'No running monitor m1 of yours',
  });
  expect(
    stopMonitorIn(agents, { key: first, agent: 'a1' }, 'm1'),
  ).toStrictEqual({
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
    startMonitorIn(agents, { key: first, task: 't1' }, ARGS, '/w'),
  ).toStrictEqual(closed);
  expect(stopMonitorIn(agents, { key: first, task: 't1' }, 'm1')).toStrictEqual(
    closed,
  );
  expect(
    startMonitorIn(agents, { key: first, agent: 'a9' }, ARGS, '/w'),
  ).toStrictEqual(closed);
  expect(startMonitorIn(agents, { key: 99 }, ARGS, '/w')).toStrictEqual(closed);
});
