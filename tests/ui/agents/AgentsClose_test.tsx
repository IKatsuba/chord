/**
 * Long-lived agents closed, cleared and resumed in the window: the attention
 * key, held messages, a parent's close, records and `/resume`.
 */
import { describe, expect, setSystemTime, test } from 'bun:test';
import { pickAgent, readyAgent } from '../app/child_window.tsx';
import assert from 'node:assert/strict';
import { mkdir, readFile, readdir, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { serveChord } from '../../../src/server/server.ts';
import { fakeAgentCommand } from '../../fixtures/fake.ts';
import {
  CHILD_MESSAGES,
  DOCS_MESSAGE,
  GATE,
  GATE_RELEASE,
  HELD_AGAIN,
  HELD_MESSAGE,
  MAIN_MESSAGES,
} from '../../fixtures/fake_agent/scenarios/agents.ts';
import {
  DOWN,
  leader,
  ready,
  send,
  until,
  UP,
  type Window,
  withWindow,
} from '../app/render.tsx';
import { count, opened, withAgents } from './agents_window.tsx';

test('ctrl+x a picks the child that waits, and its permission box opens there', () =>
  withAgents(async (window) => {
    await opened(window);
    await window.shows('● docs needs your permission · ctrl+x a');
    expect(!window.frame().includes('Write notes.txt')).toBeTruthy();
    await leader(window, 'a');
    await window.shows('docs asks');
    await window.shows('╭─ docs ─');
    await window.press('1');
    await window.shows('Permission: allow.');
  }));

test("a queued message's row keeps its header whole on a narrow window and cuts only its text", async () => {
  const server = serveChord();

  try {
    await withWindow(
      async (window) => {
        await ready(window);
        // The message goes once chord shows docs asking, so chord holds it for
        // the answer however slow docs started (CHD-399).
        await send(window, 'agentsheldgated');
        await window.shows('● docs needs your permission');
        await mkdir(join(window.dir, GATE), { recursive: true });
        await writeFile(join(window.dir, GATE, GATE_RELEASE), '');
        await leader(window, 'a');
        await window.shows('docs asks');
        await window.shows('← from @main · after your answer: ');

        const row = window
          .frame()
          .split('\n')
          .find((line) => line.includes('after your answer'))!;

        // The text, not the header, gives way to the width.
        expect(row).toContain('...');
        expect(row).not.toContain(DOCS_MESSAGE);
      },
      {
        agentCommand: fakeAgentCommand(undefined, '--steering', 'claude'),
        server,
        runtimes: ['fake'],
        rows: 40,
        columns: 60,
      },
    );
  } finally {
    await server.close();
  }
});

test("a message held behind the child's running call waits in its queue until it goes in, then the row is gone", async () => {
  const server = serveChord();

  try {
    await withWindow(
      async (window) => {
        await ready(window);
        // The child's call stays open until the test releases it.
        await send(window, 'agentcallgated');
        await window.shows('Open(parser)');
        await window.press(DOWN);
        await window.press(DOWN);
        await window.shows('╭─ parser ─');
        await window.shows(
          `← from @main · after the running calls: ${HELD_AGAIN}`,
        );
        expect(window.frame()).toContain(
          `← from @main · after the running calls: ${HELD_MESSAGE}`,
        );
        // Not in the turn yet: its call still runs.
        expect(window.frame()).toContain('Running…');
        await writeFile(join(window.dir, GATE, GATE_RELEASE), '');
        await window.shows('The tests pass.');
        // The answer can draw before the held steers have been accepted.
        await window.shows(`← from @main\n   ⎿  ${HELD_MESSAGE}`);
        await window.shows(`← from @main\n   ⎿  ${HELD_AGAIN}`);

        const frame = window.frame();

        expect(frame).toContain(`← from @main\n   ⎿  ${HELD_MESSAGE}`);
        expect(frame).toContain(`← from @main\n   ⎿  ${HELD_AGAIN}`);
        expect(frame).not.toContain('after the running calls');
      },
      {
        agentCommand: fakeAgentCommand(undefined, '--steering', 'claude'),
        server,
        runtimes: ['fake'],
        rows: 40,
        columns: 120,
      },
    );
  } finally {
    await server.close();
  }
});

test('/clear with a child picked clears it, main told, and on main it closes the children with the session (CHD-476)', () =>
  withAgents(async (window) => {
    await opened(window);
    await window.press(DOWN);
    await window.press(DOWN);
    await window.press('\r');
    await window.shows('╭─ parser ');
    await window.shows('I will run the parser tests on each change.');
    await send(window, '/clear');
    // Its view starts over under its header; it stays picked and listed.
    await until(
      "parser's view empty",
      () =>
        !window.frame().includes('I will run the parser tests on each change.'),
    );

    expect(window.frame()).toContain('╭─ parser ');
    expect(window.frame()).toContain('opened by main');
    await window.press(DOWN);
    await window.press(UP);
    await window.press(UP);
    // Main, its parent, was told.
    await window.shows('The person cleared parser');
    // The transcript empties, the command with it.
    await window.type('/clear');
    await window.press('\r');
    await until('the list gone', () => !window.frame().includes('    parser'));
    expect(!window.frame().includes('Waiting on parser.')).toBeTruthy();
  }));

/**
 * Drops each prompt line's `from`, as a record written before it was kept
 * has none, so only the wrapper and the served answers say who sent it.
 */
async function forgetSenders(dir: string) {
  const records = `${dir}/state/records`;

  for (const file of await readdir(records, { withFileTypes: true })) {
    const path = `${records}/${file.name}`;
    const lines = (await readFile(path, 'utf8')).split('\n').map((line) => {
      if (line === '') {
        return line;
      }

      const { from: _, ...entry } = JSON.parse(line);

      return JSON.stringify(entry);
    });

    await writeFile(path, lines.join('\n'));
  }
}

/** The closing note of a parent left with parser and docs open. */
const LEFT_OPEN =
  'parser (fake) and docs (fake) were open when this session was left and ' +
  'are not reopened · /resume lists them';

/**
 * Leaves a parent with parser and docs open for a new session with
 * `/clear`, which closes them, and opens it again from `/resume`.
 */
async function leftAndResumed(window: Window, legacy = false): Promise<void> {
  await opened(window);
  // Played as turns, which the record keeps; a queued one it does not.
  await until(
    'both messages answered',
    () => count(window, 'Received the message from parser · fake.') === 2,
  );
  await window.shows('● docs needs your permission');
  await send(window, '/clear');
  await until('the list gone', () => !window.frame().includes('    parser'));
  await ready(window);

  if (legacy) {
    await forgetSenders(window.dir);
  }

  await window.type('/resume');
  await window.press('\r');
  await window.shows('just now  agents');

  // Ordered by the last write, which the children's turns may have made.
  while (!/❯ \d\. just now {2}agents/.test(window.frame())) {
    await window.press(DOWN);
  }

  await window.press('\r');
}

/**
 * On `--resume-only`, as Claude's adapter is, a session resumed is drawn
 * from chord's record rather than the agent's replay; `legacy` resumes it as
 * a record kept before senders were.
 */
const resumedFromRecord = (legacy: boolean) => () =>
  withAgents(async (window) => {
    await leftAndResumed(window, legacy);
    // Both of parser's messages, read back from the record, not sent again.
    await window.shows(CHILD_MESSAGES[1]);
    expect(window.frame()).toContain('→ to @parser');
    expect(count(window, '← from @parser · fake')).toStrictEqual(2);
    expect(!window.frame().includes('← from parser')).toBeTruthy();
    await window.shows(LEFT_OPEN);
    // Not reopened: no list under the prompt.
    expect(!window.frame().includes('    main    fake')).toBeTruthy();
  }, '--resume-only');

test('a parent the agent loads is drawn from its record, naming the children left open, and a message to one is refused', () =>
  withAgents(async (window) => {
    await leftAndResumed(window);
    await window.shows(LEFT_OPEN);
    expect(count(window, '← from @parser · fake')).toStrictEqual(2);
    expect(!window.frame().includes('Read(README.md)')).toBeTruthy();

    // The window closed parser with the session /clear let go, so it
    // says so before the record would.
    await send(window, 'agentclose');
    await window.shows('Are you still there?');
    await window.shows('parser is closed, so I will run the tests myself.');
    expect(!window.frame().includes('    main    fake')).toBeTruthy();
  }));

test(
  'a closed parent resumed from its record draws its child as @parser both ways',
  resumedFromRecord(false),
);

test(
  'a record kept before senders were draws the child open_agent opened as @parser',
  resumedFromRecord(true),
);

test('/resume marks a live child open now, and picking it goes to it without a second agent', () =>
  withAgents(async (window) => {
    await opened(window);
    // /resume waits for main's turn, which ends once parser has answered.
    await until(
      'both messages answered',
      () => count(window, 'Received the message from parser · fake.') === 2,
    );
    await until('the turn to end', () => !window.frame().includes('Working'));

    const agents = window.pids.length;

    await window.type('/resume');
    await window.press('\r');
    await window.shows('Resume a session');
    await window.shows('just now  open now  parser · agentchild');

    // docs, open too, was last used about when parser was, so either can be
    // first; parser is picked by its number.
    const row = /(\d)\. just now {2}open now {2}parser · agentchild/.exec(
      window.frame(),
    );

    assert(row);
    await window.press(row[1]!);
    // parser picked, the same conversation the list names.
    await window.shows('parser · fake · Fake Small · opened by main');
    await window.shows('╭─ parser ─');
    await window.shows(MAIN_MESSAGES[1]);
    expect(!window.frame().includes('Resume a session')).toBeTruthy();
    // Give a second agent the time it would take to start, had one been.
    await new Promise((resolve) => setTimeout(resolve, 500));
    expect(window.pids.length).toStrictEqual(agents);
    expect(count(window, '    parser  fake')).toStrictEqual(1);
  }));

test("a picked child's opening line goes on aging with the TUI idle", () =>
  withAgents(async (window) => {
    await ready(window);
    await send(window, 'agenteffort');
    await window.shows('Started on high.');
    await window.press(DOWN);
    await window.press(DOWN);
    await window.shows('tuner · fake · Fake Small · opened by main');

    // A minute on, with no key and no message to redraw the window.
    setSystemTime(new Date(Date.now() + 60_000));

    try {
      await window.shows('tuner · fake · Fake Small · opened by main 1m ago');
    } finally {
      setSystemTime();
    }
  }));

describe('CHD-264 tester: failure surfaces in the window', () => {
  for (const [columns, rows] of [
    [80, 24],
    [120, 40],
  ] as const) {
    test(`failure idle age and independent child news survive attendance at ${columns}x${rows}`, async () => {
      const server = serveChord();
      const admit = server.admit.bind(server);
      let main: Parameters<typeof admit>[0] | undefined;

      server.admit = (caller) => {
        if (caller.role === 'person') {
          main = caller;
        }

        return admit(caller);
      };

      try {
        await withWindow(
          async (window) => {
            await readyAgent(window);
            assert(main);
            await main.window.open(main.key, {
              agent: 'fake',
              name: 'parser',
              prompt: 'error',
            });
            await window.shows("✗ parser's turn failed · ctrl+x a");

            const failedRow = () =>
              window
                .frame()
                .split('\n')
                .find((line) => /^ {4}parser {2}fake/.test(line));
            const age = () =>
              Number(/◦ idle (\d+)s/.exec(failedRow() ?? '')?.[1]);
            const first = age();

            expect(Number.isFinite(first)).toBe(true);
            await until(
              'idle time advances beside the timeless failure mark',
              () => age() > first,
            );
            expect(failedRow()).toMatch(/◦ idle \d+s +✗ turn failed$/);
            await main.window.open(main.key, {
              agent: 'fake',
              name: 'other',
              prompt: 'crash',
            });
            await window.shows('✗ 1 exited · 1 turn failed · ctrl+x a');
            expect(window.frame()).not.toContain('sessions ended');
            await leader(window, 'a');
            await window.shows('╭─ parser ');
            await window.shows('✗ other exited · ctrl+x a');
            await send(window, 'text');
            await window.shows('came in chunks');
            await pickAgent(window, 'main');
            await leader(window, 'a');
            await window.shows('╭─ other ');
            expect(window.frame()).toMatch(/^ {4}other .*✗ exited$/m);
            await pickAgent(window, 'main');
            await pickAgent(window, 'other');
            expect(window.frame()).toMatch(/^ {4}other .*✗ exited$/m);
            expect(window.frame()).not.toContain('✗ other exited · ctrl+x a');
          },
          { server, runtimes: ['fake'], columns, rows },
        );
      } finally {
        await server.close();
      }
    });
  }
});
