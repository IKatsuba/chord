import { expect, jest, test } from 'bun:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import process from 'node:process';
import { join } from 'node:path';
import {
  Conversation,
  type ConversationEvent,
} from '../../src/session/conversation.ts';
import type { SignalName } from '../../src/platform/process.ts';
import { FileRecording } from '../../src/session/record.ts';
import { openSession } from '../../src/session/session.ts';
import { readRecords, type Resume } from '../../src/session/sessions.ts';
import { fromLine } from '../../src/session/tasks.ts';
import { reduceTranscript } from '../../src/session/transcript/reducer.ts';
import {
  emptyTranscript,
  type TranscriptAction,
} from '../../src/session/transcript/types.ts';
import { runShell, type ShellEnd, type ShellProcess } from '../../src/shell.ts';
import {
  endSentence,
  endWord,
  eventLine,
  type EventLines,
  eventText,
  FloodWatch,
  leftRunningLine,
  type MonitorInfo,
  monitorRefusal,
  MonitorRun,
  monitorsPast,
  NO_LINES,
  type RunCommand,
  timeoutWords,
  withLines,
} from '../../src/session/monitors.ts';
import type { MonitorEnd } from '../../src/session/transcript/types.ts';
import { fakeAgentCommand } from '../fixtures/fake.ts';

const INFO: MonitorInfo = {
  id: 'm1',
  description: 'dev server errors',
  command: 'tail -f dev.log',
  startedAt: 0,
  timeoutMs: 600_000,
};

/**
 * A command the test speaks for: `line` prints, `exit` ends it, `shellExits`
 * ends its shell with what it started still being reaped, and a stop ends it
 * as stopped, as `runShell` does once the group is gone.
 */
function fakeCommand() {
  let print: (line: string) => void = () => {};

  const { promise: ended, resolve: end } = Promise.withResolvers<ShellEnd>();
  const { promise: exited, resolve: exit } = Promise.withResolvers<ShellEnd>();
  const stops: number[] = [];
  const run: RunCommand = (_command, _cwd, onLine) => {
    print = onLine;

    const process: ShellProcess = {
      stop: () => {
        stops.push(Date.now());
        exit({ stopped: true });
        end({ stopped: true });
      },
      ended,
      exited,
    };

    return process;
  };

  return {
    run,
    stops,
    line: (line: string) => print(line),
    exit: (code: number, signal?: SignalName) => {
      const status = signal === undefined ? { code } : { code, signal };

      exit(status);
      end(status);
    },
    shellExits: (code: number) => exit({ code }),
    reaped: (status: ShellEnd) => end(status),
  };
}

/**
 * bun:test's fake timers from 0, real again once the test's `using` ends.
 * `setImmediate` stays real under them, so `settle` lets every settled
 * promise's callbacks run; `tick` settles, then moves the clock, firing the
 * timers due on the way.
 */
function fakeTime() {
  jest.useFakeTimers({ now: 0 });

  const settle = () => new Promise<void>((resolve) => setImmediate(resolve));

  return {
    settle,
    tick: async (ms: number) => {
      await settle();
      jest.advanceTimersByTime(ms);
    },
    [Symbol.dispose]: () => {
      jest.useRealTimers();
    },
  };
}

/** A monitor on a fake command, with what it handed on. */
function started(info: MonitorInfo = INFO) {
  const command = fakeCommand();
  const events: string[][] = [];
  const ends: [MonitorEnd, EventLines][] = [];
  const run = MonitorRun.start(
    info,
    {
      event: (lines) => events.push([...lines.lines]),
      ended: (end, rest) => ends.push([end, rest]),
    },
    '/tmp',
    command.run,
  );

  assert(run instanceof MonitorRun);

  return { ...command, monitor: run, events, ends };
}

test('a line is stripped of escapes and cut past 1,000 characters', () => {
  expect(eventLine('\u001b[31mERROR\u001b[0m boom')).toStrictEqual(
    'ERROR boom',
  );
  expect(eventLine('x'.repeat(1000))).toStrictEqual('x'.repeat(1000));
  expect(eventLine('é'.repeat(1003))).toStrictEqual(
    `${'é'.repeat(1000)}… (+3 characters)`,
  );
});

test('an event carries the first 100 lines or 16 KiB, and counts the rest', () => {
  const lines = Array.from({ length: 340 }, (_, index) => `line ${index}`);
  const event = withLines(NO_LINES, lines);

  expect(event.lines.length).toStrictEqual(100);
  expect(event.dropped).toStrictEqual(240);
  expect(eventText(event).split('\n').at(-1)).toStrictEqual(
    '… 240 more lines not delivered (an event carries at most 100)',
  );

  const wide = withLines(NO_LINES, Array(20).fill('y'.repeat(1000)));

  // 16 lines of 1,001 bytes fit in 16 KiB; the 17th does not.
  expect([wide.lines.length, wide.dropped]).toStrictEqual([16, 4]);

  // Once one is left out, later short ones are too: what goes is unbroken.
  const after = withLines(wide, ['short'], 2);

  expect([after.lines.length, after.dropped]).toStrictEqual([16, 7]);
  expect(
    eventText(withLines(NO_LINES, ['a', 'b']), 'Exited with code 0 after 1s.'),
  ).toStrictEqual('a\nb\nExited with code 0 after 1s.');
});

test('a flood is more than 1,000 lines or 256 KiB within any 10 s', () => {
  const lines = new FloodWatch();

  for (let index = 0; index < 1000; index++) {
    expect(lines.add(index, 10)).toStrictEqual(undefined);
  }

  expect(lines.add(1000, 10)).toStrictEqual('lines');

  // 1,000 lines a little over 10 s apart are no flood: the window slides.
  const slow = new FloodWatch();

  for (let index = 0; index < 2000; index++) {
    expect(slow.add(index * 11, 10)).toStrictEqual(undefined);
  }

  const bytes = new FloodWatch();

  expect(bytes.add(0, 200 * 1024)).toStrictEqual(undefined);
  expect(bytes.add(9_999, 57 * 1024)).toStrictEqual('bytes');
  expect(new FloodWatch().add(0, 300 * 1024)).toStrictEqual('bytes');

  const slid = new FloodWatch();

  slid.add(0, 200 * 1024);
  expect(slid.add(10_000, 200 * 1024)).toStrictEqual(undefined);
});

test("lines within 200 ms of a batch's first go as one event, on a fixed window", async () => {
  using time = fakeTime();
  const { line, events, monitor } = started();

  line('one');
  await time.tick(100);
  line('two');
  await time.tick(99);
  expect(events).toStrictEqual([]);
  await time.tick(1);
  expect(events).toStrictEqual([['one', 'two']]);

  // A steady stream is not pushed back: every 200 ms a batch goes.
  for (let tick = 0; tick < 8; tick++) {
    line(`steady ${tick}`);
    await time.tick(50);
  }

  expect(events.slice(1)).toStrictEqual([
    ['steady 0', 'steady 1', 'steady 2', 'steady 3'],
    ['steady 4', 'steady 5', 'steady 6', 'steady 7'],
  ]);
  expect(monitor.running.events).toStrictEqual(3);

  monitor.stop('close');
});

test('a command that exits ends the monitor with its code, the lines not yet sent first', async () => {
  using time = fakeTime();
  const { line, exit, events, ends } = started();

  line('\u001b[1mbuilt\u001b[0m');
  exit(1);
  await time.settle();

  expect(events).toStrictEqual([]);
  expect(ends.map(([end, rest]) => [end, rest.lines])).toStrictEqual([
    [{ kind: 'exit', code: 1 }, ['built']],
  ]);

  // Nothing is sent twice: the batch went with the end.
  await time.tick(500);
  expect(events).toStrictEqual([]);
});

test('a signal chord did not send ends it as killed by that signal', async () => {
  using time = fakeTime();
  const { exit, ends } = started();

  exit(137, 'SIGKILL');
  await time.settle();

  expect(ends.map(([end]) => end)).toStrictEqual([
    { kind: 'signal', signal: 'SIGKILL' },
  ]);
});

test('its timeout stops it and ends it as timed out', async () => {
  using time = fakeTime();
  const { stops, ends } = started({ ...INFO, timeoutMs: 1000 });

  await time.tick(999);
  expect(stops).toStrictEqual([]);
  await time.tick(1);
  expect(stops).toStrictEqual([1000]);
  expect(ends.map(([end]) => end)).toStrictEqual([
    { kind: 'timed_out', timeoutMs: 1000 },
  ]);
});

test('once its shell exits, that code is its end, though a timeout or a flood comes while what it left is reaped', async () => {
  using time = fakeTime();
  const { line, shellExits, reaped, stops, events, ends } = started({
    ...INFO,
    timeoutMs: 1000,
  });

  line('pid 42');
  shellExits(7);
  await time.settle();

  // What is still in the pipe is batched as before; the timeout is gone.
  await time.tick(2000);
  expect(events).toStrictEqual([['pid 42']]);
  expect(stops).toStrictEqual([]);

  for (let i = 0; i <= 1000; i += 1) {
    line(`late ${i}`);
  }

  expect(stops).toStrictEqual([]);
  reaped({ code: 7 });
  await time.settle();

  expect(
    ends.map(([end, rest]) => [end, rest.lines.length, rest.dropped]),
  ).toStrictEqual([[{ kind: 'exit', code: 7 }, 100, 901]]);
});

test('a flood stops it at once, with the first 100 lines as the sample', async () => {
  using time = fakeTime();
  const { line, stops, events, ends } = started();

  for (let index = 1; index <= 1500; index++) {
    line(`GET /health ${index}`);
  }

  await time.settle();

  expect(stops).toStrictEqual([0]);
  expect(events).toStrictEqual([]);

  const [[end, rest] = []] = ends;

  expect(end).toStrictEqual({ kind: 'flooded', by: 'lines' });
  expect(rest?.lines.length).toStrictEqual(100);
  expect(rest?.lines[0]).toStrictEqual('GET /health 1');
  // The 1,001st line flooded it; nothing after it was read.
  expect(rest?.dropped).toStrictEqual(901);
});

test.skipIf(process.platform === 'win32')(
  "a progress bar's 1,001 redraws are one line, not a flood",
  async () => {
    const { promise: ended, resolve: finish } =
      Promise.withResolvers<[MonitorEnd, EventLines]>();
    const events: string[][] = [];
    const run = MonitorRun.start(
      {
        ...INFO,
        command:
          "i=0; while [ $i -lt 1001 ]; do printf 'x\\r'; i=$((i+1)); done; " +
          "sleep 0.2; printf 'done\\n'",
      },
      {
        event: (lines) => events.push([...lines.lines]),
        ended: (end, rest) => finish([end, rest]),
      },
      process.cwd(),
      (command, cwd, onLine) =>
        runShell(command, {
          cwd,
          shell: ['/bin/sh', '-c'],
          onLine,
          reap: true,
        }),
    );

    expect(run instanceof MonitorRun).toBeTruthy();

    const [monitorEnd, rest] = await ended;

    expect(monitorEnd).toStrictEqual({ kind: 'exit', code: 0 });
    // One line, cut past 1,000 characters, which went with the end.
    expect(events).toStrictEqual([]);
    expect(rest.lines.length).toStrictEqual(1);
    expect(rest.lines[0]!.startsWith('x\rx\r'), rest.lines[0]).toBeTruthy();
  },
);

test("the person's stop is told; the agent's and a close's are not", async () => {
  using time = fakeTime();
  const person = started();
  const agent = started();
  const close = started();

  person.line('half a batch');
  person.monitor.stop('person');
  agent.monitor.stop('agent');
  close.monitor.stop('close');
  await time.tick(1000);

  expect(person.ends.map(([end, rest]) => [end, rest.lines])).toStrictEqual([
    [{ kind: 'stopped' }, ['half a batch']],
  ]);
  expect([agent.ends, close.ends, person.events]).toStrictEqual([[], [], []]);
});

test('a shell that does not start is the refusal', () => {
  const failed = MonitorRun.start(
    INFO,
    {
      event: () => {},
      ended: () => {},
    },
    '/tmp',
    () => ({
      stop: () => {},
      ended: Promise.resolve({ error: 'No such file or directory' }),
      failed: 'No such file or directory',
    }),
  );

  expect(failed).toStrictEqual({
    error: 'Could not start the command: No such file or directory',
  });
});

test('what monitor is asked is refused, never clamped, outside its bounds', () => {
  const asked = { command: 'tail -f log', description: 'log' };

  expect(monitorRefusal(asked, 7)).toStrictEqual(undefined);
  expect(monitorRefusal(asked, 8)).toStrictEqual(
    'This session has 8 monitors running; stop_monitor one first',
  );

  for (const description of ['', 'two\nlines', 'x'.repeat(61)]) {
    expect(monitorRefusal({ ...asked, description }, 0)).toStrictEqual(
      'description is at most 60 characters on one line; it is shown on ' +
        'every event',
    );
  }

  expect(
    monitorRefusal({ ...asked, description: 'é'.repeat(60) }, 0),
  ).toStrictEqual(undefined);

  for (const timeoutMs of [999, 3_600_001, 1500.5]) {
    expect(monitorRefusal({ ...asked, timeoutMs }, 0)).toStrictEqual(
      'timeout_ms is between 1000 and 3600000 (1h)',
    );
  }

  expect(monitorRefusal({ ...asked, timeoutMs: 1000 }, 0)).toStrictEqual(
    undefined,
  );
  expect(monitorRefusal({ ...asked, timeoutMs: 3_600_000 }, 0)).toStrictEqual(
    undefined,
  );
});

test('each end has its word and its sentence', () => {
  const said = (end: MonitorEnd, ran = 363_000) =>
    `${endWord(end)} | ${endSentence(end, ran)}`;

  expect(said({ kind: 'exit', code: 0 })).toStrictEqual(
    'exit code 0 | Exited with code 0 after 6m 3s.',
  );
  expect(said({ kind: 'exit', code: 127 }, 0)).toStrictEqual(
    'exit code 127 | Exited with code 127 (command not found) after 0s.',
  );
  expect(said({ kind: 'exit', code: 126 }, 0)).toStrictEqual(
    'exit code 126 | Exited with code 126 (not executable) after 0s.',
  );
  expect(said({ kind: 'signal', signal: 'SIGKILL' })).toStrictEqual(
    'killed by SIGKILL | Killed by SIGKILL after 6m 3s.',
  );
  expect(said({ kind: 'timed_out', timeoutMs: 600_000 })).toStrictEqual(
    'timed out | Timed out after 10m (timeout_ms 600000); chord stopped it.',
  );
  expect(said({ kind: 'stopped' }, 252_000)).toStrictEqual(
    'stopped | The person stopped it after 4m 12s.',
  );
  expect(said({ kind: 'flooded', by: 'lines' })).toStrictEqual(
    'flooded | chord stopped it: 1,000 lines in 10s is more than a monitor ' +
      'may print. Filter its output (grep --line-buffered) and start it again.',
  );
  expect(
    endSentence({ kind: 'flooded', by: 'bytes' }, 0).split(':')[1],
  ).toStrictEqual(
    ' 256 KiB in 10s is more than a monitor may print. Filter its output (grep --line-buffered) and start it again.',
  );
  expect([
    timeoutWords(1000),
    timeoutWords(90_000),
    timeoutWords(3_600_000),
  ]).toStrictEqual(['1s', '1m 30s', '1h']);
});

test("a past's monitors: the next id, how each ended, and those left running", () => {
  const served = (tool: 'monitor' | 'stop_monitor', answer: unknown) => ({
    type: 'served' as const,
    turnId: 't',
    call: { tool, input: {}, answer },
  });

  expect(
    monitorsPast([
      served('monitor', { id: 'm1', description: 'log', timeout_ms: 1000 }),
      served('monitor', { id: 'm2', description: 'CI', timeout_ms: 1000 }),
      served('monitor', { id: 'm3', description: 'tests', timeout_ms: 1000 }),
      served('stop_monitor', { id: 'm3', description: 'tests' }),
      {
        type: 'served',
        turnId: 't',
        call: { tool: 'monitor', input: {}, error: 'refused' },
      },
      {
        type: 'prompt',
        turnId: 't',
        text: 'done',
        at: 0,
        from: {
          name: 'log',
          monitor: { id: 'm1', end: { kind: 'exit', code: 0 } },
        },
      },
      {
        type: 'prompt',
        turnId: 't',
        text: 'a line',
        at: 0,
        from: { name: 'CI', monitor: { id: 'm2' } },
      },
    ]),
  ).toStrictEqual({
    last: 3,
    ended: new Map([
      ['m3', 'stopped'],
      ['m1', 'exit code 0'],
    ]),
    left: [{ id: 'm2', description: 'CI' }],
  });
  expect(monitorsPast([])).toStrictEqual({
    last: 0,
    ended: new Map(),
    left: [],
  });
});

/** Until `check` holds, or fails the test after `ms`. */
async function until(check: () => boolean, ms = 10_000): Promise<void> {
  const deadline = Date.now() + ms;

  while (!check()) {
    expect(Date.now() < deadline, 'waited too long').toBeTruthy();
    await new Promise((resolve) => setTimeout(resolve, 10));
  }
}

/** Whether process `pid` is still there. */
function alive(pid: number): boolean {
  try {
    process.kill(pid, 'SIGCONT');

    return true;
  } catch {
    return false;
  }
}

/**
 * A conversation with the fake agent, up, in a directory of its own, and
 * what it reported; recorded into `stateDir` when given, and resuming
 * `resume`.
 */
async function withAgent(
  body: (
    conversation: Conversation,
    events: ConversationEvent[],
    dir: string,
  ) => Promise<void>,
  {
    stateDir,
    resume,
    dir: given,
  }: {
    stateDir?: string;
    resume?: Resume;
    dir?: string;
  } = {},
): Promise<void> {
  const dir = given ?? (await mkdtemp(join(tmpdir(), 'chord-monitor-')));
  const events: ConversationEvent[] = [];
  const conversation = new Conversation(
    (signal) =>
      openSession({
        agent: 'fake',
        cwd: dir,
        agentCommand: fakeAgentCommand(
          undefined,
          ...(resume === undefined ? [] : ['--resume-only']),
        ),
        signal,
        ...(resume === undefined ? {} : { resume }),
      }),
    (event) => events.push(event),
    Date.now,
    {},
    stateDir === undefined
      ? undefined
      : new FileRecording(stateDir, (message) => {
          throw new Error(message);
        }),
  );

  try {
    conversation.start();
    await until(() => events.some((event) => event.type === 'connected'));
    await body(conversation, events, dir);
  } finally {
    await conversation.close();

    if (given === undefined) {
      await rm(dir, { recursive: true });
    }
  }
}

/** The monitor messages that went to the agent: who, and what. */
function delivered(events: readonly ConversationEvent[]) {
  return events.flatMap((event) =>
    event.type === 'prompt' && event.from?.monitor !== undefined
      ? [{ from: event.from, text: event.text }]
      : [],
  );
}

function idOf(answer: unknown): string {
  assert(
    typeof answer === 'object' &&
      answer !== null &&
      'id' in answer &&
      typeof answer.id === 'string',
    `not started: ${JSON.stringify(answer)}`,
  );

  return answer.id;
}

test('a real command: each batch is a turn for the agent, and its exit code the last', () =>
  withAgent(async (conversation, events, dir) => {
    idOf(
      conversation.startMonitor(
        {
          command:
            "printf 'one\\n'; sleep 0.6; printf 'two\\nthree\\n'; " +
            'sleep 0.6; exit 3',
          description: 'steps',
        },
        dir,
      ),
    );
    await until(() =>
      delivered(events).some(({ from }) => from.monitor?.end !== undefined),
    );

    const messages = delivered(events);

    expect(messages.slice(0, 2).map(({ text }) => text)).toStrictEqual([
      'one',
      'two\nthree',
    ]);
    expect(
      /^Exited with code 3 after \ds\.$/.test(messages[2]!.text),
    ).toBeTruthy();
    expect(messages.map(({ from }) => from)).toStrictEqual([
      { name: 'steps', monitor: { id: 'm1' } },
      { name: 'steps', monitor: { id: 'm1' } },
      {
        name: 'steps',
        monitor: { id: 'm1', end: { kind: 'exit', code: 3 } },
      },
    ]);
    // The running list had it, then lost it.
    expect(
      events.flatMap((event) =>
        event.type === 'monitors'
          ? [event.monitors.map(({ id, events }) => `${id}:${events}`)]
          : [],
      ),
    ).toStrictEqual([['m1:0'], ['m1:1'], ['m1:2'], []]);
    expect(conversation.monitors).toStrictEqual([]);
    expect(conversation.stopMonitor('m1')).toStrictEqual({
      error: 'm1 already ended: exit code 3',
    });
  }));

test('a batch that comes while the agent is in a turn waits behind it, later batches joining it', () =>
  withAgent(async (conversation, events, dir) => {
    conversation.send('permission');
    await until(() =>
      events.some((event) => event.type === 'permission_requested'),
    );

    const asked = events.find((event) => event.type === 'permission_requested');

    idOf(
      conversation.startMonitor(
        {
          command: "printf 'first\\n'; sleep 0.5; printf 'second\\n'; sleep 30",
          description: 'log',
        },
        dir,
      ),
    );

    const queued = () =>
      events.flatMap((event) =>
        event.type === 'queued' && event.from?.monitor !== undefined
          ? [event]
          : [],
      );

    await until(() => queued().length === 2);

    // One message, reported again as the second batch joined it.
    expect(new Set(queued().map(({ turnId }) => turnId)).size).toStrictEqual(1);
    expect(queued().map(({ text }) => text)).toStrictEqual([
      'first',
      'first\nsecond',
    ]);
    expect(delivered(events)).toStrictEqual([]);

    assert(asked?.type === 'permission_requested');
    conversation.choose(asked.permission.id, 'allow');
    await until(() => delivered(events).length === 1);

    expect(delivered(events)[0]?.text).toStrictEqual('first\nsecond');
    expect(
      events.findIndex((event) => event.type === 'prompt' && event.from) >
        events.findIndex(
          (event) =>
            event.type === 'result' && !event.turnId.startsWith('history-'),
        ),
    ).toStrictEqual(true);
  }));

test('a monitor past its timeout_ms is stopped, and the agent told', () =>
  withAgent(async (conversation, events, dir) => {
    idOf(
      conversation.startMonitor(
        {
          command: 'sleep 30',
          description: 'waits',
          timeoutMs: 1000,
        },
        dir,
      ),
    );
    await until(() => delivered(events).length === 1);

    expect(delivered(events)).toStrictEqual([
      {
        from: {
          name: 'waits',
          monitor: { id: 'm1', end: { kind: 'timed_out', timeoutMs: 1000 } },
        },
        text: 'Timed out after 1s (timeout_ms 1000); chord stopped it.',
      },
    ]);
  }));

test('a monitor that floods is stopped, its first lines the sample', () =>
  withAgent(async (conversation, events, dir) => {
    idOf(
      conversation.startMonitor(
        {
          command:
            'i=0; while [ $i -lt 3000 ]; do echo "line $i"; ' +
            'i=$((i+1)); done; sleep 30',
          description: 'busy',
        },
        dir,
      ),
    );
    await until(() =>
      delivered(events).some(({ from }) => from.monitor?.end !== undefined),
    );

    const end = delivered(events).at(-1)!;
    const lines = end.text.split('\n');

    expect(end.from.monitor?.end).toStrictEqual({
      kind: 'flooded',
      by: 'lines',
    });
    expect(lines.at(-1)).toStrictEqual(
      'chord stopped it: 1,000 lines in 10s is more than a monitor may ' +
        'print. Filter its output (grep --line-buffered) and start it again.',
    );
    expect(/^… \d+ more lines not delivered/.test(lines.at(-2)!)).toBeTruthy();
    expect(lines.length <= 102).toBeTruthy();
    expect(conversation.monitors).toStrictEqual([]);
  }));

test("the agent's stop_monitor stops it with no message, the person's with one; a closing session stops the rest, whole groups", async () => {
  let pids: number[] = [];

  await withAgent(async (conversation, events, dir) => {
    // In the monitors' order, m1 first: their first lines can come in any.
    const spawned = () =>
      delivered(events)
        .filter(({ from }) => from.monitor?.end === undefined)
        .toSorted((a, b) =>
          (a.from.monitor?.id ?? '').localeCompare(b.from.monitor?.id ?? ''),
        )
        .flatMap(({ text }) =>
          text
            .split('\n')
            .map(Number)
            .filter((pid) => pid > 0),
        );

    for (const description of ['one', 'two', 'three']) {
      idOf(
        conversation.startMonitor(
          {
            // What the shell starts in the background is in its group.
            command: 'sleep 30 & echo $!; wait',
            description,
          },
          dir,
        ),
      );
    }

    await until(() => spawned().length === 3);

    pids = spawned();

    expect(pids.every(alive)).toBeTruthy();

    const stopped = conversation.stopMonitor('m1');

    assert(!('error' in stopped));
    expect([stopped.id, stopped.description, stopped.events]).toStrictEqual([
      'm1',
      'one',
      1,
    ]);
    await until(() => !alive(pids[0]!));
    expect(conversation.monitors.map(({ id }) => id)).toStrictEqual([
      'm2',
      'm3',
    ]);
    expect(conversation.stopMonitor('m1')).toStrictEqual({
      error: 'm1 already ended: stopped',
    });
    expect(conversation.stopMonitor('m9')).toStrictEqual({
      error: 'No running monitor m9 of yours; list_monitors names them',
    });
    await new Promise((resolve) => setTimeout(resolve, 300));
    expect(
      delivered(events).filter(({ from }) => from.monitor?.end),
    ).toStrictEqual([]);

    conversation.stopMonitor('m2', 'person');
    // Off the list at once; its message follows once the group is gone.
    expect(conversation.monitors.map(({ id }) => id)).toStrictEqual(['m3']);
    await until(() =>
      delivered(events).some(({ from }) => from.monitor?.end !== undefined),
    );

    const ends = delivered(events).filter(({ from }) => from.monitor?.end);

    expect(ends.map(({ from }) => from.monitor)).toStrictEqual([
      { id: 'm2', end: { kind: 'stopped' } },
    ]);
    expect(
      /^The person stopped it after \d+s\.$/.test(ends[0]!.text),
    ).toBeTruthy();
    expect(!alive(pids[1]!)).toBeTruthy();
    expect(conversation.monitors.map(({ id }) => id)).toStrictEqual(['m3']);
  });

  // The close waited for the group to go.
  expect(pids.map(alive)).toStrictEqual([false, false, false]);
});

test("a monitor's messages are in the record, and a resume names the one left running and goes on from its ids", async () => {
  const dir = await mkdtemp(join(tmpdir(), 'chord-monitor-'));
  const stateDir = join(dir, 'state');
  const serve = (
    conversation: Conversation,
    tool: 'monitor' | 'stop_monitor',
    input: unknown,
    answer: unknown,
  ) =>
    conversation.served(
      typeof answer === 'object' && answer !== null && 'error' in answer
        ? { tool, input, error: String(answer.error) }
        : { tool, input, answer },
    );
  let sessionId = '';

  try {
    await withAgent(
      async (conversation, events) => {
        conversation.send('text');
        await until(() => events.some((event) => event.type === 'result'));

        sessionId = conversation.session!.id;

        for (const input of [
          { command: "printf 'built\\n'", description: 'build' },
          { command: 'sleep 30', description: 'watch' },
        ]) {
          serve(
            conversation,
            'monitor',
            input,
            conversation.startMonitor(input, dir),
          );
        }

        await until(
          () => events.filter((event) => event.type === 'result').length === 2,
        );
      },
      { stateDir, dir },
    );

    const [record] = await readRecords(stateDir);

    assert(record !== undefined);

    await withAgent(
      (conversation, events) => {
        const transcript = events
          .flatMap((event) =>
            event.type === 'connected' || !('turnId' in event) ? [] : [event],
          )
          .filter(
            (event): event is TranscriptAction =>
              event.type !== 'usage' && event.type !== 'queued',
          )
          .reduce(reduceTranscript, emptyTranscript);

        expect(
          transcript.entries.flatMap((entry) =>
            entry.kind === 'message'
              ? [`${fromLine(entry.from)}: ${entry.text}`]
              : entry.kind === 'monitors_left'
                ? [leftRunningLine(entry.monitors)]
                : [],
          ),
        ).toStrictEqual([
          'build · monitor · exit code 0: built\nExited with code 0 after 0s.',
          'watch was running when this session was left and is not restarted',
        ]);
        expect(
          idOf(
            conversation.startMonitor(
              {
                command: 'true',
                description: 'next',
              },
              dir,
            ),
          ),
        ).toStrictEqual('m3');
        expect(conversation.stopMonitor('m1')).toStrictEqual({
          error: 'm1 already ended: exit code 0',
        });
        expect(conversation.stopMonitor('m2')).toStrictEqual({
          error:
            'm2 was running when this session was left and was not ' +
            'restarted; monitor starts another',
        });

        return Promise.resolve();
      },
      {
        stateDir,
        dir,
        resume: { sessionId, cwd: dir, record: record.path },
      },
    );
  } finally {
    await rm(dir, { recursive: true });
  }
});

test("a monitor stopped by the person, timed out or flooded before a /clear ends after it, and leaves the new session's monitors be", () =>
  withAgent(async (conversation, events, dir) => {
    // Each old command ends only when the test says, well after the clear.
    const commands = [fakeCommand(), fakeCommand(), fakeCommand()];

    for (const [index, description] of [
      'stopped',
      'timed',
      'flooded',
    ].entries()) {
      idOf(
        conversation.startMonitor(
          {
            command: 'old',
            description,
            timeoutMs: 1000,
          },
          dir,
          (command, cwd, onLine) => {
            const process = commands[index]!.run(command, cwd, onLine);

            return {
              stop: () => commands[index]!.stops.push(Date.now()),
              ended: process.ended,
            };
          },
        ),
      );
    }

    conversation.stopMonitor('m1', 'person');

    for (let i = 0; i <= 1000; i++) {
      commands[2]!.line(`line ${i}`);
    }

    await until(() => commands.every(({ stops }) => stops.length === 1));

    conversation.clear();
    await until(
      () => events.filter((event) => event.type === 'connected').length === 2,
    );

    const cleared = events.findIndex((event) => event.type === 'cleared');

    for (const description of ['one', 'two', 'three']) {
      idOf(
        conversation.startMonitor({ command: 'sleep 30', description }, dir),
      );
    }

    for (const command of commands) {
      command.exit(0);
    }

    await new Promise((resolve) => setTimeout(resolve, 300));

    expect(
      conversation.monitors.map(
        ({ id, description }) => `${id} ${description}`,
      ),
    ).toStrictEqual(['m1 one', 'm2 two', 'm3 three']);
    expect(delivered(events.slice(cleared))).toStrictEqual([]);

    // Still the new session's to stop, and close.
    const stopped = conversation.stopMonitor('m1');

    assert(!('error' in stopped));
    expect(stopped.description).toStrictEqual('one');
  }));

test('a command that exits takes what it left running in the background with it, its code kept', async () => {
  let pid = 0;

  try {
    await withAgent(async (conversation, events, dir) => {
      idOf(
        conversation.startMonitor(
          {
            // Lets go of the pipes, so the shell's end is the monitor's.
            command: 'sleep 30 >/dev/null 2>&1 & echo $!',
            description: 'leaves one',
          },
          dir,
        ),
      );
      await until(() =>
        delivered(events).some(({ from }) => from.monitor?.end !== undefined),
      );

      const messages = delivered(events);

      pid = Number(messages[0]!.text.split('\n')[0]);

      expect(pid > 0).toBeTruthy();
      expect(messages.at(-1)!.from.monitor?.end).toStrictEqual({
        kind: 'exit',
        code: 0,
      });
      expect(conversation.monitors).toStrictEqual([]);
      expect(!alive(pid)).toBeTruthy();
    });
  } finally {
    if (pid > 0 && alive(pid)) {
      process.kill(pid, 'SIGKILL');
    }
  }
});

/**
 * Runs `command` as a monitor with a 1 s timeout, until its end comes, and
 * hands back that end, the PID it printed, and whether that PID was alive
 * once the monitor was off the list.
 */
async function leavesOne(command: string) {
  let pid = 0;

  try {
    let result: { end: unknown; aliveAfter: boolean } | undefined;

    await withAgent(async (conversation, events, dir) => {
      idOf(
        conversation.startMonitor(
          {
            command,
            description: 'leaves one',
            timeoutMs: 1000,
          },
          dir,
        ),
      );
      await until(() =>
        delivered(events).some(({ from }) => from.monitor?.end !== undefined),
      );

      const messages = delivered(events);

      pid = Number(
        messages
          .map(({ text }) => text)
          .join('\n')
          .match(/^\d+$/m)?.[0],
      );

      expect(pid > 0).toBeTruthy();
      expect(conversation.monitors).toStrictEqual([]);

      result = {
        end: messages.at(-1)!.from.monitor?.end,
        aliveAfter: alive(pid),
      };
    });

    return result!;
  } finally {
    if (pid > 0 && alive(pid)) {
      process.kill(pid, 'SIGKILL');
    }
  }
}

test('a shell that exits while what it started still holds stdout ends with its own code, not the timeout', async () => {
  expect(await leavesOne('sleep 30 & echo $!; exit 7')).toStrictEqual({
    end: { kind: 'exit', code: 7 },
    aliveAfter: false,
  });
});

test("a shell's code stays its end while what it left shrugs off SIGTERM past the timeout", async () => {
  expect(
    await leavesOne(
      "(trap '' TERM; sleep 30) >/dev/null 2>&1 & echo $!; sleep 0.1; exit 7",
    ),
  ).toStrictEqual({ end: { kind: 'exit', code: 7 }, aliveAfter: false });
});

test("the window hears each monitor's end once, in the order they ended, a stop's at once; a /clear forgets them", () =>
  withAgent(async (conversation, events, dir) => {
    const commands = [fakeCommand(), fakeCommand(), fakeCommand()];

    for (const [index, description] of ['exits', 'agent', 'person'].entries()) {
      idOf(
        conversation.startMonitor(
          { command: 'cmd', description },
          dir,
          commands[index]!.run,
        ),
      );
    }

    const ended = () => {
      const last = events.findLast((event) => event.type === 'monitors');

      assert(last?.type === 'monitors');

      return last.ended.map(({ id, description, end }) => ({
        id,
        description,
        end,
      }));
    };

    commands[0]!.exit(3);
    await until(() => ended().length === 1);
    conversation.stopMonitor('m2');
    conversation.stopMonitor('m3', 'person');

    // The person's stop is ended before its run is gone, and only once.
    expect(ended()).toStrictEqual([
      { id: 'm1', description: 'exits', end: { kind: 'exit', code: 3 } },
      { id: 'm2', description: 'agent', end: { kind: 'stopped' } },
      { id: 'm3', description: 'person', end: { kind: 'stopped' } },
    ]);
    await until(() =>
      delivered(events).some(({ from }) => from.monitor?.id === 'm3'),
    );
    expect(ended().map(({ id }) => id)).toStrictEqual(['m1', 'm2', 'm3']);

    conversation.clear();
    await until(
      () => events.filter((event) => event.type === 'connected').length === 2,
    );
    idOf(
      conversation.startMonitor(
        { command: 'sleep 30', description: 'new' },
        dir,
      ),
    );
    expect(ended()).toStrictEqual([]);
  }));
