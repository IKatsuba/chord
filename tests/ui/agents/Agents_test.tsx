/**
 * Long-lived agents in the window, on the fake agent and chord's own server:
 * opened under the prompt, picked, written to, messaged both ways and
 * closed.
 */
import { describe, expect, setSystemTime, test } from 'bun:test';
import assert from 'node:assert/strict';
import { readFile, readdir, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { serveChord } from '../../../src/server/server.ts';
import { readPast } from '../../../src/session/record.ts';
import { fakeAgentCommand } from '../../fixtures/fake.ts';
import {
  CHILD_MESSAGES,
  CRASH_WORDS,
  DOCS_MESSAGE,
  GATE,
  GATE_RELEASE,
  HELD_AGAIN,
  HELD_MESSAGE,
  MAIN_MESSAGES,
} from '../../fixtures/fake_agent/scenarios/agents.ts';
import { TASK_REPORT } from '../../fixtures/fake_agent/scenarios/tasks.ts';
import {
  CTRL_X,
  DOWN,
  ESC,
  leader,
  left,
  ready,
  send,
  until,
  UP,
  type Window,
  withWindow,
} from '../app/render.tsx';

/** How many times `text` is on screen. */
function count(window: Window, text: string): number {
  return window.frame().split(text).length - 1;
}

/**
 * Runs `body` in a window with chord's server, the fake its one runtime,
 * started with `flags`.
 */
async function withAgents(
  body: (window: Window) => Promise<void>,
  ...flags: string[]
) {
  const server = serveChord();

  try {
    await withWindow(body, {
      ...(flags.length === 0
        ? {}
        : { agentCommand: fakeAgentCommand(undefined, ...flags) }),
      server,
      runtimes: ['fake'],
      rows: 80,
      columns: 120,
    });
  } finally {
    await server.close();
  }
}

/**
 * The hint for parser's task asking, as CHD-431 names it: by the task's own
 * name, or by whose task it is where that does not fit.
 */
const PARSER_TASK =
  /● (Agent\(Fix the tokenizer\) · fake|parser's task) needs your permission/;

async function parserTaskAsks(window: Window): Promise<void> {
  await until("parser's task asks", () => PARSER_TASK.test(window.frame()));
}

/** `agents`, until both of parser's messages have come back. */
async function opened(window: Window): Promise<void> {
  await ready(window);
  await send(window, 'agents');
  await window.shows('Open(parser) · fake · fake-small');
  await window.shows('Waiting on parser.');
  await window.shows(CHILD_MESSAGES[1]);
}

test('a long-lived agent opens in the list under the prompt and trades two messages each way with its parent', () =>
  withAgents(async (window) => {
    await opened(window);
    await window.shows('Received the message from parser · fake.');
    await window.shows('    docs    fake');

    const frame = window.frame();

    // No tab of its own: one session has no strip.
    expect(!frame.includes(' 1 fake ')).toBeTruthy();
    expect(frame).toContain('    main    fake ·');
    expect(frame).toContain('    parser  fake · Fake Small');
    expect(frame).toContain('→ to @parser');
    expect(frame).toContain(MAIN_MESSAGES[0]);
    expect(count(window, '← from @parser · fake')).toStrictEqual(2);

    // ↓ into the list and ↓ again picks parser, whose chat fills the window.
    await window.press(DOWN);
    await window.shows('❯ main');
    await window.press(DOWN);
    await window.shows('parser · fake · Fake Small · opened by main');
    await window.shows('╭─ parser ─');
    await window.shows('← from @main');
    await window.shows(MAIN_MESSAGES[1]);
    expect(window.frame()).toContain('→ to @main');
    expect(!window.frame().includes('Waiting on parser.')).toBeTruthy();

    // Enter goes back to the box, and what is typed goes to parser.
    await window.press('\r');
    await send(window, '/echo straight to parser');
    await window.shows('straight to parser');

    // ↑ on main hands the keys back; main's chat never had the prompt.
    await window.press(DOWN);
    await window.press(UP);
    await window.shows('Waiting on parser.');
    expect(!window.frame().includes('straight to parser')).toBeTruthy();
    expect(!window.frame().includes('╭─ parser')).toBeTruthy();
  }));

test('an agent opened on an effort its runtime offers runs on it, and its call, its row and the answer say so', () =>
  withAgents(async (window) => {
    await ready(window);
    await send(window, 'agenteffort');
    await window.shows('Started on high.');
    await window.shows('    tuner  fake · Fake Small · high');
    expect(window.frame()).toContain('Open(tuner) · fake · fake-small · high');
    expect(window.frame()).toContain(
      '    main   fake · Fake Large with a 1M context window · medium',
    );
  }));

test("the status line names the shown agent's effort: main's, then the picked child's", () =>
  withAgents(async (window) => {
    await ready(window);
    await send(window, 'agenteffort');
    await window.shows('Started on high.');
    await window.shows(
      'Fake Large with a 1M context window · medium effort · 1% context used',
    );
    await window.press(DOWN);
    await window.press(DOWN);
    await window.shows('Fake Small · high effort · 1% context used');
  }));

test("an agent opened on an effort its runtime refuses runs on the runtime's own, and the answer says so", () =>
  withAgents(async (window) => {
    const refusal =
      'Could not start on max effort, asked by open_agent: the agent offers ' +
      'low, medium, high';

    await ready(window);
    await send(window, 'agentmaxeffort');
    await window.shows('Started on medium.');
    await window.shows('    tuner  fake · Fake Small · medium');
    expect(window.frame().replace(/\s+/g, ' ')).toContain(refusal);
    expect(window.frame()).toContain(
      'Open(tuner) · fake · fake-small · medium',
    );

    // The refusal is in the agent's own transcript too.
    await window.press(DOWN);
    await window.press(DOWN);
    await window.shows(refusal);
  }));

test('x closes the picked child, once more while it waits, and chord tells the parent', () =>
  withAgents(async (window) => {
    await opened(window);
    await window.shows('● docs needs your permission');
    await window.press(DOWN);
    await window.press(DOWN);
    await window.press(DOWN);
    await window.shows('docs asks');
    await window.press('x');
    await window.shows('docs waits for your permission · x again to stop it');
    await window.press('x');
    await window.shows('← from chord');
    await window.shows('The person closed docs (fake, id ');
    await window.shows('It takes no more messages; open_agent starts another.');
    await window.shows('Received the message from chord.');
    expect(!window.frame().includes('    docs ')).toBeTruthy();

    // On main, x closes nothing.
    await window.press('x');
    await window.shows('main is the session · ctrl+x k closes it');

    // close_agent from the parent sends no such message; a message after
    // it is refused.
    await window.press(ESC);
    await send(window, 'agentclose');
    await window.shows('Close(parser)');
    await window.shows('parser is closed; open_agent starts another');
    await window.shows('parser is closed, so I will run the tests myself.');
    expect(count(window, 'The person closed')).toStrictEqual(1);
    // The last child gone, the list goes with it.
    expect(!window.frame().includes('    main    fake')).toBeTruthy();
    // Both closed in the parent's own time, so a resume names neither.
    await until(
      'both closes recorded',
      async () => (await closedInRecords(window.dir)) === 2,
    );
  }));

test("a child starts a task agent of its own, drawn in the child's turn, which reports to the child", () =>
  withAgents(async (window) => {
    await ready(window);
    await send(window, 'agenttask');
    await window.shows('Waiting on parser.');
    await parserTaskAsks(window);
    // The task is the child's, so main's transcript never draws it.
    expect(!window.frame().includes('Agent(Fix the tokenizer)')).toBeTruthy();
    await leader(window, 'a');
    await window.shows('╭─ parser ─');
    await window.shows('Agent(Fix the tokenizer) · fake · fake-small');
    await window.shows('Agent(Fix the tokenizer) · fake asks');
    await window.press('1');
    await window.shows('← from Fix the tokenizer · fake · report');
    await window.shows('Done (5 tool uses');
    await window.shows(
      'Received the message from Fix the tokenizer · fake · report.',
    );
    expect(window.frame()).toContain(TASK_REPORT.slice(0, 40));
  }));

test('closing a child cancels the task agents it started', () =>
  withAgents(async (window) => {
    await ready(window);
    await send(window, 'agenttask');
    await parserTaskAsks(window);
    await window.press(DOWN);
    await window.press(DOWN);
    await window.shows('Agent(Fix the tokenizer) · fake asks');
    await window.press('x');
    await window.shows('x again to stop it');
    await window.press('x');
    await window.shows('The person closed parser (fake');
    await window.shows('Received the message from chord.');
    expect(!window.frame().includes('needs your permission')).toBeTruthy();
    expect(!window.frame().includes('Fix the tokenizer')).toBeTruthy();
  }));

test("a child's agent that exits tells the parent with a message from chord, its last words in it", () =>
  withAgents(async (window) => {
    await ready(window);
    await send(window, 'agentexit');
    await window.shows('Waiting on parser.');
    await window.shows('← from chord');
    await window.shows(
      `parser's agent exited: ${CRASH_WORDS}. open_agent opens it again.`,
    );
    // The message starts the parent's turn, as every message does.
    await window.shows('Received the message from chord.');
    expect(count(window, '← from chord')).toStrictEqual(1);
    // Behind, its row and the status line say the agent went, not its turn.
    expect(window.frame()).toMatch(/ {4}parser {2}fake.* {2}✗ exited$/m);
    await window.shows('✗ parser exited · ctrl+x a to go');
  }));

test("a child's turn that fails tells the parent, and the child stays open", () =>
  withAgents(async (window) => {
    await ready(window);
    await send(window, 'agentfail');
    await window.shows(
      "parser's turn failed: The fake agent failed on purpose. It is still " +
        'open; send_message reaches it.',
    );
    await window.shows('Received the message from chord.');
    expect(window.frame()).toContain('    parser  fake');
    // Behind, its row says its turn failed and since when, not that it is
    // gone, and so does the status line.
    expect(window.frame()).toMatch(
      / {4}parser {2}fake.* {2}✗ turn failed \d+s ago$/m,
    );
    await window.shows("✗ parser's turn failed · ctrl+x a to go");
    // Once looked at, the failed turn clears, and parser reads open and idle.
    await leader(window, 'a');
    await window.shows('╭─ parser ');
    await until(
      'the failed turn cleared',
      () => !window.frame().includes('turn failed'),
    );
  }));

test("a child's exit in a tab behind is named for the child, in that tab", () =>
  withAgents(async (window) => {
    await ready(window);
    await send(window, 'agentfail');
    await window.shows("✗ parser's turn failed · ctrl+x a to go");
    await leader(window, 'c');
    await window.shows(' 2 fake ');
    await ready(window);
    await send(window, 'agentexit');
    await window.shows('✗ 1 exited · 1 turn failed · ctrl+x a to go');
    // Back in tab 1, its failed turn seen: only tab 2's child is left.
    await leader(window, '1');
    await leader(window, 'a');
    await window.shows('╭─ parser ');
    await window.shows('✗ parser exited in 2 fake · ctrl+x a to go');
    expect(!window.frame().includes('2 fake exited')).toBeTruthy();
  }));

test("a child's reply to a message reads its age from the reply, not from the message (CHD-364)", () =>
  withAgents(
    async (window) => {
      await ready(window);
      await send(window, 'agents');
      await window.shows('← message from @main');
      await until(
        'parser replied',
        () => /parser .*✓ replied/.test(window.frame()),
        30_000,
      );

      const age = /parser .*✓ replied (\d+)s ago/.exec(window.frame());

      // The message came seconds before; the reply has only just come.
      expect(Number(age?.[1])).toBeLessThanOrEqual(2);
    },
    '--steering',
    'codex',
    '--steer-late',
    // Slow enough that the reply comes seconds after the message.
    '--step-ms',
    '30',
  ));

/** A left click on the prompt box's text row, as a terminal reports one. */
async function clickBox(window: Window): Promise<void> {
  const y = window
    .frame()
    .split('\n')
    .findLastIndex((line) => line.startsWith('│ ›'));

  expect(y).toBeGreaterThan(0);
  await window.press(left(10, y, 'down'));
  await window.press(left(10, y, 'up'));
}

test("a click on the box takes the keys back from the list: the ❯ goes, the child picked stays the box's, and typing goes in in order (CHD-384)", () =>
  withAgents(async (window) => {
    await ready(window);
    await send(window, 'agents');
    await window.shows('Waiting on parser.');
    await window.press(DOWN);
    await window.press(DOWN);
    await window.shows('❯ parser ');
    await clickBox(window);
    await until('the ❯ gone', () => !window.frame().includes('❯ parser '));
    await window.type('abc');
    await window.type('def');
    await window.shows('│ › abcdef');
    // Still parser's box, and the list's hint gone from the status line.
    expect(window.frame()).toContain('╭─ parser ');
    expect(!window.frame().includes('↑ ↓ to pick')).toBeTruthy();
    // ↓ is the box's again: it stays in the draft, not in the list.
    await window.press(DOWN);
    expect(!window.frame().includes('❯ ')).toBeTruthy();
  }));

test('a click on the box takes the keys back from the summary line too (CHD-384)', () =>
  withAgents(async (window) => {
    await ready(window);
    await send(window, 'monitors');
    await window.shows('    background  2 monitors running');
    await window.press(DOWN);
    await window.shows('❯ background');
    await clickBox(window);
    await until('the ❯ gone', () => !window.frame().includes('❯ background'));
    await window.type('abc');
    await window.type('def');
    await window.shows('│ › abcdef');
    // Enter is the box's: it sends the draft, not opening the view.
    await window.press('\r');
    await window.shows('› abcdef');
    expect(!window.frame().includes(' Background · ')).toBeTruthy();
  }));

/** How many `closed` lines the records in `dir`'s state hold. */
async function closedInRecords(dir: string): Promise<number> {
  const records = `${dir}/state/records`;
  let closed = 0;

  for (const file of await readdir(records, { withFileTypes: true })) {
    const text = await readFile(`${records}/${file.name}`, 'utf8');

    closed += text
      .split('\n')
      .filter((line) => line.startsWith('{"type":"closed"')).length;
  }

  return closed;
}

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
        await send(window, 'agentsheld');
        await window.shows('● docs needs your permission');
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

test('/clear with a child picked is refused, and on main it closes the children with the session', () =>
  withAgents(async (window) => {
    await opened(window);
    await window.press(DOWN);
    await window.press(DOWN);
    await window.press('\r');
    await send(window, '/clear');
    await window.shows('/clear clears main; pick main first');
    await window.press(DOWN);
    await window.press(UP);
    await window.press(UP);
    // The transcript empties, the command with it.
    await window.type('/clear');
    await window.press('\r');
    await until('the list gone', () => !window.frame().includes('    parser'));
    expect(!window.frame().includes('Waiting on parser.')).toBeTruthy();
  }));

test('closing a parent closes its children, asking first while one waits', () =>
  withAgents(async (window) => {
    await opened(window);
    await window.shows('● docs needs your permission');
    await leader(window, 'c');
    await window.shows(' 2 fake ');
    await leader(window, '1');
    await window.shows('    parser  fake');
    await leader(window, 'k');
    await window.shows('1 fake waits for your permission · ctrl+x k again');
    await window.press(CTRL_X);
    await window.press('k');
    await window.shows('Closed 1 fake and its 2 agents · /resume opens them');
    expect(!window.frame().includes('    parser')).toBeTruthy();
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
 * Leaves a parent with parser and docs open, closing its tab, and opens it
 * again from `/resume`.
 */
async function leftAndResumed(window: Window, legacy = false): Promise<void> {
  await opened(window);
  // Played as turns, which the record keeps; a queued one it does not.
  await until(
    'both messages answered',
    () => count(window, 'Received the message from parser · fake.') === 2,
  );
  await window.shows('● docs needs your permission');
  await leader(window, 'c');
  await window.shows(' 2 fake ');
  await ready(window);
  await leader(window, '1');
  await window.shows('    parser  fake');
  await leader(window, 'k');
  await window.press(CTRL_X);
  await window.press('k');
  await window.shows('Closed 1 fake and its 2 agents · /resume opens them');

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

    await send(window, 'agentclose');
    await window.shows(
      'parser was closed when this session was left; open_agent starts ' +
        'another',
    );
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

test('/resume marks a live child open in its tab, and picking it goes there without a second agent', () =>
  withAgents(async (window) => {
    await opened(window);
    await leader(window, 'c');
    await window.shows(' 2 fake ');
    await ready(window);

    const agents = window.pids.length;

    await window.type('/resume');
    await window.press('\r');
    await window.shows('Resume a session');
    await window.shows('just now  open in 1  parser · agentchild');

    // docs, open in tab 1 too, was last used about when parser was, so
    // either can be first; parser is picked by its number.
    const row = /(\d)\. just now {2}open in 1 {2}parser · agentchild/.exec(
      window.frame(),
    );

    assert(row);
    await window.press(row[1]!);
    // Tab 1 in front, on parser, the same conversation the list names.
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

describe('CHD-423 tester: two held messages on screen', () => {
  for (const [columns, rows] of [
    [120, 40],
    [80, 24],
  ] as const) {
    test(`the background marker and both foreground rows last until taken at ${columns}x${rows}`, async () => {
      const server = serveChord();

      try {
        await withWindow(
          async (window) => {
            await ready(window);
            await send(window, 'agentcallgated');
            await window.shows('← message from @main');
            expect(window.frame()).not.toContain('after the running calls');
            await window.press(DOWN);
            await window.press(DOWN);
            await window.shows('╭─ parser ─');
            await window.shows(
              `← from @main · after the running calls: ${HELD_AGAIN}`,
            );

            const held = window.frame();

            expect(held).toContain(
              `← from @main · after the running calls: ${HELD_MESSAGE}`,
            );
            expect(held.indexOf(HELD_MESSAGE)).toBeLessThan(
              held.indexOf(HELD_AGAIN),
            );
            expect(held).toContain('Running…');
            await writeFile(join(window.dir, GATE, GATE_RELEASE), '');
            await window.shows('The tests pass.');
            await until(
              'held rows taken',
              () => !window.frame().includes('after the running calls'),
            );
            expect(window.frame()).toContain(HELD_AGAIN);
            expect(window.frame()).not.toContain('after your answer');
          },
          {
            server,
            runtimes: ['fake'],
            columns,
            rows,
            agentCommand: fakeAgentCommand(undefined, '--steering', 'claude'),
          },
        );
      } finally {
        await server.close();
      }
    });
  }

  for (const action of ['cancel', 'close'] as const) {
    test(`${action} cleans up a call whose release gate was never opened`, async () => {
      const server = serveChord();

      try {
        await withWindow(
          async (window) => {
            await ready(window);
            await send(window, 'agentcallgated');
            await window.shows('← message from @main');
            await window.press(DOWN);
            await window.press(DOWN);
            await window.shows(
              `← from @main · after the running calls: ${HELD_AGAIN}`,
            );
            expect(window.frame()).toContain('Running…');
            expect(window.pids.length >= 2).toBe(true);

            if (action === 'cancel') {
              await window.press('\r');
              await window.press(ESC);
              await window.shows('Interrupted');
              await until(
                'cancelled hold removed',
                () => !window.frame().includes('after the running calls'),
              );
            }

            expect(await readdir(join(window.dir, GATE))).not.toContain(
              GATE_RELEASE,
            );
            // withWindow closes the parent and child and proves their PIDs gone.
          },
          {
            server,
            runtimes: ['fake'],
            columns: 80,
            rows: 24,
            agentCommand: fakeAgentCommand(undefined, '--steering', 'claude'),
          },
        );
      } finally {
        await server.close();
      }
    });
  }
});

describe('CHD-264 tester: failure surfaces in the window', () => {
  async function anotherTab(window: Window) {
    const opened = window.pids.length;

    await leader(window, 'c');
    // A failure notice can replace the ready hint at a narrow width.
    await until(
      'the new fake session connected',
      () => window.pids.length > opened,
    );
  }

  for (const [columns, rows] of [
    [80, 24],
    [120, 40],
  ] as const) {
    test(`failure ages, mixed notices and picker owners stay correct at ${columns}x${rows}; seeing each child clears only its news`, () =>
      withAgents(async (window) => {
        await window.resize({ columns, rows });
        await ready(window);
        await send(window, 'agentfail');
        await window.shows("✗ parser's turn failed · ctrl+x a");

        const failedRow = () =>
          window
            .frame()
            .split('\n')
            .find((line) => /^ {4}parser {2}fake/.test(line));
        const age = () =>
          Number(/turn failed (\d+)s ago/.exec(failedRow() ?? '')?.[1]);
        const first = age();

        expect(Number.isFinite(first)).toBe(true);
        await until('failed-turn age advances', () => age() > first);
        expect(failedRow()).toMatch(/✗ turn failed \d+s ago/);
        await anotherTab(window);
        await send(window, 'agentexit');
        await window.shows('✗ 1 exited · 1 turn failed · ctrl+x a');
        await anotherTab(window);
        await leader(window, 'w');
        await window.shows('✗ parser: turn failed');
        await window.shows('✗ parser: exited');
        expect(window.frame()).not.toContain('sessions ended');
        await window.press(ESC);
        await leader(window, 'a');
        await window.shows('╭─ parser ');
        await until('only exited child remains unseen', () =>
          window.frame().includes('✗ parser exited in 2 fake · ctrl+x a'),
        );
        expect(window.frame()).not.toMatch(/^ {4}parser .*turn failed/m);
        await send(window, 'text');
        await window.shows('came in chunks');
        await leader(window, '2');
        await leader(window, 'a');
        await window.shows('╭─ parser ');
        expect(window.frame()).toMatch(/^ {4}parser .*✗ exited$/m);
        await leader(window, '1');
        await leader(window, '2');
        expect(window.frame()).toMatch(/^ {4}parser .*✗ exited$/m);
        expect(window.frame()).not.toContain('✗ parser exited in 2 fake');
      }));
  }
});

describe('CHD-364 tester: narrow reply age', () => {
  test('the first reply at 80x24 starts fresh and then ages from the reply', () =>
    withAgents(
      async (window) => {
        await window.resize({ columns: 80, rows: 24 });
        await ready(window);
        await send(window, 'agents');
        await window.shows('← message from @main');

        const age = () =>
          Number(/parser .*✓ replied (\d+)s ago/.exec(window.frame())?.[1]);

        await until(
          'the narrow parser reply',
          () => Number.isFinite(age()),
          30_000,
        );

        const first = age();

        expect(first).toBeLessThanOrEqual(2);
        await until('reply age advances', () => age() > first);
        expect(age()).toBeLessThan(10);
      },
      '--steering',
      'codex',
      '--steer-late',
      '--step-ms',
      '30',
    ));
});

describe('CHD-384 tester: click focus and neighboring dialogs', () => {
  for (const columns of [80, 120]) {
    for (const target of ['child', 'summary'] as const) {
      test(`clicking from ${target} focus at ${columns} columns restores cursor edits and keyboard list navigation`, () =>
        withAgents(async (window) => {
          await window.resize({ columns, rows: columns === 80 ? 24 : 40 });
          await ready(window);
          await send(window, target === 'child' ? 'monitorchild' : 'monitors');
          await window.shows('background  2 monitors running');
          await window.press(DOWN);

          if (target === 'child') {
            await window.press(DOWN);
            await window.shows('❯ parser ');
          } else {
            await window.shows('❯ background');
          }

          await clickBox(window);
          await until(
            'list highlight released by click',
            () =>
              !window
                .frame()
                .includes(target === 'child' ? '❯ parser ' : '❯ background'),
          );
          await window.type('abc');
          await window.type('def');
          await window.shows('│ › abcdef');
          await window.press('\x1b[D');
          await window.press('\x1b[D');
          await window.type('XY');
          await window.shows('│ › abcdXYef');
          await window.press('\x7f');
          await window.shows('│ › abcdXef');
          expect(window.frame()).not.toContain('↑ ↓ pick');
          expect(window.frame()).not.toContain('↑ ↓ to pick');

          if (target === 'child') {
            expect(window.frame()).toContain('╭─ parser ');
          }

          await window.press('\x03');
          await window.press(DOWN);
          await window.shows(target === 'child' ? '❯ parser ' : '❯ background');
          await window.press(ESC);
          await until(
            'keyboard exit releases list',
            () =>
              !window
                .frame()
                .includes(target === 'child' ? '❯ parser ' : '❯ background'),
          );
          await window.type('ghi');
          await window.shows('│ › ghi');
        }));
    }
  }

  test('a click while the sessions picker is open preserves the picker and picked child; Esc returns ordinary typing', () =>
    withAgents(async (window) => {
      await window.resize({ columns: 120, rows: 40 });
      await ready(window);
      await send(window, 'monitorchild');
      await window.shows('background  2 monitors running');
      await window.press(DOWN);
      await window.press(DOWN);
      await window.shows('❯ parser ');
      await leader(window, 'w');
      await window.shows('Enter to go');
      await clickBox(window);
      expect(window.frame()).toContain('Enter to go');
      await window.press(ESC);
      await until(
        'the picker closes',
        () => !window.frame().includes('Enter to go'),
      );
      expect(window.frame()).toContain('╭─ parser ');
      expect(window.frame()).not.toContain('❯ parser ');
      await window.type('abc');
      await window.type('def');
      await window.shows('│ › abcdef');
    }));

  test('a click releases a selected asking child to its permission box without answering it at 80x24', () =>
    withAgents(async (window) => {
      await window.resize({ columns: 80, rows: 24 });
      await ready(window);
      await send(window, 'agents');
      await window.shows('Waiting on parser.');
      await window.press(DOWN);
      await window.press(DOWN);
      await window.press(DOWN);
      await window.shows('❯ docs ');
      await window.shows('Do you want to proceed?');
      await clickBox(window);
      await until(
        'docs list highlight released',
        () => !window.frame().includes('❯ docs '),
      );
      expect(window.frame()).toContain('Do you want to proceed?');
      expect(window.frame()).not.toContain('Permission: allow.');
      await window.press('1');
      await window.shows('Permission: allow.');
      expect(window.frame()).toContain('╭─ docs ');
    }));
});

test("a child's task permission keeps its mark and ctrl+x a once the child's turn has ended (CHD-266)", () =>
  withAgents(async (window) => {
    await ready(window);
    await send(window, 'agenttask');
    await parserTaskAsks(window);
    // parser's own turn ends about 3 s after it starts; its task still asks.
    await new Promise((resolve) => setTimeout(resolve, 4500));
    expect(window.frame()).toMatch(PARSER_TASK);
    expect(window.frame()).not.toContain('parser replied');
    await leader(window, 'a');
    await window.shows('╭─ parser ─');
    // Asked in a turn that has ended: it waits between turns.
    await window.shows('Agent(Fix the tokenizer) · fake asks · between turns');
    expect(window.frame()).toMatch(/parser .*● permission/);
    await leader(window, 'a');
    await window.shows('Esc to reject');
    await window.press('1');
    await window.shows('← from Fix the tokenizer · fake · report');
    expect(window.frame()).not.toMatch(/parser .*● permission/);
  }));

describe('CHD-266 tester: attention after an observed parent result', () => {
  async function taskAsks(window: Window, job: 'task' | 'taskask' = 'task') {
    const hint =
      job === 'task'
        ? /● (Agent\(Fix the tokenizer\) · fake|parser's task) needs your permission/
        : /● (Agent\(Ask the person\) · fake|parser's task) asks for input/;

    await until("parser's task hint", () => hint.test(window.frame()));

    return hint;
  }

  async function parserResult(dir: string): Promise<boolean> {
    const records = join(dir, 'state', 'records');

    for (const file of await readdir(records)) {
      const past = await readPast(join(records, file));
      const own = past.find((entry) => entry.type === 'session');

      if (own?.type !== 'session' || own.name !== 'parser') {
        continue;
      }

      const prompt = past.find((entry) => entry.type === 'prompt');

      if (
        prompt?.type === 'prompt' &&
        past.some(
          (entry) => entry.type === 'result' && entry.turnId === prompt.turnId,
        )
      ) {
        return true;
      }
    }

    return false;
  }

  for (const [columns, rows] of [
    [80, 24],
    [120, 40],
  ] as const) {
    for (const job of ['task', 'taskask'] as const) {
      test(`${job}: attention reaches the pending task after parser's recorded result at ${columns} columns`, async () => {
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
              await ready(window);
              assert(main);
              await main.window.open(main.key, {
                agent: 'fake',
                model: 'fake-small',
                name: 'parser',
                prompt: job,
              });

              const hint = await taskAsks(window, job);

              await until('parser’s spawning turn result in its record', () =>
                parserResult(window.dir),
              );
              expect(window.frame()).toMatch(hint);
              expect(window.frame()).not.toContain('parser replied');
              await leader(window, 'a');
              await window.shows('╭─ parser ─');
              await window.shows('between turns');
              await leader(window, 'a');

              if (job === 'task') {
                await window.shows('Esc to reject');
                await window.press('1');
                await window.shows('← from Fix the tokenizer · fake · report');
              } else {
                await window.shows('Esc to cancel');
                await window.press(ESC);
                await window.shows('← from Ask the person · fake · report');
              }

              expect(window.frame()).not.toMatch(
                /parser .*● (permission|input)/,
              );
            },
            { server, runtimes: ['fake'], columns, rows },
          );
        } finally {
          await server.close();
        }
      });
    }
  }

  test('clear removes an unanswered task mark and a later child request asks again', () =>
    withAgents(async (window) => {
      await ready(window);
      await send(window, 'agenttask');
      await taskAsks(window);
      await until('the first parser result', () => parserResult(window.dir));
      await send(window, '/clear');
      await until(
        'the old parser and its attention to leave',
        () =>
          !window.frame().includes('    parser') &&
          !window.frame().includes('needs your permission'),
      );
      // Clear drops the old child before the new session is ready for Enter.
      await ready(window);
      await send(window, 'agenttask');
      await taskAsks(window);
      await leader(window, 'a');
      await window.shows('Agent(Fix the tokenizer) · fake asks');
    }));
});

describe('who a box that asks names (CHD-389)', () => {
  test('a picked child is named in its question, form and link boxes, not its runtime', () =>
    withAgents(async (window) => {
      await opened(window);
      await window.press(DOWN);
      await window.press(DOWN);
      // Enter takes the keys from the list back to parser's prompt.
      await window.press('\r');
      await window.shows('╭─ parser ─');

      for (const [prompt, heading] of [
        ['askclaude', 'parser asks you 2 questions'],
        ['form', 'parser asks for input'],
        ['link', 'parser asks you to open a link'],
      ] as const) {
        await send(window, prompt);
        await window.shows(heading);
        expect(window.frame()).not.toContain(`fake ${heading.slice(7)}`);
        await window.press(ESC);
        await window.shows('Elicitation answer: cancel');
      }
    }));
});

describe('CHD-431 tester: task input and permission in different children', () => {
  for (const [columns, rows] of [
    [80, 24],
    [120, 40],
  ] as const) {
    test(`settling the older task input changes the count to the remaining task's name at ${columns} columns`, async () => {
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
            await ready(window);
            assert(main);
            await main.window.open(main.key, {
              agent: 'fake',
              name: 'questions',
              prompt: 'taskask',
            });
            await until('the first task input hint', () =>
              /● (Agent\(Ask the person\) · fake|questions's task) asks for input/.test(
                window.frame(),
              ),
            );
            await main.window.open(main.key, {
              agent: 'fake',
              name: 'parser',
              prompt: 'task',
            });
            await window.shows('● 2 agents wait');
            await leader(window, 'a');
            await window.shows('╭─ questions ─');
            await window.shows('between turns');
            await leader(window, 'a');
            await window.shows('Esc to cancel');
            await window.press(ESC);
            await until('the remaining task permission hint', () =>
              /● (Agent\(Fix the tokenizer\) · fake|parser's task) needs your permission/.test(
                window.frame(),
              ),
            );
            expect(window.frame()).not.toContain('● 2 agents wait');
            expect(window.frame()).not.toMatch(
              /● (Agent\(Ask the person\) · fake|questions's task) asks for input/,
            );
          },
          { server, runtimes: ['fake'], columns, rows },
        );
      } finally {
        await server.close();
      }
    });
  }
});

describe('CHD-405 tester: reports follow the picked runtime', () => {
  async function report(window: Window, command: string, expected: RegExp) {
    const latest = () => {
      const lines = window.frame().split('\n');
      const at = lines.findLastIndex((line) => line.includes(`› ${command}`));

      return at < 0 ? '' : lines.slice(at + 1).join('\n');
    };

    await send(window, command);
    await until(`the latest ${command} report`, () => expected.test(latest()));

    return latest();
  }

  async function childFinished(dir: string) {
    const records = join(dir, 'state', 'records');
    let files: string[];

    try {
      files = await readdir(records);
    } catch (error) {
      if (
        error instanceof Error &&
        'code' in error &&
        error.code === 'ENOENT'
      ) {
        return false;
      }

      throw error;
    }

    for (const file of files) {
      const past = await readPast(join(dir, 'state', 'records', file));
      const session = past.find((entry) => entry.type === 'session');

      if (
        session?.type === 'session' &&
        session.name === 'foreign' &&
        past.some((entry) => entry.type === 'result')
      ) {
        return true;
      }
    }

    return false;
  }

  for (const [columns, rows] of [
    [80, 24],
    [120, 40],
  ] as const) {
    for (const usage of ['missing', 'tokens', 'values'] as const) {
      test(`a standalone child, main and another tab keep their own report runtime with ${usage} usage at ${columns} columns`, async () => {
        const server = serveChord();
        const admit = server.admit.bind(server);
        let main: Parameters<typeof admit>[0] | undefined;
        const command = fakeAgentCommand(
          undefined,
          ...(usage === 'missing'
            ? ['--no-usage']
            : usage === 'tokens'
              ? ['--tokens-only']
              : []),
        );

        server.admit = (caller) => {
          if (caller.role === 'person') {
            main = caller;
          }

          return admit(caller);
        };

        try {
          await withWindow(
            async (window) => {
              await ready(window);
              assert(main);
              await main.window.open(main.key, {
                agent: 'codex',
                name: 'foreign',
                prompt: 'text',
              });
              await until("the child's actual recorded result", () =>
                childFinished(window.dir),
              );
              await window.press(DOWN);
              await window.press(DOWN);
              await window.press('\r');
              await window.shows('╭─ foreign ─');
              await report(window, '/status', /Agent: +codex/);

              const cost = await report(
                window,
                '/cost',
                usage === 'missing'
                  ? /codex has not reported what this session has used\./
                  : /Total cost:/,
              );

              if (usage === 'tokens') {
                expect(cost).toContain("(chord's estimate)");
                expect(cost).toMatch(/Tokens in: +1,000/);
              } else if (usage === 'values') {
                expect(cost).toContain('$0.0125');
                expect(cost).toMatch(/Tokens in: +1,000/);
              }

              await report(
                window,
                '/context',
                usage === 'missing'
                  ? /codex has not reported how full its context window is\./
                  : /Used: +/,
              );
              await window.press(DOWN);
              await window.press(UP);
              await window.press('\r');
              await report(window, '/status', /Agent: +fake/);
              await report(
                window,
                '/cost',
                /fake has not reported what this session has used\./,
              );
              await report(
                window,
                '/context',
                /fake has not reported how full its context window is\./,
              );
              await send(window, '/new other');
              await ready(window);
              await report(window, '/status', /Agent: +other/);
              await report(
                window,
                '/cost',
                /other has not reported what this session has used\./,
              );
              await leader(window, '1');
              await report(window, '/status', /Agent: +fake/);
              await window.press(DOWN);
              await window.press(DOWN);
              await window.press('\r');
              await window.shows('╭─ foreign ─');
              await report(window, '/status', /Agent: +codex/);
            },
            {
              server,
              columns,
              rows,
              runtimes: ['fake', 'codex', 'other'],
              agentCommand: command,
              startupOf: () => ({ agentCommand: command }),
            },
          );
        } finally {
          await server.close();
        }
      });
    }
  }
});
