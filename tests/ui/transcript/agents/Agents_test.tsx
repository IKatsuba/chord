import { describe, expect, test } from 'bun:test';
import { useState } from 'react';
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

test("Claude's subagents read as each ended, a failure's message and an untracked one's line in ctrl+o's view", () =>
  withWindow(
    async (window) => {
      await send(window, 'claudesubagents');
      await asked(window);
      await window.press('1');
      await window.shows(
        '⏺ 4 agents ended · 1 failed, 1 untracked, 1 cancelled (ctrl+o to expand)',
      );

      let frame = window.frame();

      expect(frame).toContain('⎿  Untracked');
      expect(frame).toContain('⎿  Cancelled');
      expect(frame).toContain('⎿  Failed');
      expect(frame).not.toContain('API Error');
      await window.press(CTRL_O);
      await window.shows('API Error: 529 Overloaded');

      frame = window.frame();

      expect(frame).toContain(
        'The agent no longer reports this subagent; it may still be at work.',
      );
    },
    { rows: 80, columns: 120 },
  ));

test("ctrl+o shows a subagent's whole task, and a later message among its work, from its agent's runtime", () =>
  withWindow(
    async (window) => {
      await send(window, 'claudemessage');
      await window.shows('Both found.');
      expect(window.frame()).not.toContain('Report the file');
      await window.press(CTRL_O);
      await window.shows(
        'Report the file that owns the routing, with line numbers.',
      );

      const frame = window.frame();

      expect(frame).not.toContain('Find the session layer');
      expect(frame).toContain('← from fake');
      expect(frame).toContain('⎿  Now find the tests that cover it.');
    },
    { rows: 80, columns: 120 },
  ));

test('Esc leaves a subagent that can be cancelled alone at work until its agent says it ended', () =>
  withWindow(
    async (window) => {
      await send(window, 'claudebackground');
      await window.shows('⏺ Running 2 agents…');
      await window.press(ESC);
      await window.shows('Interrupted by user');
      await window.shows('Cancelled');

      const frame = window.frame();

      expect(frame).toContain('⏺ Running 2 agents…');
      expect(frame).toContain('1 agent still running');
      await window.shows('⏺ 2 agents ended · 1 cancelled');
      expect(window.frame()).toContain('│  ⎿  Done');
    },
    { rows: 40, columns: 120 },
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

            if (phase === 'pair') {
              // The worker may finish before Esc reaches the pair; only
              // children still running then are cancelled.
              await window.shows('2 agents ended');
              expect(window.frame()).toMatch(/2 agents ended · [12] cancelled/);
            } else {
              await window.shows('Cancelled');
            }

            expect(window.frame()).not.toContain('Running 2 agents');
            expect(window.frame()).not.toContain('still running');
          },
          { columns, rows },
        ));
    }
  }
});

describe('CHD-432 tester: ending notes in terminal widths', () => {
  for (const columns of [80, 120]) {
    for (const [state, word, note] of [
      [
        'untracked',
        'Untracked',
        'The agent no longer reports this subagent; it may still be at work.',
      ],
      ['ended', 'Ended', 'The agent did not say how it ended.'],
      ['failed', 'Failed', 'API Error: 529 Overloaded'],
    ] as const) {
      test(`${word} keeps its frozen duration and opens its whole note at ${columns} columns`, async () => {
        for (const open of [false, true]) {
          const drawn = await draw(
            <Agents
              agents={[
                {
                  id: 'ending',
                  title: 'Check the transport',
                  state,
                  ...(state === 'failed' ? { error: note } : {}),
                  entries: [],
                  plan: [],
                  startedAt: 1000,
                  endedAt: 9000,
                },
              ]}
              turn={{ status: 'idle' }}
              agent='fake'
              open={open}
              width={columns - 4}
            />,
            { columns, rows: 24 },
          );

          try {
            const frame = stripAnsi(drawn.frame()).replace(/\s+/g, ' ');

            expect(frame).toContain(`${word} (0 tool uses · 8s)`);

            if (open) {
              expect(frame).toContain(note);
            } else {
              expect(frame).not.toContain(note);
            }
          } finally {
            await drawn.unmount();
          }
        }
      });
    }
  }
});

describe('CHD-432 tester: whole-task expansion keys', () => {
  for (const [columns, rows] of [
    [120, 40],
    [80, 24],
  ] as const) {
    test(`Ctrl+O opens the whole task and sender then folds them again at ${columns} columns`, () =>
      withWindow(
        async (window) => {
          await send(window, 'claudemessage');
          await window.shows('Both found.');
          expect(window.frame()).not.toContain('Report the file');
          await window.press(CTRL_O);
          await window.shows(
            'Report the file that owns the routing, with line numbers.',
          );
          expect(window.frame()).toContain('← from fake');
          expect(window.frame()).toContain('Now find the tests that cover it.');
          await window.press(CTRL_O);
          await until(
            'the task and message to fold again',
            () => !window.frame().includes('Report the file'),
          );
          expect(window.frame()).not.toContain('Report the file');
          expect(window.frame()).not.toContain('← from fake');
        },
        { columns, rows },
      ));
  }
});

test('a row that was last when drawn keeps its column once a sibling comes after it (Q41)', () =>
  withWindow(
    async (window) => {
      // Announced one at a time, each row is the last for a moment.
      await send(window, 'claudesubagents');
      await asked(window);
      await window.press('1');
      await window.shows('4 agents ended');

      const frame = window.frame();

      for (const ending of ['Done', 'Failed', 'Cancelled']) {
        expect(frame).toContain(`│  ⎿  ${ending}`);
      }

      expect(frame).not.toContain('│   ⎿');
    },
    { rows: 40, columns: 120 },
  ));

describe('Q41 tester: a mounted last row gains a sibling', () => {
  for (const columns of [80, 120]) {
    for (const open of [false, true]) {
      test(`${open ? 'expanded' : 'folded'} bodies retain their column after a committed last-to-non-last transition at ${columns} columns`, async () => {
        const agents: Subagent[] = [
          {
            id: 'a',
            title: 'First',
            description: 'First task',
            state: 'completed',
            entries: [],
            plan: [],
          },
          {
            id: 'b',
            title: 'Second',
            description:
              'Second task has enough words to wrap and keep its body under the same branch.',
            error: 'Second failure detail',
            state: 'failed',
            entries: [],
            plan: [],
          },
          {
            id: 'c',
            title: 'Third',
            description: 'Third task',
            state: 'cancelled',
            entries: [],
            plan: [],
          },
        ];
        let append = () => {};

        function ChangingGroup() {
          const [count, setCount] = useState(2);

          append = () => setCount(3);

          return (
            <Agents
              agents={agents.slice(0, count)}
              turn={{ status: 'idle' }}
              agent='fake'
              open={open}
              width={columns - 4}
            />
          );
        }

        const drawn = await draw(<ChangingGroup />, { columns, rows: 24 });

        try {
          const before = stripAnsi(drawn.frame());

          expect(before).toContain('└─ Agent(Second)');
          expect(before).not.toContain('Agent(Third)');
          append();

          await until('the newly appended third sibling to render', () =>
            drawn.frame().includes('Agent(Third)'),
          );

          const frame = stripAnsi(drawn.frame());

          expect(frame).toContain('├─ Agent(Second)');
          expect(frame).toContain('│  ⎿  Failed');
          expect(frame).not.toContain('│   ⎿');

          if (open) {
            expect(frame).toContain('│  ⎿  Second task');
            expect(frame).toContain('│     Second failure detail');
          }
        } finally {
          await drawn.unmount();
        }
      });
    }
  }
});

describe('CHD-404 tester: expanded subagent permission matching', () => {
  test('only the requested child call waits, including a request queued second', async () => {
    for (const requested of ['child-a', 'child-b', undefined]) {
      const drawn = await draw(
        <Agents
          agents={[
            {
              id: 'child-a',
              title: 'Inspect deploy',
              state: 'running',
              plan: [],
              entries: [
                {
                  kind: 'tool',
                  turnId: 't',
                  call: {
                    id: 'same',
                    title: 'Run ./deploy.sh',
                    status: 'in_progress',
                    content: [
                      {
                        type: 'content',
                        content: { type: 'text', text: 'existing output' },
                      },
                    ],
                  },
                },
              ],
            },
          ]}
          turn={{
            status: 'awaiting_permission',
            turnId: 't',
            since: 0,
            permissions: [
              { id: 'first', toolCallId: 'other', options: [] },
              {
                id: 'second',
                toolCallId: 'same',
                ...(requested === undefined ? {} : { subagentId: requested }),
                options: [],
              },
            ],
          }}
          agent='fake'
          open
          width={78}
        />,
        { columns: 80, rows: 24 },
      );

      try {
        const frame = stripAnsi(drawn.frame());

        expect(frame).toContain('existing output');
        expect(frame.includes('Waiting…')).toBe(requested === 'child-a');
      } finally {
        await drawn.unmount();
      }
    }
  });
});
