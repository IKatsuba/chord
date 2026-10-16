import { describe, expect, test } from 'bun:test';
import { draw } from '../../harness.tsx';
import stripAnsi from 'strip-ansi';
import type { Subagent } from '../../../../src/session/transcript/types.ts';
import { Agents } from '../../../../src/ui/transcript/agents/Agents.tsx';
import {
  asked,
  CTRL_O,
  ESC,
  send,
  until,
  withWindow,
} from '../../app/render.tsx';

test("subagents draw under the turn: one group, a child's permission named, their endings, and one still running after it", () =>
  withWindow(
    async (window) => {
      await send(window, 'subagent');
      await window.shows('⏺ Running 2 agents… (ctrl+o to expand)');
      await asked(window);

      let frame = window.frame();

      expect(frame).toContain('Agent(Find the session layer) asks');
      expect(frame).toContain(
        '│  ⎿  Write(notes/routing.md) · waiting for permission',
      );
      await window.press('1');
      await window.shows('⏺ 2 agents ended · 1 failed (ctrl+o to expand)');
      await window.shows('1 agent still running');

      frame = window.frame();

      expect(frame).toContain(
        '├─ Agent(Find the session layer) · 5 tool uses · ',
      );
      expect(frame).toContain('│  ⎿  Done');
      expect(frame).toContain(
        '└─ Agent(Find where tool calls are drawn on screen and how they fold)',
      );
      expect(frame).toContain('   ⎿  Failed');
      // Spawned after the parent spoke, the third is a block of its own.
      expect(frame).toContain('⏺ Agent(Run the whole test suite)');
      // A child's words wait for ctrl+o; folded, they never read as the parent's.
      expect(
        !frame.includes('Could not read the component'),
        'a child spoke',
      ).toBeTruthy();
      await window.shows('⎿  Done (1 tool use · ');
      await until(
        'the status line to let the agent go',
        () => !window.frame().includes('still running'),
      );
      await window.press(CTRL_O);
      await window.shows('Find where chord hands each session/update');

      frame = window.frame();

      expect(frame).toContain('Could not read the component.');
      expect(frame).toContain('⎿  Error: File is too large to read whole.');
      // Two levels open; the grandchild stays folded.
      expect(frame).toContain('⏺ Agent(Read the transport tests)');
      expect(frame).toContain('⎿  Done (2 tool uses');
      expect(
        !frame.includes('Nothing it did not open'),
        'a grandchild opened',
      ).toBeTruthy();
      expect(
        !frame.includes('(ctrl+o to expand)'),
        'the open view names ctrl+o',
      ).toBeTruthy();
    },
    { rows: 80, columns: 120 },
  ));

test("Esc cancels a turn's subagents with it", () =>
  withWindow(
    async (window) => {
      await send(window, 'subagent');
      await window.shows('⏺ Running 2 agents…');
      await window.press(ESC);
      await window.shows('Interrupted by user');
      await window.shows('Cancelled');
      expect(
        !window.frame().includes('Running 2'),
        'a cancelled child runs on',
      ).toBeTruthy();
    },
    { rows: 40, columns: 120 },
  ));

test('a call a subagent left unfinished waits on nothing once it has ended', async () => {
  const shown = async (state: Subagent['state']) => {
    const drawn = await draw(
      <Agents
        agents={[
          {
            id: 's1',
            title: 'Fix the tokenizer',
            state,
            entries: [
              {
                kind: 'tool',
                turnId: 't',
                call: { id: 'c', title: 'Edit', status: 'pending' },
              },
            ],
            plan: [],
          },
        ]}
        turn={{ status: 'idle' }}
        agent='fake'
        open
        width={80}
      />,
    );
    const frame = stripAnsi(drawn.frame());

    await drawn.unmount();

    return frame;
  };

  expect(await shown('running')).toContain('Waiting…');
  expect(
    !(await shown('cancelled')).includes('Waiting…'),
    'an ended call waits',
  ).toBeTruthy();
  expect(await shown('cancelled')).toContain('⏺ Edit');
});

test('a task whose record has gone says so where its work would be, only when open', async () => {
  const shown = async (open: boolean) => {
    const drawn = await draw(
      <Agents
        agents={[
          {
            id: 's1',
            title: 'Fix the tokenizer',
            description: 'taskchild',
            state: 'cancelled',
            entries: [],
            plan: [],
            startedAt: 0,
            endedAt: 9_000,
            task: {
              name: 'Fix the tokenizer',
              runtime: 'fake',
              workLost: true,
            },
          },
        ]}
        turn={{ status: 'idle' }}
        agent='fake'
        open={open}
        width={80}
      />,
    );
    const frame = stripAnsi(drawn.frame());

    await drawn.unmount();

    return frame;
  };

  expect(await shown(true)).toContain(
    "⎿  taskchild\n     Its work was not kept: the task's record is gone.\n  ⎿  Cancelled (9s)",
  );
  expect(
    !(await shown(false)).includes('not kept'),
    'a folded block says it',
  ).toBeTruthy();
  expect(await shown(false)).toContain('⎿  Cancelled (9s)');
});

test("a lone block's headline wraps whole, its runtime, model and effort after the `)`", async () => {
  const drawn = await draw(
    <Agents
      agents={[
        {
          id: 's1',
          title: 'Fix the tokenizer so a heredoc reaches the shell whole',
          state: 'completed',
          entries: [],
          plan: [],
          startedAt: 0,
          endedAt: 9_000,
          task: {
            name: 'Fix the tokenizer',
            runtime: 'codex',
            model: 'gpt-5.3-codex',
            effort: 'high',
          },
        },
      ]}
      turn={{ status: 'idle' }}
      agent='fake'
      open={false}
      width={36}
    />,
    { columns: 40, rows: 10 },
  );
  const frame = stripAnsi(drawn.frame());

  await drawn.unmount();

  expect(frame).toContain(
    [
      '⏺ Agent(Fix the tokenizer so a heredoc',
      '  reaches the shell whole) · codex ·',
      '  gpt-5.3-codex · high',
    ].join('\n'),
  );
});

describe('tester: selectable group titles', () => {
  for (const [columns, rows] of [
    [120, 40],
    [80, 24],
  ] as const) {
    test(`a group title selects without its tree or counts at ${columns} columns`, () =>
      withWindow(
        async (window) => {
          await send(window, 'subagent');
          await asked(window);

          const lines = stripAnsi(window.frame()).split('\n');
          const y = lines.findIndex((line) =>
            line.includes('├─ Agent(Find the session layer)'),
          );

          expect(y).toBeGreaterThanOrEqual(0);
          expect(lines[y]).toContain('tool use');

          const mouse = (button: number, x: number, release = false) =>
            `\x1b[<${button};${x + 1};${y + 1}${release ? 'm' : 'M'}`;

          await window.press(mouse(0, lines[y]!.indexOf('Agent(')));
          await window.press(mouse(32, columns - 1));
          await window.press(mouse(0, columns - 1, true));

          expect(window.selected()).toBe('Agent(Find the session layer)');
        },
        { columns, rows },
      ));
  }
});

describe('subagentstates: the states subagent never reaches', () => {
  test("the parent's plan shows above the prompt, a child's never does", () =>
    withWindow(
      async (window) => {
        await send(window, 'subagentstates');
        await window.shows('⏺ Agent(Find the session layer)');
        await window.shows(
          [
            '  ⎿  ☒ Plan the change',
            '     ◐ Read the session layer',
            '     ☐ Write the design',
          ].join('\n'),
        );
        await window.shows('+2 more tool uses');
        expect(
          !window.frame().includes('Find the transport'),
          "a child's plan shows",
        ).toBeTruthy();
      },
      { rows: 40, columns: 120 },
    ));

  test('a lone running child shows its latest three calls and counts the rest', () =>
    withWindow(
      async (window) => {
        await send(window, 'subagentstates');
        await window.shows(
          [
            '⏺ Agent(Find the session layer)',
            '   ⎿  Read(src/session/session.ts)',
            '      Read(src/session/conversation.ts)',
            '      Read(src/session/enrichers.ts)',
            '      +2 more tool uses (ctrl+o to expand)',
          ].join('\n'),
        );
      },
      { rows: 40, columns: 120 },
    ));

  test("the parent's own call draws beside a running group of two", () =>
    withWindow(
      async (window) => {
        await send(window, 'subagentstates');
        await until('the parent to wait on its running pair', () => {
          const frame = window.frame();

          return (
            frame.includes('⏺ Running 2 agents… (ctrl+o to expand)') &&
            frame.includes('⏺ Wait(explorer, worker)\n   ⎿  Running…')
          );
        });

        expect(window.frame()).toContain('⎿  Done (5 tool uses · ');
      },
      { rows: 40, columns: 120 },
    ));

  test('a group whose children all completed reads as finished', () =>
    withWindow(
      async (window) => {
        await send(window, 'subagentstates');
        await window.shows('⏺ 2 agents finished (ctrl+o to expand)');
        await window.shows('drawing is Tool in');

        const frame = window.frame();

        expect(frame).toContain('├─ Agent(explorer) · 3 tool uses · ');
        expect(frame).toContain('│  ⎿  Done');
        expect(frame).toContain('└─ Agent(worker) · 1 tool use · ');
        expect(frame).toContain('      ⎿  Done');
        expect(frame).toContain('⏺ Wait(explorer, worker)');
        expect(
          !frame.includes('Running…'),
          'the wait runs on after the pair',
        ).toBeTruthy();
      },
      { rows: 40, columns: 120 },
    ));
});

describe('tester: subagentstates keys and terminal sizes', () => {
  for (const [columns, rows] of [
    [120, 40],
    [80, 24],
  ] as const) {
    test(`the child plan opens with ctrl+o and all four states fit at ${columns} columns`, () =>
      withWindow(
        async (window) => {
          await send(window, 'subagentstates');
          await window.shows('Search(sessionUpdate in src)');
          expect(window.frame()).toContain('◐ Read the session layer');
          expect(window.frame()).not.toContain('Find the transport');
          await window.press(CTRL_O);
          await window.shows('Find the transport');
          expect(window.frame()).toContain('◐ Read the session layer');
          await window.press(CTRL_O);
          await window.shows('+2 more tool uses (ctrl+o to expand)');

          const lone = window.frame();

          expect(lone).toContain('Read(src/session/session.ts)');
          expect(lone).toContain('Read(src/session/conversation.ts)');
          expect(lone).toContain('Read(src/session/enrichers.ts)');
          expect(lone).not.toContain('Search(sessionUpdate in src)');
          expect(lone).not.toContain('Find the transport');
          await until('the parent to wait beside its running pair', () => {
            const frame = window.frame();

            return (
              frame.includes('Running 2 agents…') &&
              frame.includes('Wait(explorer, worker)\n   ⎿  Running…')
            );
          });

          await window.shows('2 agents finished (ctrl+o to expand)');
          await window.shows('drawing is Tool');

          const finished = window.frame();

          expect(finished).toContain('│  ⎿  Done');
          expect(finished).toContain('      ⎿  Done');
          expect(finished).not.toContain('Running…');
        },
        { columns, rows },
      ));

    for (const phase of ['lone child', 'pair'] as const) {
      test(`Esc cancels the ${phase} at ${columns} columns`, () =>
        withWindow(
          async (window) => {
            await send(window, 'subagentstates');

            if (phase === 'lone child') {
              await window.shows('+2 more tool uses');
            } else {
              await until('the pair and parent wait to run', () => {
                const frame = window.frame();

                return (
                  frame.includes('Running 2 agents…') &&
                  frame.includes('Wait(explorer, worker)\n   ⎿  Running…')
                );
              });
            }

            await window.press(ESC);
            await window.shows('Interrupted by user');
            await window.shows(
              phase === 'pair' ? '2 agents ended · 2 cancelled' : 'Cancelled',
            );
            expect(window.frame()).not.toContain('Running 2 agents');
            expect(window.frame()).not.toContain('still running');
          },
          { columns, rows },
        ));
    }
  }
});
