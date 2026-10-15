/**
 * Long-lived agents in the window, on the fake agent and chord's own server:
 * opened under the prompt, picked, written to, messaged both ways and
 * closed.
 */
import { expect, setSystemTime, test } from 'bun:test';
import { readFile, readdir, writeFile } from 'node:fs/promises';
import { serveChord } from '../../../src/server/server.ts';
import { fakeAgentCommand } from '../../fixtures/fake.ts';
import {
  CHILD_MESSAGES,
  CRASH_WORDS,
  DOCS_MESSAGE,
  MAIN_MESSAGES,
} from '../../fixtures/fake_agent/scenarios/agents.ts';
import { TASK_REPORT } from '../../fixtures/fake_agent/scenarios/tasks.ts';
import {
  CTRL_X,
  DOWN,
  ESC,
  leader,
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
    expect(frame).toContain('→ @parser');
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
    expect(window.frame()).toContain('→ @main');
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
    await window.shows('● parser needs your permission');
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
    await window.shows('● parser needs your permission');
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
    expect(window.frame()).toContain('→ @parser');
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
    await window.shows('❯ 1. just now  open in 1  parser · agentchild');
    await window.press('\r');
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
