import { describe, expect, test } from 'bun:test';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import type {
  EndedMonitor,
  RunningMonitor,
} from '../../../src/session/monitors.ts';
import {
  emptyTranscript,
  type Entry,
  type Subagent,
  type Transcript,
} from '../../../src/session/transcript/types.ts';
import {
  type BackgroundAgent,
  type BackgroundItem,
  type ItemStatus,
  backgroundItems,
  callPlace,
  itemSubagent,
  leavesList,
  summaryGroups,
  summaryLines,
  type SummaryPiece,
} from '../../../src/ui/background/background.ts';
import { openSession } from '../../../src/session/session.ts';
import { reduceTranscript } from '../../../src/session/transcript/reducer.ts';
import { fakeAgentCommand } from '../../fixtures/fake.ts';
import { play, type PlayOptions } from '../../fixtures/recorder.ts';

function running(id: string, description: string, startedAt: number) {
  return {
    id,
    description,
    command: 'cmd',
    startedAt,
    timeoutMs: 600_000,
    events: 1,
  } satisfies RunningMonitor;
}

function ended(
  monitor: RunningMonitor,
  end: EndedMonitor['end'],
  endedAt: number,
): EndedMonitor {
  return { ...monitor, end, endedAt };
}

function task(
  id: string,
  name: string,
  startedAt: number,
  more: Partial<Subagent> = {},
): Entry {
  return {
    kind: 'subagent',
    turnId: 't1',
    subagent: {
      id,
      title: name,
      state: 'running',
      startedAt,
      entries: [],
      plan: [],
      task: { name, runtime: 'fake', model: 'Fake Small' },
      callId: `call-${id}`,
      ...more,
    },
  };
}

function agent(
  key: number,
  more: Partial<BackgroundAgent> = {},
): BackgroundAgent {
  return {
    key,
    since: 0,
    monitors: [],
    endedMonitors: [],
    transcript: emptyTranscript,
    ...more,
  };
}

function withEntries(
  entries: readonly Entry[],
  more: Partial<Transcript> = {},
) {
  return { ...emptyTranscript, entries, ...more };
}

const brief = (items: readonly BackgroundItem[]) =>
  items.map(
    ({ kind, name, key, status }) => `${kind} ${name} ${key} ${status.group}`,
  );

describe('the items', () => {
  test("every monitor and task of the tab's agents, oldest first, each in its state", () => {
    const items = backgroundItems([
      agent(1, {
        monitors: [running('m2', 'dev server', 300)],
        endedMonitors: [
          ended(running('m1', 'CI run', 100), { kind: 'exit', code: 1 }, 400),
        ],
        transcript: withEntries([
          task('task-1', 'Fix the tokenizer', 200),
          task('task-2', 'Fix the printer', 500, {
            state: 'completed',
            endedAt: 900,
          }),
        ]),
      }),
      agent(2, {
        owner: { name: 'parser', colour: 0 },
        monitors: [running('m1', 'parser tests', 250)],
      }),
    ]);

    // The ended monitor and the ended task have left (CHD-479, CHD-482).
    expect(brief(items)).toStrictEqual([
      'task Fix the tokenizer 1 running',
      'monitor parser tests 2 running',
      'monitor dev server 1 running',
    ]);
    expect(items[0]).toStrictEqual({
      kind: 'task',
      id: 'task-1',
      key: 1,
      name: 'Fix the tokenizer',
      startedAt: 200,
      status: { group: 'running' },
      runtime: 'fake',
      model: 'Fake Small',
      callId: 'call-task-1',
    });
    expect(items[1]?.owner).toStrictEqual({ name: 'parser', colour: 0 });
  });

  test('a monitor leaves the list however it ended: exit 0, another exit, a signal, a timeout, a flood or a stop (CHD-479)', () => {
    const monitor = running('m1', 'x', 0);
    const items = (
      [
        { kind: 'exit', code: 0 },
        { kind: 'exit', code: 2 },
        { kind: 'signal', signal: 'SIGKILL' },
        { kind: 'timed_out', timeoutMs: 1000 },
        { kind: 'flooded', by: 'lines' },
        { kind: 'stopped' },
      ] as const
    ).map(
      (end) =>
        backgroundItems([agent(1, { endedMonitors: [ended(monitor, end, 5)] })])
          .length,
    );

    expect(items).toStrictEqual([0, 0, 0, 0, 0, 0]);
  });

  test('an ended monitor whose detail is open stays until it is left, the others leaving as they would (CHD-481, Q126)', () => {
    const agents = [
      agent(1, {
        endedMonitors: [
          ended(
            running('m1', 'kept', 0),
            { kind: 'timed_out', timeoutMs: 1000 },
            5,
          ),
          ended(running('m2', 'gone', 0), { kind: 'stopped' }, 5),
        ],
      }),
    ];

    expect(brief(backgroundItems(agents, { key: 1, id: 'm1' }))).toStrictEqual([
      'monitor kept 1 stopped',
    ]);
    expect(brief(backgroundItems(agents, { key: 2, id: 'm1' }))).toStrictEqual(
      [],
    );
  });

  test("a task leaves at once however it ends; its open detail keeps it, as a monitor's and an agent's do (CHD-482, Q126, Q136)", () => {
    const items = (
      state: Subagent['state'],
      keep?: { key: number; id: string },
    ) =>
      backgroundItems(
        [
          agent(1, {
            transcript: withEntries([
              task('t', 'x', 10, { state, endedAt: 20 }),
            ]),
          }),
        ],
        keep,
      );
    const ends = ['completed', 'failed', 'disconnected', 'cancelled'] as const;

    expect(ends.map((state) => items(state).length)).toStrictEqual([
      0, 0, 0, 0,
    ]);
    expect(
      ends.map((state) => items(state, { key: 1, id: 't' }).length),
    ).toStrictEqual([1, 1, 1, 1]);
    // An agent too, while its detail is open (CHD-487).
    expect(
      backgroundItems(
        [
          agent(1, {
            transcript: withEntries([
              claude('a', 10, { state: 'completed', endedAt: 20 }),
            ]),
          }),
        ],
        { key: 1, id: 'a' },
      ).map(({ id }) => id),
    ).toStrictEqual(['a']);
  });

  test('a task asking for a permission or an input counts from when it asked, its oldest request first', () => {
    const asking = (transcript: Partial<Transcript>) =>
      backgroundItems([
        agent(1, {
          transcript: withEntries([task('task-1', 'x', 10)], transcript),
        }),
      ])[0]?.status;

    expect(
      asking({
        turn: {
          status: 'awaiting_permission',
          turnId: 't1',
          since: 5,
          permissions: [
            { id: 'p0', options: [] },
            { id: 'p1', subagentId: 'task-1', at: 40, options: [] },
          ],
        },
      }),
    ).toStrictEqual({ group: 'asking', on: 'permission', since: 40 });
    expect(
      asking({
        asking: [
          {
            id: 'e1',
            mode: 'url',
            url: 'https://example.com',
            message: 'Sign in',
            subagentId: 'task-1',
            at: 30,
          },
        ],
      }),
    ).toStrictEqual({ group: 'asking', on: 'input', since: 30 });
    // Another's request leaves it working.
    expect(
      asking({
        asking: [
          {
            id: 'e1',
            mode: 'url',
            url: 'u',
            message: 'm',
            subagentId: 'other',
            at: 1,
          },
        ],
      }),
    ).toStrictEqual({ group: 'running' });
  });

  test("a task in a subagent's work is one, and one from before its session came up is its past, not an item", () => {
    // A Claude subagent of its own, which is no task, with one inside.
    const nested: Entry = {
      kind: 'subagent',
      turnId: 't1',
      subagent: {
        id: 'outer',
        state: 'running',
        startedAt: 10,
        entries: [task('inner', 'Inner task', 20)],
        plan: [],
      },
    };
    const items = backgroundItems([
      agent(1, {
        since: 15,
        transcript: withEntries([
          task('past', 'Past task', 5, { state: 'completed', endedAt: 8 }),
          nested,
        ]),
      }),
      // Not up yet: nothing of it counts.
      agent(2, {
        since: undefined,
        transcript: withEntries([task('t', 'x', 30)]),
      }),
    ]);

    expect(brief(items)).toStrictEqual(['task Inner task 1 running']);
  });

  test('items started in the same millisecond keep their places whichever ends first', () => {
    const one = running('m1', 'one', 100);
    const two = running('m2', 'two', 100);
    const tasks = [task('task-a', 'a', 100), task('task-b', 'b', 100)];
    const order = (
      more: Partial<BackgroundAgent>,
      other: Partial<BackgroundAgent>,
    ) =>
      backgroundItems([
        agent(1, { transcript: withEntries(tasks), ...more }),
        agent(2, { owner: { name: 'parser', colour: 0 }, ...other }),
      ]).map(({ name }) => name);
    const before = order(
      { monitors: [one, two] },
      { monitors: [running('m1', 'three', 100)] },
    );

    expect(before).toStrictEqual(['one', 'two', 'a', 'b', 'three']);
    // m2 and the other agent's ended first, then m1, and left (CHD-479);
    // the running task keeps its place, the ended one left (CHD-482).
    expect(
      order(
        {
          monitors: [],
          endedMonitors: [
            ended(two, { kind: 'stopped' }, 150),
            ended(one, { kind: 'exit', code: 0 }, 160),
          ],
          transcript: withEntries([
            tasks[0]!,
            task('task-b', 'b', 100, { state: 'completed', endedAt: 120 }),
          ]),
        },
        {
          endedMonitors: [
            ended(running('m1', 'three', 100), { kind: 'stopped' }, 110),
          ],
        },
      ),
    ).toStrictEqual(['a']);
  });

  test('an ended task leaves at once; what runs or asks stays (CHD-482)', () => {
    const items = backgroundItems([
      agent(1, {
        monitors: [running('m2', 'still', 10)],
        // A task, as an ended monitor leaves at once (CHD-479).
        transcript: withEntries(
          [
            task('task-0', 'before', 0, { state: 'completed', endedAt: 50 }),
            task('task-1', 'asking', 5),
            task('task-3', 'after', 20, {
              state: 'completed',
              endedAt: 150,
            }),
          ],
          {
            asking: [
              {
                id: 'e',
                mode: 'url',
                url: 'u',
                message: 'm',
                subagentId: 'task-1',
                at: 6,
              },
            ],
          },
        ),
      }),
    ]);

    expect(brief(items)).toStrictEqual([
      'task asking 1 asking',
      'monitor still 1 running',
    ]);
  });
});

function item(
  kind: BackgroundItem['kind'],
  status: BackgroundItem['status'],
): BackgroundItem {
  return { kind, id: 'x', key: 1, name: 'x', startedAt: 0, status };
}

const RUNNING = { group: 'running' } as const;
const ASKING = { group: 'asking', on: 'permission', since: 0 } as const;
const FAILED = { group: 'failed', endedAt: 0 } as const;
const DONE = { group: 'done', endedAt: 0 } as const;
const STOPPED = { group: 'stopped', endedAt: 0 } as const;

describe('the summary line', () => {
  test('a group per state, most urgent first, its kinds joined by and, each word by its count', () => {
    expect(
      summaryGroups([
        item('task', RUNNING),
        item('monitor', STOPPED),
        item('monitor', RUNNING),
        item('task', DONE),
        item('monitor', FAILED),
        item('task', ASKING),
        item('monitor', RUNNING),
      ]),
    ).toStrictEqual([
      { group: 'asking', text: '● 1 task asking' },
      { group: 'failed', text: '✗ 1 monitor failed' },
      { group: 'running', text: '2 monitors and 1 task running' },
      { group: 'done', text: '✓ 1 task done' },
      { group: 'stopped', text: '■ 1 monitor stopped' },
    ]);
    expect(summaryGroups([])).toStrictEqual([]);
    expect(
      summaryGroups([item('task', FAILED), item('task', FAILED)]),
    ).toStrictEqual([{ group: 'failed', text: '✗ 2 tasks failed' }]);
  });

  const text = (lines: SummaryPiece[][]) =>
    lines.map((line) => line.map((piece) => piece.text).join(''));
  const GROUPS = summaryGroups([
    item('task', ASKING),
    item('monitor', FAILED),
    item('monitor', RUNNING),
    item('monitor', RUNNING),
    item('task', RUNNING),
  ]);

  test('on one line where it fits, the label first and the groups joined by a dot', () => {
    const lines = summaryLines(GROUPS, 120);

    expect(text(lines)).toStrictEqual([
      'background  ● 1 task asking · ✗ 1 monitor failed · 2 monitors and 1 task running',
    ]);
    expect(lines[0]!.map(({ tone }) => tone)).toStrictEqual([
      'label',
      'plain',
      'asking',
      'plain',
      'plain',
      'failed',
      'plain',
      'plain',
      'running',
    ]);
  });

  test('too long, it breaks between groups, the next line under the first group', () => {
    expect(text(summaryLines(GROUPS, 74))).toStrictEqual([
      'background  ● 1 task asking · ✗ 1 monitor failed ·',
      '            2 monitors and 1 task running',
    ]);
    // Every line within the width, nothing cut.
    expect(text(summaryLines(GROUPS, 34))).toStrictEqual([
      'background  ● 1 task asking ·',
      '            ✗ 1 monitor failed ·',
      '            2 monitors and 1 task',
      '            running',
    ]);
  });

  test('a group longer than a line alone breaks between its words, its dot kept on its last', () => {
    const lines = text(
      summaryLines(
        summaryGroups([
          item('monitor', RUNNING),
          item('task', RUNNING),
          item('task', DONE),
        ]),
        26,
      ),
    );

    expect(lines).toStrictEqual([
      'background  1 monitor and',
      '            1 task',
      '            running ·',
      '            ✓ 1 task done',
    ]);
  });
});

describe('CHD-424 tester: background item edges', () => {
  test('same-millisecond monitor ids stay in numeric order across stopping and ending', () => {
    const items = backgroundItems([
      agent(1, {
        monitors: [
          running('m10', 'ten', 10),
          running('m11', 'eleven', 10),
          running('m1', 'one', 10),
        ],
        endedMonitors: [
          ended(running('m9', 'nine', 10), { kind: 'stopped' }, 20),
          ended(running('m2', 'two', 10), { kind: 'exit', code: 1 }, 30),
        ],
      }),
    ]);

    expect(items.map(({ id }) => id)).toStrictEqual(['m1', 'm10', 'm11']);
  });

  test('all ended task states leave immediately, including later ends; running tasks stay', () => {
    const items = backgroundItems([
      agent(1, {
        transcript: withEntries([
          ...(
            ['completed', 'failed', 'cancelled', 'disconnected'] as const
          ).map((state) => task(state, state, 10, { state, endedAt: 50 })),
          task('later', 'later', 20, { state: 'completed', endedAt: 51 }),
          task('running', 'running', 30),
        ]),
      }),
    ]);

    expect(items.map(({ id }) => id)).toStrictEqual(['running']);
  });

  test('resumed historical tasks are excluded even while running; a task started when the session came up remains', () => {
    const items = backgroundItems([
      agent(1, {
        since: 100,
        transcript: withEntries([
          task('past-running', 'past', 99),
          task('past-ended', 'past', 90, { state: 'completed', endedAt: 110 }),
          task('current', 'current', 100),
        ]),
      }),
    ]);

    expect(items.map(({ id }) => id)).toStrictEqual(['current']);
  });

  test('the oldest matching input or permission sets asking time, and an ended task ignores stale requests', () => {
    const transcript = withEntries([task('t', 'task', 10)], {
      turn: {
        status: 'awaiting_permission',
        turnId: 't1',
        since: 5,
        permissions: [
          { id: 'p-other', subagentId: 'other', at: 1, options: [] },
          { id: 'p-new', subagentId: 't', at: 40, options: [] },
          { id: 'p-old', subagentId: 't', at: 30, options: [] },
        ],
      },
      asking: [
        {
          id: 'e',
          subagentId: 't',
          mode: 'url',
          url: 'u',
          message: 'm',
          at: 20,
        },
      ],
    });
    const status = (value: Transcript) =>
      backgroundItems([agent(1, { transcript: value })])[0]?.status;

    expect(status(transcript)).toStrictEqual({
      group: 'asking',
      on: 'input',
      since: 20,
    });
    expect(status({ ...transcript, asking: [] })).toStrictEqual({
      group: 'asking',
      on: 'permission',
      since: 30,
    });
    expect(
      status({
        ...transcript,
        entries: [task('t', 'task', 10, { state: 'cancelled', endedAt: 50 })],
      }),
    ).toBeUndefined();
  });

  test('all summary words and separators survive wrapping at every width from 26 through 120', () => {
    const groups = summaryGroups([
      item('task', ASKING),
      item('monitor', FAILED),
      item('monitor', RUNNING),
      item('task', RUNNING),
      item('task', DONE),
      item('monitor', STOPPED),
    ]);
    const words =
      `background ${groups.map(({ text }) => text).join(' · ')}`.split(/\s+/);

    for (let width = 26; width <= 120; width++) {
      const lines = summaryLines(groups, width).map((line) =>
        line.map(({ text }) => text).join(''),
      );

      expect(lines.join(' ').trim().split(/\s+/)).toStrictEqual(words);
      expect(lines.every((line) => Array.from(line).length <= width)).toBe(
        true,
      );
      expect(
        lines.slice(1).every((line) => line.startsWith(' '.repeat(12))),
      ).toBe(true);
    }
  });
});

describe('the call that started an item', () => {
  const monitorCall = (id: string, callId: string): Entry => ({
    kind: 'tool',
    turnId: 't1',
    call: {
      id: callId,
      title: 'Monitor',
      chord: {
        tool: 'monitor',
        input: {},
        answer: { id, description: 'x', timeout_ms: 1000 },
      },
    },
  });
  const item = (kind: 'monitor' | 'task', id: string): BackgroundItem => ({
    kind,
    id,
    key: 1,
    name: 'x',
    startedAt: 0,
    status: { group: 'running' },
  });
  const text: Entry = { kind: 'user', turnId: 't1', text: 'hi' };

  test("a monitor's is its Monitor call, by the id its answer gave", () => {
    const entries = [text, monitorCall('m1', 'c1'), monitorCall('m2', 'c2')];

    expect(callPlace(entries, item('monitor', 'm2'))).toStrictEqual({
      entry: 2,
      target: 'call:c2',
    });
    expect(callPlace(entries, item('monitor', 'm9'))).toStrictEqual(undefined);
  });

  test("a task's is its own Agent block, or its own row in the group of tasks that draws it", () => {
    const entries = [
      text,
      task('task-1', 'one', 0),
      task('task-2', 'two', 0),
      text,
      task('task-3', 'three', 0),
    ];

    expect(callPlace(entries, item('task', 'task-1'))).toStrictEqual({
      entry: 1,
      target: 'agent:task-1',
    });
    expect(callPlace(entries, item('task', 'task-2'))).toStrictEqual({
      entry: 1,
      target: 'agent:task-2',
    });
    expect(callPlace(entries, item('task', 'task-3'))).toStrictEqual({
      entry: 4,
      target: 'agent:task-3',
    });
    expect(callPlace(entries, item('task', 'gone'))).toStrictEqual(undefined);
  });

  test("a call inside a subagent's work is in the subagent's entry, by its own box", () => {
    const claude: Entry = {
      kind: 'subagent',
      turnId: 't1',
      subagent: {
        id: 'claude-1',
        state: 'running',
        entries: [monitorCall('m1', 'c1'), task('task-1', 'inner', 0)],
        plan: [],
      },
    };

    expect(callPlace([text, claude], item('monitor', 'm1'))).toStrictEqual({
      entry: 1,
      target: 'call:c1',
    });
    expect(callPlace([text, claude], item('task', 'task-1'))).toStrictEqual({
      entry: 1,
      target: 'agent:task-1',
    });
  });
});

/** A subagent entry as Claude's adapter announces one, open to a cancel. */
function claude(
  id: string,
  startedAt: number,
  more: Partial<Subagent> = {},
  without: readonly (keyof Subagent)[] = [],
): Entry {
  const subagent: Record<string, unknown> = {
    id,
    title: `${id} (Explore)`,
    description: `Find ${id}`,
    state: 'running',
    startedAt,
    entries: [],
    plan: [],
    cancellable: true,
    offeredCancel: true,
    ...more,
  };

  for (const key of without) {
    delete subagent[key];
  }

  return {
    kind: 'subagent',
    turnId: 't1',
    subagent: subagent as unknown as Subagent,
  };
}

describe('agent items', () => {
  test('every subagent its agent announced is an agent item, named by its short task; one that offered no cancel stops nothing (Q135)', () => {
    const items = backgroundItems([
      agent(1, {
        transcript: withEntries([
          claude('a', 10, {
            entries: [claude('g', 12, {}, ['description'])],
          }),
          // Codex's draft form, and a replayed one, offer none: an item
          // still, that offers no stop (CHD-487).
          claude('b', 11, {}, ['cancellable', 'offeredCancel']),
          task('t', 'Fix the tokenizer', 13),
          // Lost its cancel since: still an item, with no stop.
          claude('l', 14, {}, ['cancellable']),
        ]),
      }),
    ]);

    expect(
      items.map(({ kind, name, stoppable }) => ({ kind, name, stoppable })),
    ).toStrictEqual([
      { kind: 'agent', name: 'Find a', stoppable: true },
      { kind: 'agent', name: 'Find b', stoppable: false },
      { kind: 'agent', name: 'g (Explore)', stoppable: true },
      { kind: 'task', name: 'Fix the tokenizer', stoppable: undefined },
      { kind: 'agent', name: 'Find l', stoppable: false },
    ]);
    // One from before its session came up is its past.
    expect(
      backgroundItems([
        agent(1, { since: 11, transcript: withEntries([claude('a', 10)]) }),
      ]),
    ).toStrictEqual([]);
  });

  test("an agent item stands as its subagent does, by CHD-2's table", () => {
    const status = (
      more: Partial<Subagent>,
      extra: Partial<BackgroundAgent> = {},
    ) =>
      backgroundItems([
        agent(1, {
          transcript: withEntries([claude('a', 10, more)]),
          ...extra,
        }),
      ])[0]?.status;

    expect(status({})).toStrictEqual({ group: 'running' });
    expect(status({}, { stopping: new Set(['a']) })).toStrictEqual({
      group: 'running',
      stopping: true,
    });
    expect(status({ waiting: { since: 20 } })).toStrictEqual({
      group: 'asking',
      on: 'waiting',
      since: 20,
    });
    expect(
      backgroundItems([
        agent(1, {
          transcript: withEntries(
            [claude('a', 10, { waiting: { since: 20 } })],
            {
              asking: [
                {
                  id: 'e',
                  subagentId: 'a',
                  at: 22,
                  request: {
                    message: 'Pick',
                    mode: 'form',
                    requestedSchema: { type: 'object', properties: {} },
                  },
                } as unknown as Transcript['asking'][number],
              ],
            },
          ),
        }),
      ])[0]?.status,
    ).toStrictEqual({ group: 'asking', on: 'input', since: 22 });

    // Ended, however, it has left the list (CHD-479).
    for (const state of [
      'completed',
      'failed',
      'disconnected',
      'cancelled',
      'ended',
    ] as const) {
      expect(status({ state, endedAt: 30 }), state).toStrictEqual(undefined);
    }

    expect(status({ state: 'untracked', endedAt: 30 })).toStrictEqual({
      group: 'untracked',
      endedAt: 30,
    });
  });

  test('the summary line counts agents after monitors and tasks, untracked after failed', () => {
    expect(
      summaryGroups([
        item('agent', { group: 'asking', on: 'waiting', since: 0 }),
        item('monitor', FAILED),
        item('agent', { group: 'untracked', endedAt: 0 }),
        item('monitor', RUNNING),
        item('agent', RUNNING),
        item('agent', { group: 'running', stopping: true }),
      ]).map(({ text }) => text),
    ).toStrictEqual([
      "● main's agent asking",
      '✗ 1 monitor failed',
      "? main's agent untracked",
      "1 monitor and main's 2 agents running",
    ]);
  });

  test("an agent phrase names each parent in the possessive, in the agents list's order (CHD-479)", () => {
    const of = (parent: string, parentAt: number): BackgroundItem => ({
      ...item('agent', RUNNING),
      parent,
      parentAt,
    });

    expect(
      summaryGroups([
        of('tester', 2),
        item('task', RUNNING),
        of('main', 0),
        of('tester', 2),
        of('parser', 1),
        of('main', 0),
      ]).map(({ text }) => text),
    ).toStrictEqual([
      "1 task and main's 2 agents and parser's agent and tester's 2 agents running",
    ]);
  });

  test('an untracked agent stays listed, as it has not ended; an ended one has left (CHD-479, Q110)', () => {
    const at = (more: Partial<Subagent>) =>
      brief(
        backgroundItems([
          agent(1, { transcript: withEntries([claude('a', 10, more)]) }),
        ]),
      );

    expect(at({ state: 'untracked', endedAt: 30 })).toStrictEqual([
      'agent Find a 1 untracked',
    ]);
    expect(at({ state: 'completed', endedAt: 50 })).toStrictEqual([]);
    expect(at({ state: 'running' })).toStrictEqual(['agent Find a 1 running']);
    expect(at({ state: 'untracked', endedAt: 50 })).toStrictEqual([
      'agent Find a 1 untracked',
    ]);
  });
});

describe('agent items from the fake', () => {
  /** The tab's items once `scenario` has played on the fake, at `answer`. */
  async function itemsAfter(
    scenario: string,
    options: PlayOptions = {},
  ): Promise<BackgroundItem[]> {
    const dir = await mkdtemp(join(tmpdir(), 'chord-background-'));
    const session = await openSession({
      agent: 'fake',
      cwd: dir,
      agentCommand: fakeAgentCommand(undefined, '--step-ms', '1'),
    });

    try {
      // Timed in the order they came, as the window times what it hears.
      const transcript = (await play(session, scenario, options))
        .map((action, at) =>
          action.type === 'update' ? { ...action, at: at + 1 } : action,
        )
        .reduce(reduceTranscript, emptyTranscript);

      return backgroundItems([agent(1, { transcript })]);
    } finally {
      await session.close();
      await rm(dir, { recursive: true });
    }
  }

  test("Claude's four subagents are agent items while they run, and only the untracked one stays once they end", async () => {
    const items = await itemsAfter('claudesubagents');

    expect(
      items.map(({ kind, name, status }) => [kind, name, status.group]),
      // Done, failed and stopped, they have left (CHD-479).
    ).toStrictEqual([['agent', 'Watch the build', 'untracked']]);
  });

  test("Claude's background agent stays running past the parent's cancel", async () => {
    const items = await itemsAfter('claudebackground', {
      cancelAfterEvents: 6,
    });

    expect(items.map(({ name, status }) => [name, status.group])).toStrictEqual(
      // The one the cancel stopped has left (CHD-479).
      [['Run the test suite', 'running']],
    );
  });
});

test('a stopped agent reads stopping while it still asks, until its agent says it ended', () => {
  const stopping = new Set(['a']);
  const asked = (waits: Partial<Transcript>, more: Partial<Subagent> = {}) =>
    backgroundItems([
      agent(1, {
        stopping,
        transcript: withEntries([claude('a', 10, more)], waits),
      }),
    ])[0]?.status;
  const form = {
    id: 'e',
    subagentId: 'a',
    at: 22,
  } as unknown as Transcript['asking'][number];
  const permission = {
    turn: {
      status: 'awaiting_permission',
      turnId: 't1',
      since: 5,
      permissions: [
        { id: 'p', subagentId: 'a', toolCallId: 'c', options: [], at: 21 },
      ],
    },
  } as unknown as Partial<Transcript>;
  const STOPPING = { group: 'running', stopping: true } as const;

  expect(asked({}, { waiting: { since: 20 } })).toStrictEqual(STOPPING);
  expect(asked(permission)).toStrictEqual(STOPPING);
  expect(asked({ asking: [form] })).toStrictEqual(STOPPING);
  // Its agent's end wins over the key: it has left (CHD-479).
  expect(asked({}, { state: 'completed', endedAt: 30 })).toStrictEqual(
    undefined,
  );
});

describe('an agent item names its parent, and which items leave as they end (CHD-479)', () => {
  test("an agent item's parent is the listed agent that announced it, a subagent's own too", () => {
    const items = backgroundItems([
      agent(1, {
        transcript: withEntries([
          claude('a', 10, { entries: [claude('g', 11)] }),
        ]),
      }),
      agent(2, {
        owner: { name: 'tester', colour: 3 },
        transcript: withEntries([
          claude('b', 12),
          task('t', 'Fix the tokenizer', 13),
        ]),
      }),
    ]);

    expect(
      items.map(({ kind, id, parent }) => ({ kind, id, parent })),
    ).toStrictEqual([
      { kind: 'agent', id: 'a', parent: 'main' },
      { kind: 'agent', id: 'g', parent: 'main' },
      { kind: 'agent', id: 'b', parent: 'tester' },
      { kind: 'task', id: 't', parent: undefined },
    ]);
  });

  test('every kind leaves once done, failed or stopped; running, asking and untracked stay (CHD-479, CHD-482)', () => {
    const at = (group: ItemStatus['group']): ItemStatus =>
      group === 'running'
        ? { group }
        : group === 'asking'
          ? { group, on: 'waiting', since: 1 }
          : { group, endedAt: 2 };
    const groups: readonly ItemStatus['group'][] = [
      'running',
      'asking',
      'untracked',
      'done',
      'failed',
      'stopped',
    ];

    expect(
      groups.filter((group) =>
        leavesList({ kind: 'agent', status: at(group) }),
      ),
    ).toStrictEqual(['done', 'failed', 'stopped']);
    expect(
      groups.filter((group) =>
        leavesList({ kind: 'monitor', status: at(group) }),
      ),
    ).toStrictEqual(['done', 'failed', 'stopped']);
    expect(
      groups.filter((group) => leavesList({ kind: 'task', status: at(group) })),
    ).toStrictEqual(['done', 'failed', 'stopped']);
  });
});

describe('the block an agent item goes to', () => {
  const item = (id: string): BackgroundItem => ({
    kind: 'agent',
    id,
    key: 1,
    name: 'x',
    startedAt: 0,
    status: { group: 'running' },
  });
  const text: Entry = { kind: 'user', turnId: 't1', text: 'hi' };

  test("its own Agent block, its own row in a group, or, inside another's work, its own box there", () => {
    const entries = [
      text,
      claude('a', 0),
      claude('b', 0),
      text,
      claude('c', 0, { entries: [claude('g', 1)] }),
    ];

    expect(callPlace(entries, item('a'))).toStrictEqual({
      entry: 1,
      target: 'agent:a',
    });
    expect(callPlace(entries, item('b'))).toStrictEqual({
      entry: 1,
      target: 'agent:b',
    });
    expect(callPlace(entries, item('g'))).toStrictEqual({
      entry: 4,
      target: 'agent:g',
    });
  });
});

describe('CHD-2 tester: agent item ownership and terminal precedence', () => {
  test('nested item order and owner remain stable when an untracked item persists and recovers', () => {
    const owner = { name: 'parser', colour: 2 };
    const listed = (state: Subagent['state']) =>
      backgroundItems([
        agent(1, { transcript: withEntries([claude('same', 20)]) }),
        agent(2, {
          owner,
          transcript: withEntries([
            claude('outer', 10, {
              entries: [claude('same', 15, { state, endedAt: 30 })],
            }),
          ]),
        }),
      ]);

    expect(listed('untracked').map(({ key, id }) => [key, id])).toStrictEqual([
      [2, 'outer'],
      [2, 'same'],
      [1, 'same'],
    ]);

    const recovered = listed('running');

    expect(recovered.map(({ key, id }) => [key, id])).toStrictEqual([
      [2, 'outer'],
      [2, 'same'],
      [1, 'same'],
    ]);
    expect(recovered[1]?.owner).toStrictEqual(owner);
    expect(recovered[1]?.startedAt).toBe(15);
  });

  test('all terminal wire states beat stopping and stale permission, input and waiting state', () => {
    for (const [state, group] of [
      ['completed', 'done'],
      ['failed', 'failed'],
      ['cancelled', 'stopped'],
      ['ended', 'stopped'],
      ['untracked', 'untracked'],
      ['disconnected', 'failed'],
    ] as const) {
      const transcript = withEntries(
        [claude('a', 10, { state, endedAt: 40, waiting: { since: 20 } })],
        {
          turn: {
            status: 'awaiting_permission',
            turnId: 't1',
            since: 21,
            permissions: [{ id: 'p', subagentId: 'a', options: [], at: 21 }],
          },
          asking: [
            {
              id: 'e',
              subagentId: 'a',
              mode: 'url',
              url: 'u',
              message: 'm',
              at: 22,
            },
          ],
        },
      );
      const [item] = backgroundItems([
        agent(1, { transcript, stopping: new Set(['a']) }),
      ]);

      if (group === 'untracked') {
        expect(item?.status).toMatchObject({ group, endedAt: 40 });
        expect(summaryGroups(item ? [item] : [])[0]?.group).toBe(group);
      } else {
        expect(item).toBeUndefined();
      }
    }
  });

  test('every group and kind survives narrow and wide summary wrapping with agent counts', () => {
    const groups = summaryGroups([
      item('agent', ASKING),
      item('agent', FAILED),
      item('agent', { group: 'untracked', endedAt: 0 }),
      item('monitor', RUNNING),
      item('task', RUNNING),
      item('agent', RUNNING),
      item('agent', DONE),
      item('agent', STOPPED),
    ]);
    const words =
      `background ${groups.map(({ text }) => text).join(' · ')}`.split(/\s+/);

    for (const width of [74, 114]) {
      const lines = summaryLines(groups, width).map((line) =>
        line.map(({ text }) => text).join(''),
      );

      expect(lines.join(' ').trim().split(/\s+/)).toStrictEqual(words);
      expect(lines.every((line) => Array.from(line).length <= width)).toBe(
        true,
      );
    }
  });
});

describe('CHD-2 tester: waiting fixture cancellation', () => {
  test('requires_action without a request cancels to stopped and the next prompt completes independently', async () => {
    const dir = await mkdtemp(join(tmpdir(), 'chord-waiting-'));
    const session = await openSession({
      agent: 'fake',
      cwd: dir,
      agentCommand: fakeAgentCommand(undefined, '--step-ms', '1'),
    });
    let requests = 0;
    const unsubscribe = session.permissions.subscribe(() => {
      requests++;
    });

    try {
      const actions = await play(session, 'claudewaiting', {
        cancelAfterEvents: 3,
      });
      const transcript = actions
        .map((action, at) =>
          action.type === 'update' ? { ...action, at: at + 1 } : action,
        )
        .reduce(reduceTranscript, emptyTranscript);

      expect(actions.at(-1)).toMatchObject({
        type: 'result',
        result: { status: 'cancelled' },
      });
      expect(
        backgroundItems([agent(1, { transcript })]).map(
          ({ status }) => status.group,
        ),
      ).toStrictEqual([]);
      expect(requests).toBe(0);

      const next = await play(session, 'claudewaiting');
      const finished = next
        .map((action, at) =>
          action.type === 'update' ? { ...action, at: at + 1 } : action,
        )
        .reduce(reduceTranscript, emptyTranscript);

      expect(
        backgroundItems([agent(1, { transcript: finished })]).map(
          ({ status }) => status.group,
        ),
      ).toStrictEqual([]);
      expect(requests).toBe(0);
    } finally {
      unsubscribe();
      await session.close();
      await rm(dir, { recursive: true });
    }
  });
});

describe('CHD-479 tester: parent identity survives nested and reused adapter ids', () => {
  test('the same adapter ids in different sessions retain distinct parents', () => {
    const items = backgroundItems([
      agent(17, {
        owner: { name: 'tester', colour: 1 },
        transcript: withEntries([
          claude('shared', 10, {
            entries: [claude('nested', 11, { entries: [claude('leaf', 12)] })],
          }),
        ]),
      }),
      agent(23, {
        owner: { name: 'coder', colour: 2 },
        transcript: withEntries([
          claude('shared', 10, { entries: [claude('nested', 11)] }),
        ]),
      }),
    ]);

    expect(
      items
        .filter(({ key }) => key === 17)
        .map(({ id, parent }) => ({ id, parent })),
    ).toStrictEqual([
      { id: 'shared', parent: 'tester' },
      { id: 'nested', parent: 'tester' },
      { id: 'leaf', parent: 'tester' },
    ]);
    expect(
      items
        .filter(({ key }) => key === 23)
        .map(({ id, parent }) => ({ id, parent })),
    ).toStrictEqual([
      { id: 'shared', parent: 'coder' },
      { id: 'nested', parent: 'coder' },
    ]);
    expect(new Set(items.map(({ key, id }) => `${key}:${id}`)).size).toBe(5);
  });

  test('an ancestor without cancel is not substituted for the listed parent', () => {
    const transcript = withEntries([
      claude(
        'container',
        10,
        {
          entries: [claude('inner', 11, { entries: [claude('leaf', 12)] })],
        },
        ['offeredCancel', 'cancellable'],
      ),
    ]);

    for (const owner of [undefined, { name: 'reviewer', colour: 3 }]) {
      const items = backgroundItems([
        agent(1, { transcript, ...(owner === undefined ? {} : { owner }) }),
      ]);

      expect(items.map(({ id, parent }) => ({ id, parent }))).toStrictEqual([
        { id: 'container', parent: owner?.name ?? 'main' },
        { id: 'inner', parent: owner?.name ?? 'main' },
        { id: 'leaf', parent: owner?.name ?? 'main' },
      ]);
    }
  });

  test('a still-untracked agent and its recovered stopping state keep the parent', () => {
    const make = (state: 'untracked' | 'running') =>
      backgroundItems([
        agent(31, {
          owner: { name: 'parser', colour: 0 },
          stopping: new Set(['same']),
          transcript: withEntries([claude('same', 10, { state })]),
        }),
      ]);
    const lost = make('untracked');
    const recovered = make('running');

    expect(lost[0]?.status.group).toBe('untracked');
    expect(recovered[0]?.status).toStrictEqual({
      group: 'running',
      stopping: true,
    });

    for (const item of [...lost, ...recovered]) {
      expect(item.parent).toBe('parser');
      expect(item.key).toBe(31);
      expect(item.id).toBe('same');
      expect(leavesList(item)).toBe(false);
    }
  });
});

describe('CHD-479 tester: parent order follows the list through live state changes', () => {
  test('interleaved start times cannot reorder parents, and a removed parent returns in its list position', () => {
    const list = (state: Subagent['state']) =>
      backgroundItems([
        agent(1, { transcript: withEntries([claude('main', 40)]) }),
        agent(2, {
          owner: { name: 'parser', colour: 1 },
          transcript: withEntries([claude('parser', 30, { state })]),
        }),
        agent(3, {
          owner: { name: 'tester', colour: 2 },
          transcript: withEntries([
            claude('tester-1', 10),
            claude('tester-2', 20),
          ]),
        }),
      ]);

    expect(list('running').map(({ parent }) => parent)).toStrictEqual([
      'tester',
      'tester',
      'parser',
      'main',
    ]);
    expect(
      summaryGroups(list('completed')).map(({ text }) => text),
    ).toStrictEqual(["main's agent and tester's 2 agents running"]);
    expect(
      summaryGroups(list('untracked')).map(({ text }) => text),
    ).toStrictEqual([
      "? parser's agent untracked",
      "main's agent and tester's 2 agents running",
    ]);

    const groups = summaryGroups(list('running'));
    const expected =
      "main's agent and parser's agent and tester's 2 agents running";

    expect(groups.map(({ text }) => text)).toStrictEqual([expected]);

    for (const width of [74, 114]) {
      expect(
        summaryLines(groups, width)
          .flat()
          .map(({ text }) => text)
          .join('')
          .replace(/\s+/g, ' ')
          .trim(),
      ).toBe(`background ${expected}`);
    }
  });
});

describe('a monitor item keeps what its detail says (CHD-481)', () => {
  test('its command, start, timeout and last batch with when it went; no batch before the first', () => {
    const quiet = running('m1', 'dev server', 100);
    const said = {
      ...running('m2', 'CI run', 200),
      command: 'bun test --watch',
      timeoutMs: 3_600_000,
      lastEvent: { lines: ['ok 1', 'ok 2'], at: 900 },
    };
    const items = backgroundItems([agent(1, { monitors: [quiet, said] })]);

    expect(
      items.map(({ id, command, startedAt, timeoutMs, lastEvent }) => ({
        id,
        command,
        startedAt,
        timeoutMs,
        lastEvent,
      })),
    ).toStrictEqual([
      {
        id: 'm1',
        command: 'cmd',
        startedAt: 100,
        timeoutMs: 600_000,
        lastEvent: undefined,
      },
      {
        id: 'm2',
        command: 'bun test --watch',
        startedAt: 200,
        timeoutMs: 3_600_000,
        lastEvent: { lines: ['ok 1', 'ok 2'], at: 900 },
      },
    ]);
    expect('lastEvent' in items[0]!).toStrictEqual(false);
  });
});

describe("an agent's or a task's detail (CHD-487)", () => {
  test('its item stays while its detail is open, ended or not, and leaves once the detail is left (Q136)', () => {
    const ended = agent(1, {
      transcript: withEntries([
        claude('a', 10, { state: 'completed', endedAt: 20 }),
        claude('b', 11, {}, ['cancellable', 'offeredCancel']),
      ]),
    });

    expect(backgroundItems([ended]).map(({ id }) => id)).toStrictEqual(['b']);
    expect(
      backgroundItems([ended], { key: 1, id: 'a' }).map(({ id }) => id),
    ).toStrictEqual(['a', 'b']);
  });

  test("its subagent is found at any depth, an agent's and a task's alike, none for a monitor", () => {
    const entries = withEntries([
      claude('a', 10, { entries: [claude('g', 12)] }),
      task('t', 'Fix the tokenizer', 13),
    ]).entries;

    expect(itemSubagent(entries, { kind: 'agent', id: 'g' })?.id).toBe('g');
    expect(itemSubagent(entries, { kind: 'task', id: 't' })?.id).toBe('t');
    expect(itemSubagent(entries, { kind: 'agent', id: 'x' })).toBe(undefined);
    expect(itemSubagent(entries, { kind: 'monitor', id: 'a' })).toBe(undefined);
  });
});

describe('CHD-487 U1 tester: retained non-cancellable rows are session-local', () => {
  test('keeping one ended nested agent never keeps its reused id in another session or its ancestor', () => {
    const transcript = withEntries([
      claude('outer', 10, {
        state: 'completed',
        endedAt: 30,
        entries: [
          claude('inner', 11, { state: 'disconnected', endedAt: 29 }, [
            'offeredCancel',
            'cancellable',
          ]),
        ],
      }),
    ]);
    const agents = [
      agent(1, { transcript }),
      agent(2, { transcript, owner: { name: 'other', colour: 2 } }),
    ];

    expect(backgroundItems(agents)).toEqual([]);
    expect(backgroundItems(agents, { key: 2, id: 'inner' })).toMatchObject([
      {
        id: 'inner',
        key: 2,
        parent: 'other',
        stoppable: false,
        status: { group: 'failed', word: 'disconnected', endedAt: 29 },
      },
    ]);
    expect(backgroundItems(agents, { key: 1, id: 'outer' })).toMatchObject([
      { id: 'outer', key: 1, parent: 'main', status: { group: 'done' } },
    ]);
    expect(backgroundItems(agents)).toEqual([]);
  });
});
