/**
 * Long-lived agents in the window, on the fake agent and chord's own server:
 * opened under the prompt, picked, written to, messaged both ways, their
 * exits, failures and marks, and the keys a click takes back.
 */
import { describe, expect, setSystemTime, test } from 'bun:test';
import { readFile, readdir, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { serveChord } from '../../../src/server/server.ts';
import { fakeAgentCommand } from '../../fixtures/fake.ts';
import {
  CRASH_WORDS,
  GATE,
  GATE_RELEASE,
  HELD_AGAIN,
  HELD_MESSAGE,
  MAIN_MESSAGES,
} from '../../fixtures/fake_agent/scenarios/agents.ts';
import { TASK_REPORT } from '../../fixtures/fake_agent/scenarios/tasks.ts';
import {
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
import { count, opened, parserTaskAsks, withAgents } from './agents_window.tsx';

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
    // Once parser's turn, a fixed 3 s, has ended, however the task's ask
    // fell, it waits between turns for ctrl+x a, so '1' never races that
    // end (CHD-470).
    await window.shows('Agent(Fix the tokenizer) · fake asks · between turns');
    await leader(window, 'a');
    await window.shows('Esc to reject');
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
    // Behind, its row reads open and idle, the failed turn its mark beside
    // that (CHD-471), not that it is gone, and so does the status line.
    expect(window.frame()).toMatch(
      / {4}parser {2}fake.* {2}◦ idle \d+s +✗ turn failed$/m,
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

test("a child's message not yet seen, then its reply, are marks beside its state, whose idle time counts from its reply (CHD-364, CHD-471)", () =>
  withAgents(
    async (window) => {
      await ready(window);
      await send(window, 'agents');
      await window.shows('← new message');

      // Its reply held, chord's clock is put ten seconds past the message,
      // where it stays, and then the reply comes: an idle time counted
      // from the message would say ten seconds or more.
      try {
        setSystemTime(new Date(Date.now() + 10_000));
        await writeFile(join(window.dir, GATE, GATE_RELEASE), '');
        await until(
          'parser replied',
          () => /parser .*✓ new reply/.test(window.frame()),
          30_000,
        );

        const idle = /parser .*◦ idle (\d+)s +✓ new reply/.exec(window.frame());

        // The message came seconds before; it stopped as its reply came.
        expect(Number(idle?.[1])).toBeLessThanOrEqual(2);
      } finally {
        setSystemTime();
      }
    },
    '--steering',
    'codex',
    '--steer-late',
    '--hold-reply',
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
            await window.shows('← new message');
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
            await window.shows('← new message');
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

describe('CHD-364 tester: narrow idle time beside reply mark', () => {
  test('idle at 80x24 counts from the last reply beside its timeless mark', () =>
    withAgents(
      async (window) => {
        await window.resize({ columns: 80, rows: 24 });
        await ready(window);
        await send(window, 'agentsquiet');
        await window.shows('← new message');

        const age = () =>
          Number(
            /parser .*◦ idle (\d+)s +✓ new reply/.exec(window.frame())?.[1],
          );

        try {
          // The message is old, while the reply is released at the new time.
          setSystemTime(new Date(Date.now() + 10_000));
          await writeFile(join(window.dir, GATE, GATE_RELEASE), '');
          // agentsquiet sends parser no later messages, so this idle is final.
          await until('the narrow parser reply', () => Number.isFinite(age()));

          const first = age();

          expect(first).toBeLessThanOrEqual(2);
          setSystemTime(new Date(Date.now() + 2000));
          await until(
            'idle age advances beside the reply mark',
            () => age() > first,
          );
          expect(age()).toBe(first + 2);
          expect(age()).toBeLessThan(10);
        } finally {
          setSystemTime();
        }
      },
      '--steering',
      'codex',
      '--steer-late',
      '--hold-reply',
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
