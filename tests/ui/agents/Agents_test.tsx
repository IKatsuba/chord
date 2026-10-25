/**
 * Long-lived agents in the window, on the fake agent and chord's own server:
 * opened under the prompt, picked, written to, messaged both ways, their
 * exits, failures and marks.
 */
import { describe, expect, setSystemTime, test } from 'bun:test';
import { readFile, readdir, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { serveChord } from '../../../src/server/server.ts';
import { readRecords } from '../../../src/session/sessions.ts';
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
  ready,
  send,
  until,
  UP,
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

test("a child of a session left by /clear and picked again in /resume is refused in its record's words (Q184)", () =>
  withAgents(async (window) => {
    await opened(window);

    const first = window.session()?.id;

    await send(window, '/clear');
    await until('a new session', () => window.session()?.id !== first);
    await ready(window);
    await send(window, '/resume');
    await window.shows('Resume a session');

    // The children's sessions are listed too; main's is the one sent `agents`.
    for (let row = 0; !/❯ \d+\. .* {2}agents\s*│/.test(window.frame()); row++) {
      expect(row).toBeLessThan(3);
      await window.press(DOWN);
    }

    await window.press('\r');
    // Its transcript again, the child it opened in it.
    await window.shows('Open(parser) · fake · fake-small');
    await ready(window);
    await send(window, 'agentsendrefused');
    await window.shows(
      'parser was closed when this session was left; open_agent starts another',
    );
    expect(window.frame()).not.toContain('parser is closed;');
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
    await window.shows('main is the session · ctrl+d quits');

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

test("a child's exit while main is shown is named for the child", () =>
  withAgents(async (window) => {
    await ready(window);
    await send(window, 'agentexit');
    await window.shows('✗ parser exited · ctrl+x a to go');
    expect(!window.frame().includes('fake exited')).toBeTruthy();
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

describe('CHD-445 U1 tester: each fake child owns its title updates', () => {
  test('parser and docs record only their own titles, including both docs names', () =>
    withAgents(async (window) => {
      await ready(window);
      await send(window, 'agentstitled');
      await window.shows('Waiting on parser and docs.');

      let records: Awaited<ReturnType<typeof readRecords>> = [];
      let parser = '';
      let docs = '';

      await until('both children to record their titles', async () => {
        records = await readRecords(join(window.dir, 'state'));

        const parserRecord = records.find((record) => record.name === 'parser');
        const docsRecord = records.find((record) => record.name === 'docs');

        if (!parserRecord || !docsRecord) {
          return false;
        }

        [parser, docs] = await Promise.all([
          readFile(parserRecord.path, 'utf8'),
          readFile(docsRecord.path, 'utf8'),
        ]);

        return (
          parser.includes('"title":"Fix the tokenizer"') &&
          docs.includes('"title":"Fix the parser"')
        );
      });

      const main = records.find((record) => record.parent === undefined)!;
      const children = records.filter((record) => record.parent !== undefined);

      expect(children.map((record) => record.name).sort()).toEqual([
        'docs',
        'parser',
      ]);
      expect(new Set(records.map((record) => record.sessionId)).size).toBe(3);
      expect(children.every((record) => record.parent === main.sessionId)).toBe(
        true,
      );
      expect(parser).not.toContain('"title":"Look at the parser"');
      expect(parser).not.toContain('"title":"Fix the parser"');
      expect(docs).not.toContain('"title":"Fix the tokenizer"');
      expect(docs.indexOf('"title":"Look at the parser"')).toBeGreaterThan(0);
      expect(docs.indexOf('"title":"Fix the parser"')).toBeGreaterThan(
        docs.indexOf('"title":"Look at the parser"'),
      );
    }));
});

test('open_agent refuses quotes in supplied names and runtime fallbacks before starting (CHD-519)', () =>
  withAgents(async (window) => {
    await ready(window);
    await send(window, 'agentnames');
    await window.shows('Quoted agent names refused.');
    expect(
      count(window, 'An agent name must not contain the character "'),
    ).toBe(2);

    for (const code of ['000A', '000D', '0009', '0000', '007F']) {
      expect(window.frame()).toContain(
        `An agent name must not contain the control character U+${code}`,
      );
    }

    expect(window.pids).toHaveLength(1);
  }));
