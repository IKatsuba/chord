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
  backgroundItems,
  callPlace,
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

    expect(brief(items)).toStrictEqual([
      'monitor CI run 1 failed',
      'task Fix the tokenizer 1 running',
      'monitor parser tests 2 running',
      'monitor dev server 1 running',
      'task Fix the printer 1 done',
    ]);
    expect(items[1]).toStrictEqual({
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
    expect(items[2]?.owner).toStrictEqual({ name: 'parser', colour: 0 });
  });

  test('a monitor that exits 0 is done, a stop stopped, any other end failed', () => {
    const monitor = running('m1', 'x', 0);
    const groups = (
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
        backgroundItems([
          agent(1, { endedMonitors: [ended(monitor, end, 5)] }),
        ])[0]?.status,
    );

    expect(groups).toStrictEqual([
      { group: 'done', endedAt: 5, end: { kind: 'exit', code: 0 } },
      { group: 'failed', endedAt: 5, end: { kind: 'exit', code: 2 } },
      {
        group: 'failed',
        endedAt: 5,
        end: { kind: 'signal', signal: 'SIGKILL' },
      },
      {
        group: 'failed',
        endedAt: 5,
        end: { kind: 'timed_out', timeoutMs: 1000 },
      },
      { group: 'failed', endedAt: 5, end: { kind: 'flooded', by: 'lines' } },
      { group: 'stopped', endedAt: 5, end: { kind: 'stopped' } },
    ]);
  });

  test('a task reported is done, a failed or gone one failed, a cancelled one stopped', () => {
    const states = (
      ['completed', 'failed', 'disconnected', 'cancelled'] as const
    ).map(
      (state) =>
        backgroundItems([
          agent(1, {
            transcript: withEntries([
              task('t', 'x', 10, { state, endedAt: 20 }),
            ]),
          }),
        ])[0]?.status,
    );

    expect(states).toStrictEqual([
      { group: 'done', endedAt: 20 },
      { group: 'failed', endedAt: 20 },
      { group: 'failed', endedAt: 20 },
      { group: 'stopped', endedAt: 20 },
    ]);
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
    // m2 and the other agent's ended first, then m1.
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
    ).toStrictEqual(before);
  });

  test("the person's prompt clears what ended before it; what runs or asks stays", () => {
    const items = backgroundItems(
      [
        agent(1, {
          monitors: [running('m2', 'still', 10)],
          endedMonitors: [
            ended(running('m1', 'before', 0), { kind: 'stopped' }, 50),
            ended(running('m3', 'after', 20), { kind: 'exit', code: 0 }, 150),
          ],
          transcript: withEntries([task('task-1', 'asking', 5)], {
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
          }),
        }),
      ],
      100,
    );

    expect(brief(items)).toStrictEqual([
      'task asking 1 asking',
      'monitor still 1 running',
      'monitor after 1 done',
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
        monitors: [running('m10', 'ten', 10)],
        endedMonitors: [
          ended(running('m9', 'nine', 10), { kind: 'stopped' }, 20),
          ended(running('m2', 'two', 10), { kind: 'exit', code: 1 }, 30),
        ],
      }),
    ]);

    expect(items.map(({ id }) => id)).toStrictEqual(['m2', 'm9', 'm10']);
  });

  test('a prompt clears every ended task state at its cutoff, but keeps later ends and running tasks', () => {
    const items = backgroundItems(
      [
        agent(1, {
          transcript: withEntries([
            ...(
              ['completed', 'failed', 'cancelled', 'disconnected'] as const
            ).map((state) => task(state, state, 10, { state, endedAt: 50 })),
            task('later', 'later', 20, { state: 'completed', endedAt: 51 }),
            task('running', 'running', 30),
          ]),
        }),
      ],
      50,
    );

    expect(items.map(({ id }) => id)).toStrictEqual(['later', 'running']);
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
    ).toStrictEqual({ group: 'stopped', endedAt: 50 });
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
  test('a subagent that offered its own cancel is an agent item, named by its short task; one that never did is not', () => {
    const items = backgroundItems([
      agent(1, {
        transcript: withEntries([
          claude('a', 10, {
            entries: [claude('g', 12, {}, ['description'])],
          }),
          // Codex's draft form, and a replayed one, offer none.
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
    expect(status({ state: 'completed', endedAt: 30 })).toStrictEqual({
      group: 'done',
      endedAt: 30,
    });
    expect(status({ state: 'failed', endedAt: 30 })).toStrictEqual({
      group: 'failed',
      endedAt: 30,
    });
    expect(status({ state: 'disconnected', endedAt: 30 })).toStrictEqual({
      group: 'failed',
      endedAt: 30,
      word: 'disconnected',
    });
    expect(status({ state: 'cancelled', endedAt: 30 })).toStrictEqual({
      group: 'stopped',
      endedAt: 30,
    });
    expect(status({ state: 'ended', endedAt: 30 })).toStrictEqual({
      group: 'stopped',
      endedAt: 30,
      word: 'ended',
    });
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
      '● 1 agent asking',
      '✗ 1 monitor failed',
      '? 1 agent untracked',
      '1 monitor and 2 agents running',
    ]);
  });

  test('the next prompt clears an ended or untracked agent, and one that comes back is listed again', () => {
    const at = (more: Partial<Subagent>) =>
      brief(
        backgroundItems(
          [agent(1, { transcript: withEntries([claude('a', 10, more)]) })],
          40,
        ),
      );

    expect(at({ state: 'untracked', endedAt: 30 })).toStrictEqual([]);
    expect(at({ state: 'completed', endedAt: 30 })).toStrictEqual([]);
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

  test("Claude's four subagents are agent items, each as it ended", async () => {
    const items = await itemsAfter('claudesubagents');

    expect(
      items.map(({ kind, name, status }) => [kind, name, status.group]),
    ).toStrictEqual([
      ['agent', 'Find the session layer', 'done'],
      ['agent', 'Review the transcript reducer', 'failed'],
      ['agent', 'Run the tests', 'stopped'],
      ['agent', 'Watch the build', 'untracked'],
    ]);
  });

  test("Claude's background agent stays running past the parent's cancel", async () => {
    const items = await itemsAfter('claudebackground', {
      cancelAfterEvents: 6,
    });

    expect(items.map(({ name, status }) => [name, status.group])).toStrictEqual(
      [
        ['Run the test suite', 'running'],
        ['Find the cancel path', 'stopped'],
      ],
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
  // Its agent's end wins over the key.
  expect(asked({}, { state: 'completed', endedAt: 30 })).toStrictEqual({
    group: 'done',
    endedAt: 30,
  });
});

describe('CHD-2 tester: agent item ownership and terminal precedence', () => {
  test('nested item order and owner remain stable when an untracked item clears and recovers', () => {
    const owner = { name: 'parser', colour: 2 };
    const listed = (state: Subagent['state']) =>
      backgroundItems(
        [
          agent(1, { transcript: withEntries([claude('same', 20)]) }),
          agent(2, {
            owner,
            transcript: withEntries([
              claude('outer', 10, {
                entries: [claude('same', 15, { state, endedAt: 30 })],
              }),
            ]),
          }),
        ],
        30,
      );

    expect(listed('untracked').map(({ key, id }) => [key, id])).toStrictEqual([
      [2, 'outer'],
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

      expect(item?.status.group).toBe(group);
      expect(item?.status).toMatchObject({ endedAt: 40 });
      expect(summaryGroups(item ? [item] : [])[0]?.group).toBe(group);
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
