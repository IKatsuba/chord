/**
 * The background's summary line in the window, on the fake agent and chord's
 * own server: counted by state, reached with ↓ as the list's last stop, and
 * cleared of what ended by the person's next prompt.
 */
import { describe, expect, test } from 'bun:test';
import { useState } from 'react';
import { serveChord } from '../../../src/server/server.ts';
import { SummaryLine } from '../../../src/ui/background/Background.tsx';
import { BackgroundView } from '../../../src/ui/background/BackgroundView.tsx';
import type { BackgroundItem } from '../../../src/ui/background/background.ts';
import type { RequestScroller } from '../../../src/ui/dialogs/Permission.tsx';
import { hintLines, stopRefused } from '../../../src/ui/background/view.ts';
import assert from 'node:assert/strict';
import { FORM_SCHEMA } from '../../fixtures/forms.ts';
import { fakeAgentCommand } from '../../fixtures/fake.ts';
import { draw } from '../harness.tsx';
import {
  CTRL_X,
  DOWN,
  ESC,
  leader,
  promptRow,
  ready,
  send,
  until,
  UP,
  type Window,
  withWindow,
} from '../app/render.tsx';

/** Runs `body` in a window with chord's server, the fake its one runtime. */
async function withBackground(
  body: (window: Window) => Promise<void>,
  size: { rows: number; columns: number } = { rows: 40, columns: 120 },
) {
  const server = serveChord();

  try {
    await withWindow(body, { server, runtimes: ['fake'], ...size });
  } finally {
    await server.close();
  }
}

test('with no child open the summary line stands alone; ↓ reaches it, x does nothing there, esc and ↑ go back to the box', () =>
  withBackground(async (window) => {
    await ready(window);
    await send(window, 'monitors');
    await window.shows('Two monitors are running.');
    await window.shows('    background  2 monitors running');

    await window.press(DOWN);
    await window.shows('  ❯ background  2 monitors running');
    await window.shows('↑ ↓ to move · enter to open · esc to go back');

    // Not an item: x stops nothing, and ↓ leaves the ❯ where it is.
    await window.press('x');
    await window.press(DOWN);
    await new Promise((resolve) => setTimeout(resolve, 200));
    expect(window.frame()).toContain('  ❯ background  2 monitors running');
    expect(!window.frame().includes('· stopped')).toBeTruthy();

    await window.press(ESC);
    await until('the ❯ gone', () => !window.frame().includes('❯ background'));
    await window.press(DOWN);
    await window.shows('❯ background');
    await window.press(UP);
    await until('the ❯ gone', () => !window.frame().includes('❯ background'));
    await send(window, '/echo back in the box');
    await window.shows('back in the box');
  }));

test('an ended monitor leaves the summary line at once, its end said by the message to its agent (CHD-479)', () =>
  withBackground(async (window) => {
    await ready(window);
    await send(window, 'monitorexit');
    await window.shows('    background  1 monitor running');
    await window.shows('← from CI run 4812 · monitor · exit code 1');
    await until(
      'the summary line gone',
      () => !window.frame().includes('background  '),
    );
    await window.shows('Received the message from CI run 4812');
    expect(window.frame()).not.toContain('monitor failed');
  }));

test('the summary line is the stop after the agents: ↓ from the last agent, the agent picked staying picked; ↑ goes back to it', () =>
  withBackground(
    async (window) => {
      await ready(window);
      await send(window, 'monitorchild');
      await window.shows('parser watches its tests; I watch the dev server.');
      await window.shows('    background  2 monitors running');
      await window.shows('    parser ');

      await window.press(DOWN);
      await window.shows('❯ main ');
      await window.press(DOWN);
      await window.shows('❯ parser ');
      await window.press(DOWN);
      await window.shows('❯ background  2 monitors running');
      expect(!window.frame().includes('❯ parser ')).toBeTruthy();
      // parser is still the one the prompt goes to.
      expect(window.frame()).toContain('parser · fake');

      await window.press(UP);
      await window.shows('❯ parser ');
      expect(!window.frame().includes('❯ background')).toBeTruthy();
    },
    { rows: 24, columns: 80 },
  ));

describe('CHD-424 tester: standing background edges', () => {
  test('ended monitors stay absent across prompts in their tab and another tab', () =>
    withBackground(async (window) => {
      await ready(window);
      await send(window, 'monitors');
      await window.shows('background  2 monitors running');
      await send(window, 'monitorexit');
      await window.shows('background  2 monitors running');
      await window.shows('Received the message from CI run 4812');

      await leader(window, 'c');
      await ready(window);
      await send(window, 'monitor');
      await window.shows('background  1 monitor running');
      expect(window.frame()).not.toContain('1 monitor failed');
      await send(window, 'hello');
      await window.shows('background  1 monitor running');

      await leader(window, '1');
      await window.shows('background  2 monitors running');
      await send(window, 'hello');
      await window.shows('background  2 monitors running');
      expect(window.frame()).not.toContain('background  ✗');
      await leader(window, '2');
      await window.shows('background  1 monitor running');
    }));

  test('a child prompt keeps running monitors; closing that child removes its items without adding an ended row', () =>
    withBackground(
      async (window) => {
        await ready(window);
        await send(window, 'monitorchild');
        await window.shows('background  2 monitors running');
        await send(window, 'monitorexit');
        await window.shows('background  2 monitors running');
        await window.press(DOWN);
        await window.press(DOWN);
        await window.shows('❯ parser ');
        await window.press('\r');
        await send(window, 'hello');
        await window.shows('background  2 monitors running');
        expect(window.frame()).not.toContain('background  ✗');

        await window.press(DOWN);
        await window.shows('❯ parser ');
        await window.press('x');
        await window.shows('background  1 monitor running');
        expect(window.frame()).not.toContain('❯ parser ');
        expect(window.frame()).not.toContain('1 monitor stopped');
        await window.press(ESC);
        await send(window, '/clear');
        await until(
          'all background items removed by /clear',
          () => !window.frame().includes('background  '),
        );
      },
      { rows: 24, columns: 80 },
    ));

  test('a task asks and reports in the summary without creating an agent row; its report message retains done', () =>
    withBackground(async (window) => {
      await ready(window);
      await send(window, 'task');
      await window.shows('background  ● 1 task asking');
      expect(window.frame()).not.toMatch(/^ {4}main\s/m);
      // Once the parent's turn, a fixed 3 s, has ended, however the task's
      // ask fell, it waits between turns for ctrl+x a (CHD-470).
      await window.shows(
        'Agent(Fix the tokenizer) · fake asks · between turns',
      );
      await leader(window, 'a');
      await window.shows('Esc to reject');
      await window.press('1');
      await window.shows('background  ✓ 1 task done');
      await window.shows(
        'Received the message from Fix the tokenizer · fake · report.',
      );
      expect(window.frame()).toContain('background  ✓ 1 task done');
      await send(window, 'hello');
      await until(
        'reported task cleared',
        () => !window.frame().includes('background  '),
      );
    }));

  for (const columns of [80, 40]) {
    test(`all five groups render without lost words at ${columns} columns, with only one focus mark`, async () => {
      const items: BackgroundItem[] = [
        {
          kind: 'task',
          id: 'a',
          key: 1,
          name: 'ask',
          startedAt: 0,
          status: { group: 'asking', on: 'permission', since: 0 },
        },
        {
          kind: 'monitor',
          id: 'b',
          key: 1,
          name: 'fail',
          startedAt: 0,
          status: { group: 'failed', endedAt: 1 },
        },
        {
          kind: 'monitor',
          id: 'c',
          key: 1,
          name: 'run',
          startedAt: 0,
          status: { group: 'running' },
        },
        {
          kind: 'task',
          id: 'd',
          key: 1,
          name: 'run',
          startedAt: 0,
          status: { group: 'running' },
        },
        {
          kind: 'task',
          id: 'e',
          key: 1,
          name: 'done',
          startedAt: 0,
          status: { group: 'done', endedAt: 1 },
        },
        {
          kind: 'monitor',
          id: 'f',
          key: 1,
          name: 'stop',
          startedAt: 0,
          status: { group: 'stopped', endedAt: 1 },
        },
      ];
      const drawn = await draw(
        <SummaryLine items={items} width={columns - 4} focused />,
        { columns, rows: 24 },
      );

      try {
        const lines = drawn.frame().split('\n');

        expect(lines.join(' ').trim().split(/\s+/).join(' ')).toBe(
          '❯ background ● 1 task asking · ✗ 1 monitor failed · 1 monitor and 1 task running · ✓ 1 task done · ■ 1 monitor stopped',
        );
        expect(drawn.frame().match(/❯/g)).toHaveLength(1);
        expect(lines.every((line) => Array.from(line).length <= columns)).toBe(
          true,
        );
        expect(
          lines.slice(1).every((line) => line.startsWith(' '.repeat(16))),
        ).toBe(true);
      } finally {
        await drawn.unmount();
      }
    });
  }
});

test('enter on the summary line opens the view; ↑ ↓ and j k move, x stops a monitor, whose row leaves, the ❯ going up; the last to leave closes the view', () =>
  withBackground(async (window) => {
    await ready(window);
    await send(window, 'monitors');
    await window.shows(
      'Received the message from dev server errors · monitor.',
    );
    await window.press(DOWN);
    await window.shows('❯ background');
    await window.press('\r');
    await window.shows('│ Background · 2 in this tab');
    await window.shows('Enter to go to its call · x to stop · Esc to close');
    // A picker's frame above the prompt: the transcript, the prompt box,
    // the status line and the summary line stay, the summary's ❯ gone as
    // the keys are the frame's (CHD-462).
    expect(window.frame()).toContain('Two monitors are running.');
    expect(window.frame()).toContain('│ ›');
    expect(window.frame()).toContain('? for shortcuts');
    expect(window.frame()).toContain('    background  2 monitors running');
    expect(window.frame()).not.toContain('❯ background');
    expect(window.frame()).toMatch(
      /❯ dev server errors {2}monitor {2}running \d+s · 1 event +main/,
    );

    await window.press('j');
    await window.shows('❯ CI run 4812');
    // The last row stays the last.
    await window.press(DOWN);
    await window.press('x');
    // It leaves at once, the ❯ on the row above, as it was the last
    // (CHD-479).
    await window.shows('│ Background · 1 in this tab');
    await window.shows('❯ dev server errors');
    expect(window.frame()).not.toContain('CI run 4812  monitor');
    await window.press('k');
    await window.shows('❯ dev server errors');

    await window.press(ESC);
    await window.shows('❯ background  1 monitor running');
    expect(window.frame()).not.toContain('monitor stopped');
    // The stop is told in the transcript as before.
    await window.shows('← from CI run 4812 · monitor · stopped');
    await window.press('\r');
    await window.shows('│ Background · 1 in this tab');
    // The last row leaving closes the view, as esc does, and the summary
    // line goes with it, the keys back in the prompt box.
    await window.press('x');
    await until(
      'the view and the summary line gone',
      () =>
        !window.frame().includes('│ Background') &&
        !window.frame().includes('background  '),
    );
    await window.type('y');
    await until('the draft', () => promptRow(window)?.includes('› y') ?? false);
  }));

test('x on a working task cancels its turn: its row turns to stopped, and it sends no report', () =>
  withBackground(
    async (window) => {
      await ready(window);
      await send(window, 'tasklong');
      await window.shows('The build is being watched.');
      await window.shows('    background  1 task running');
      await window.press(DOWN);
      await window.press('\r');
      await window.shows('❯ Watch the build  task · fake  working');
      await window.press('x');
      await window.shows('■ stopped after');
      await window.press(ESC);
      await window.shows('❯ background  ■ 1 task stopped');
    },
    { rows: 24, columns: 80 },
  ));

test('the view is modal: the window’s session keys do nothing in it, and esc gives the window back as it was', () =>
  withBackground(async (window) => {
    await ready(window);
    await send(window, 'monitors');
    await window.shows('    background  2 monitors running');
    await window.press(DOWN);
    await window.press('\r');
    await window.shows('│ Background · 2 in this tab');

    // ctrl+x w would open the sessions picker; ctrl+x c a new tab.
    await window.press(CTRL_X);
    await window.press('w');
    await window.press(CTRL_X);
    await window.press('c');
    await new Promise((resolve) => setTimeout(resolve, 300));
    expect(window.frame()).toContain('│ Background · 2 in this tab');
    expect(window.frame()).not.toContain('Sessions in');

    await window.press(ESC);
    await window.shows('❯ background  2 monitors running');
    expect(!window.frame().includes(' 2 fake ')).toBeTruthy();
    expect(window.frame()).toContain('Two monitors are running.');
  }));

describe('CHD-424 tester: background frame edges', () => {
  async function withSlowTask(body: (window: Window) => Promise<void>) {
    const server = serveChord();
    const agentCommand = fakeAgentCommand(undefined, '--step-ms', '30');

    try {
      await withWindow(body, {
        server,
        runtimes: ['fake'],
        rows: 40,
        columns: 120,
        agentCommand,
        startupOf: () => ({ agentCommand }),
      });
    } finally {
      await server.close();
    }
  }

  test('an arriving permission hides the frame, then x stops its resumed task and a second x changes nothing', () =>
    withSlowTask(async (window) => {
      await ready(window);
      // Its turn runs until it is cancelled, so the task asks within it
      // however slow it is (CHD-470).
      await send(window, 'taskstays');
      await window.shows('background  1 task running');
      await window.press(DOWN);
      await window.press('\r');
      await window.shows('Do you want to proceed?');
      expect(window.frame()).not.toContain('Background ·');
      await window.press('1');
      await window.shows('❯ Fix the tokenizer');
      await window.press('x');
      await window.shows('■ stopped after');

      // The parent keeps working, so its clock outside the frame may tick.
      const background = () =>
        window.frame().match(/╭[^\n]*\n│ Background ·[\s\S]*?╰[^\n]*/)?.[0];
      const stopped = background();

      expect(stopped).toContain('❯ Fix the tokenizer');
      expect(stopped).toContain('■ stopped after');

      await window.press('x');
      await window.press(UP);
      expect(background()).toBe(stopped);
      await window.press(ESC);
      await window.shows('❯ background  ■ 1 task stopped');
      expect(window.frame()).not.toContain('waiting for permission');
      expect(window.frame()).not.toContain('· report');
    }));

  test('22 task rows scroll at 80x24, keep focus visible at both ends, and reopen on the first row', () =>
    withBackground(
      async (window) => {
        await ready(window);

        for (let count = 1; count <= 22; count++) {
          await send(window, 'tasklong');
          await window.shows(
            `background  ${count} ${count === 1 ? 'task' : 'tasks'} running`,
          );
        }

        await window.press(DOWN);
        await window.press('\r');
        await window.shows('Background · 22 in this tab');
        await window.shows('│ ↓ Watch the build');

        for (let index = 0; index < 25; index++) {
          await window.press('j');
        }

        await window.shows('│ ↑ Watch the build');
        expect(window.frame()).toContain('❯ Watch the build');
        expect(window.frame()).not.toContain('│ ↓ Watch the build');
        expect(window.frame().split('\n')).toHaveLength(24);
        await window.press('x');
        await window.shows('■ stopped after');
        expect(window.frame()).toMatch(/❯ Watch the build .*■ stopped after/);
        await window.press(ESC);
        await window.shows('❯ background  21 tasks running · ■ 1 task stopped');
        await window.press('\r');
        await window.shows('❯ Watch the build');
        await window.shows('│ ↓ Watch the build');
        expect(window.frame()).not.toContain('│ ↑ Watch the build');
      },
      { rows: 24, columns: 80 },
    ));

  test('a stopped monitor leaves while the replacement monitor keeps ticking', () =>
    withBackground(async (window) => {
      await ready(window);
      await send(window, 'monitors');
      await window.shows('background  2 monitors running');
      await window.press(DOWN);
      await window.press('\r');
      await window.shows('❯ dev server errors');
      await window.press('x');
      await window.shows('❯ CI run 4812');
      await window.shows('Background · 1 in this tab');

      const running = /running ([^·\n]+)/.exec(window.frame())?.[1];

      await until(
        'remaining monitor time advances',
        () => /running ([^·\n]+)/.exec(window.frame())?.[1] !== running,
      );
      expect(window.frame()).not.toContain('❯ dev server errors');
      expect(window.frame()).not.toContain('■ stopped after');
      await window.press('x');
      await until(
        'last monitor closes view',
        () => !window.frame().includes('Background ·'),
      );
      await window.type('back in prompt');
      expect(promptRow(window)).toContain('back in prompt');
    }));

  test('long names render whole in a scrolled 80x24 view, with the focused item and hint visible', async () => {
    const items: BackgroundItem[] = Array.from({ length: 30 }, (_, index) => ({
      kind: 'task',
      id: `task-${index}`,
      key: 1,
      name: `${index}-` + 'x'.repeat(60),
      startedAt: Date.now(),
      status: { group: 'running' },
      runtime: 'fake',
      model: 'Fake Small',
    }));
    const drawn = await draw(
      <BackgroundView items={items} focus={items[29]} columns={80} rows={24} />,
      { columns: 80, rows: 24 },
    );

    try {
      const lines = drawn.frame().split('\n');
      const at = lines.findIndex((line) => line.includes('❯ 29-'));
      const inside = (line: string) =>
        line.replace(/^│ ?/, '').replace(/ *│$/, '').trim();
      const kept = [
        inside(lines[at]!).split(/\s+/)[1],
        inside(lines[at + 1]!),
        inside(lines[at + 2]!),
      ].join('');
      const top = lines.findIndex((line) => line.startsWith('╭'));
      const bottom = lines.findIndex((line) => line.startsWith('╰'));

      expect(kept).toBe(items[29]!.name);
      expect(drawn.frame()).toMatch(/│ ↑/);
      expect(drawn.frame()).not.toMatch(/│ ↓/);
      expect(bottom - top + 1).toBeLessThanOrEqual(12);
      expect(lines[bottom - 1]).toContain(
        'Enter to go to its call · x to stop · Esc to close',
      );
    } finally {
      await drawn.unmount();
    }
  });
});

for (const size of [
  { rows: 40, columns: 120 },
  { rows: 24, columns: 80 },
]) {
  test(`Claude's agents are counted on the summary line and listed in the view, and enter goes to an agent's own row in its group, at ${size.columns}x${size.rows}`, () =>
    withWindow(async (window) => {
      // A transcript longer than a screen ahead of them, to scroll back to.
      await send(window, 'steps');
      await window.shows('150 steps read.');
      await send(window, 'claudesubagents');
      await window.shows('Do you want to proceed?');
      await window.press('1');
      await window.shows('Each agent has ended.');
      // Done, failed and stopped, three have left; the untracked one
      // stays, named by its parent (CHD-479).
      await window.shows("background  ? main's agent untracked");
      expect(window.frame()).not.toMatch(/agents? (done|failed|stopped)/);
      await window.press(DOWN);
      await window.press('\r');
      await window.shows(' Background · 1 in this tab');

      const frame = window.frame();

      for (const words of ['Watch the build', 'agent', '? untracked', 'main']) {
        expect(frame).toContain(words);
      }

      for (const words of ['✓ done in', '✗ failed after', '■ stopped after']) {
        expect(frame).not.toContain(words);
      }

      await window.press('\r');
      // At the transcript's end, it goes as high as scrolling allows.
      await until("the view to close on the watcher's own row", () =>
        window.frame().includes('Agent(watcher'),
      );
      expect(window.frame()).not.toContain('Background ·');
    }, size));
}

test('an agent its agent says waits, with no request on screen, is asking: ● waiting on its row', () =>
  withWindow(
    async (window) => {
      await send(window, 'claudewaiting');
      await window.shows("background  ● main's agent asking");
      await window.press(DOWN);
      await window.press('\r');
      await window.shows('● waiting');
      // Its end takes its row and the line away (CHD-479).
      await until(
        'the view and the summary line gone',
        () =>
          !window.frame().includes('│ Background') &&
          !window.frame().includes('background  '),
      );
    },
    { rows: 24, columns: 80 },
  ));

describe('CHD-2 tester: navigation leaves the transcript tail', () => {
  for (const [columns, rows] of [
    [120, 40],
    [80, 24],
  ] as const) {
    test(`Enter goes back to the earlier agent instead of only closing the view at ${columns} columns`, () =>
      withWindow(
        async (window) => {
          await send(window, 'claudebackground');
          await window.shows('Running 2 agents');
          await window.press(ESC);
          await window.shows('Interrupted by user');
          await send(window, 'steps');
          await window.shows('150 steps read.');
          expect(window.frame()).not.toContain(
            'Agent(tester (general-purpose))',
          );
          await window.press(DOWN);
          await window.press('\r');
          await window.shows('Background · 1 in this tab');
          expect(window.frame()).toContain('Run the test suite');
          await window.press('\r');
          await until(
            'the earlier agent row visible and later transcript tail out of view',
            () => {
              const frame = window.frame();

              return (
                frame.includes('Agent(tester (general-purpose))') &&
                !frame.includes('150 steps read.')
              );
            },
          );
          expect(window.frame()).not.toContain('Background ·');
        },
        { columns, rows },
      ));
  }
});

test("x on a Claude agent stops it alone: its row leaves, its block Cancelled, and its parent's turn goes on", () =>
  withWindow(
    async (window) => {
      await send(window, 'claudebackground');
      await window.shows("background  main's 2 agents running");
      await window.press(DOWN);
      await window.press('\r');
      await window.shows('❯ Run the test suite');
      await window.press('x');
      // Stopped, it leaves, the ❯ on the row that took its place (CHD-479).
      await window.shows('│ Background · 1 in this tab');
      expect(window.frame()).not.toContain('Run the test suite  agent');
      // The one the turn waits on runs on, and the turn ends on its own;
      // the last row leaving closes the view.
      await window.shows('The tests run on; I will say when they end.');
      await until(
        'the view gone',
        () => !window.frame().includes('│ Background'),
      );
      expect(window.frame()).toContain('⎿  Cancelled');
      expect(window.frame()).not.toContain('Interrupted by user');
    },
    { rows: 40, columns: 120 },
  ));

test('x on an agent that took its own stop back says so on the hint line, and stays running', () =>
  withWindow(
    async (window) => {
      await send(window, 'claudenostop');
      await window.shows("background  main's agent running");
      await window.press(DOWN);
      await window.press('\r');
      await window.shows('❯ Run the test suite');
      await window.press('x');
      await window.shows('this agent offers no stop');
      expect(window.frame()).not.toContain('to stop · esc to close');
      expect(window.frame()).toContain('running');
    },
    { rows: 24, columns: 80 },
  ));

describe('CHD-2 tester: stopping and refusal rendering', () => {
  for (const columns of [80, 120]) {
    test(`stopping and rolled-back waiting rows retain focus with a whole multiline refusal at ${columns} columns`, async () => {
      const item: BackgroundItem = {
        kind: 'agent',
        id: 'a',
        key: 1,
        name: 'Run the tests',
        startedAt: Date.now(),
        status: { group: 'running', stopping: true },
      };
      const first = await draw(
        <BackgroundView
          items={[item]}
          focus={item}
          columns={columns}
          rows={24}
        />,
        { columns, rows: 24 },
      );

      try {
        expect(first.frame()).toContain('■ stopping');
        expect(first.frame()).toContain('❯ Run the tests');
      } finally {
        await first.unmount();
      }

      const rollback: BackgroundItem = {
        ...item,
        status: { group: 'asking', on: 'waiting', since: Date.now() },
      };
      const hint = stopRefused(new Error('Broken pipe\ntransport detail'));
      const refused = await draw(
        <BackgroundView
          items={[rollback]}
          focus={rollback}
          hint={hint}
          columns={columns}
          rows={24}
        />,
        { columns, rows: 24 },
      );

      try {
        expect(refused.frame()).toContain('● waiting');
        expect(refused.frame()).toContain('❯ Run the tests');
        expect(refused.frame()).toContain('could not stop: Broken pipe');
        expect(refused.frame()).toContain('transport detail');
        expect(refused.frame()).toMatch(
          /could not stop: Broken pipe[^\n]*\n[^\n]*transport detail/,
        );
        expect(refused.frame()).not.toContain('■ stopping');
        expect(refused.frame()).not.toContain('x to stop');
      } finally {
        await refused.unmount();
      }
    });
  }
});

test('opened over a request held between turns, the frame gives way to ctrl+x a, which the status line names, and the box takes the keys (CHD-462)', () =>
  withBackground(async (window) => {
    await ready(window);
    await send(window, 'taskbetween');
    await window.shows('Agent(Fix the tokenizer) · fake asks · between turns');
    await window.shows('background  ● 1 task asking');
    // Held, the prompt has the keys: ↓ reaches the summary line.
    await window.press(DOWN);
    await window.press('\r');
    await window.shows('│ Background · 1 in this tab');
    expect(window.frame()).toContain('ctrl+x a to answer');

    await leader(window, 'a');
    await window.shows('❯ 1. Allow');
    expect(window.frame()).not.toContain('│ Background');
    await window.press('1');
    await window.shows(
      'Received the message from Fix the tokenizer · fake · report.',
    );
  }));

describe('CHD-462 B1 tester: an arriving input hides and resumes the frame', () => {
  for (const [columns, rows] of [
    [80, 24],
    [120, 40],
  ] as const) {
    for (const kind of ['form', 'link'] as const) {
      test(`${kind}: the incoming box takes keys and restores the focused item at ${columns} columns`, async () => {
        const server = serveChord();
        const agentCommand = fakeAgentCommand(undefined, '--step-ms', '30');

        try {
          await withWindow(
            async (window) => {
              await ready(window);
              await send(window, 'monitors');
              await window.shows('background  2 monitors running');
              await send(window, 'slow');
              await window.shows('Working');
              await window.press(DOWN);
              await window.press('\r');
              await window.shows('Background · 2 in this tab');
              await window.press('j');
              await window.shows('❯ CI run 4812');

              const session = window.session();

              assert(session);

              const response = session.elicitations.handler(
                kind === 'form'
                  ? {
                      sessionId: session.id,
                      mode: 'form',
                      message: 'Incoming deployment form',
                      requestedSchema: FORM_SCHEMA,
                    }
                  : {
                      sessionId: session.id,
                      mode: 'url',
                      message: 'Incoming release link',
                      url: 'https://example.com/release',
                      elicitationId: 'frame-link',
                    },
                new AbortController().signal,
              );

              await window.shows(
                kind === 'form'
                  ? '❯ * Project name'
                  : '❯ 1. Open in the browser',
              );
              expect(window.frame()).not.toContain('Background ·');
              await window.press(ESC);
              expect(await response).toMatchObject({ action: 'cancel' });
              await window.shows('Background · 2 in this tab');
              await window.shows('❯ CI run 4812');
              expect(window.frame()).toContain('│ ›');
              await window.press('x');
              await window.shows('Background · 1 in this tab');
              await window.shows('❯ dev server errors');
              expect(window.frame()).not.toContain('❯ CI run 4812');
              await window.press(ESC);
              await window.shows('❯ background');
              await window.press(ESC);
              expect(window.frame()).not.toContain('Background ·');
            },
            {
              server,
              runtimes: ['fake'],
              columns,
              rows,
              agentCommand,
              startupOf: () => ({ agentCommand }),
            },
          );
        } finally {
          await server.close();
        }
      });
    }
  }
});

test('a task name taller than the frame scrolls by line at 80x24: ↓ through it, ↑ back from its last line, x acts on it wherever, and a resize or reopening shows it from its first line (CHD-430)', () =>
  withBackground(
    async (window) => {
      await ready(window);
      await send(window, 'tasktallname');
      await window.shows('background  1 task running');
      await send(window, 'tasklong');
      await window.shows('background  2 tasks running');
      await window.press(DOWN);
      await window.press('\r');
      await window.shows('│ ❯ Rewrite the tokenizer');
      await window.shows('│ ↓   keeping the line and');

      // Each ↓ a line of it; its first line gone, the gutter's ↑ stands in.
      await window.press('j');
      await window.shows('│ ↑   as a single pass over');
      expect(window.frame()).not.toContain('❯ Rewrite');

      // Down to its last line, then the row below.
      for (let step = 0; step < 40; step++) {
        await window.press('j');
      }

      await window.shows('│ ❯ Watch the build');
      // The frame keeps its height: the tall row's last lines stay above,
      // the gutter's ↑ saying there is more (CHD-462).
      expect(window.frame()).toContain('│     removed together');
      expect(window.frame()).toMatch(/│ ↑ {3}\S/);
      // Back with ↑: its last line at the bottom.
      await window.press('k');
      await window.shows('removed together');
      await window.shows('│ ↑   instead, with the');

      // x stops the row the view is in, whatever line of it is in sight.
      await window.press('x');
      await window.shows('background  1 task running · ■ 1 task stopped');

      await window.resize({ columns: 82, rows: 24 });
      await window.shows('│ ❯ Rewrite the tokenizer');

      // Straight back, with no move: not where it was scrolled at 80.
      await window.resize({ columns: 80, rows: 24 });
      await window.shows('│ ❯ Rewrite the tokenizer');
      await window.resize({ columns: 82, rows: 24 });
      await window.shows('│ ❯ Rewrite the tokenizer');

      // Back to the size it was scrolled at: still from its first line.
      await window.press('j');
      await window.shows('│ ↑ ');
      await window.resize({ columns: 80, rows: 24 });
      await window.shows('│ ❯ Rewrite the tokenizer');
      // A row more, the frame as tall as before: still a resize.
      await window.press('j');
      await window.shows('│ ↑ ');
      await window.resize({ columns: 80, rows: 25 });
      await window.shows('│ ❯ Rewrite the tokenizer');

      await window.press('j');
      await window.shows('│ ↑ ');
      await window.press(ESC);
      await window.press('\r');
      await window.shows('│ ❯ Rewrite the tokenizer');
    },
    { rows: 24, columns: 80 },
  ));

describe('CHD-430 tester: a scrolled task keeps its identity', () => {
  for (const [columns, rows] of [
    [80, 24],
    [120, 40],
  ] as const) {
    test(`a live addition keeps the line in sight and Enter goes to the tall task at ${columns} columns`, async () => {
      const server = serveChord();
      const admit = server.admit.bind(server);
      let main: Parameters<typeof admit>[0] | undefined;

      server.admit = (caller) => {
        if (caller.agent === undefined && caller.task === undefined) {
          main = caller;
        }

        return admit(caller);
      };

      try {
        await withWindow(
          async (window) => {
            await ready(window);
            await send(window, 'tasktallname');
            await window.shows('background  1 task running');
            await window.press(DOWN);
            await window.press('\r');
            await window.shows('│ ❯ Rewrite the tokenizer');
            await window.press('j');
            await window.shows('│ ↑ ');

            const itemLines = () =>
              window
                .frame()
                .split('\n')
                .filter((line) => line.startsWith('│'))
                .slice(2, -2)
                .map((line) => line.trimEnd());
            const before = itemLines();

            assert(main);

            const added = await main.window.spawn(main, {
              agent: 'fake',
              name: 'New live task',
              prompt: 'taskwait',
            });

            expect(added).not.toHaveProperty('error');
            await window.shows('Background · 2 in this tab');
            expect(itemLines()).toEqual(before);
            expect(window.frame()).not.toContain('❯ Rewrite');
            await window.press('\r');
            await until(
              'the frame closes at the tall task call',
              () => !window.frame().includes('│ Background'),
            );
            await window.shows('Rewrite the tokenizer');
            expect(window.frame()).not.toContain('› New live task');
          },
          { server, runtimes: ['fake'], columns, rows },
        );
      } finally {
        await server.close();
      }
    });
  }
});

describe('CHD-473 the frame says its hint, or an error in its place, whole', () => {
  const crowd: BackgroundItem[] = Array.from({ length: 30 }, (_, index) => ({
    kind: 'task',
    id: `task-${index}`,
    key: 1,
    name: `task ${index}`,
    startedAt: Date.now(),
    status: { group: 'running' },
    runtime: 'fake',
    model: 'Fake Small',
  }));
  const inside = (line: string) =>
    line.replace(/^│ ?/, '').replace(/ *│$/, '').trim();

  test('at 46 columns the keys wrap after a `·`, and the rows give way to them within half the window', async () => {
    const drawn = await draw(
      <BackgroundView items={crowd} focus={crowd[0]} columns={46} rows={24} />,
      { columns: 46, rows: 24 },
    );

    try {
      const lines = drawn.frame().split('\n');
      const top = lines.findIndex((line) => line.startsWith('╭'));
      const bottom = lines.findIndex((line) => line.startsWith('╰'));

      expect(bottom - top + 1).toBeLessThanOrEqual(12);
      expect(inside(lines[bottom - 2]!)).toBe(
        'Enter to go to its call · x to stop ·',
      );
      expect(inside(lines[bottom - 1]!)).toBe('Esc to close');
      expect(drawn.frame()).toContain('❯ task 0');
    } finally {
      await drawn.unmount();
    }
  });

  test('a stop error is said whole on as many lines as it takes, nothing cut', async () => {
    const hint = stopRefused(
      new Error(
        'the adapter refused the stop because the task had already handed its result back',
      ),
    );
    const drawn = await draw(
      <BackgroundView
        items={crowd.slice(0, 3)}
        focus={crowd[0]}
        hint={hint}
        columns={46}
        rows={24}
      />,
      { columns: 46, rows: 24 },
    );

    try {
      const lines = drawn.frame().split('\n');
      const bottom = lines.findIndex((line) => line.startsWith('╰'));
      // The frame's last lines, 42 cells inside it at 46 columns.
      const height = hintLines(hint, 42).length;

      expect(height).toBeGreaterThan(1);
      expect(
        lines
          .slice(bottom - height, bottom)
          .map(inside)
          .join(' '),
      ).toBe(hint);
      expect(drawn.frame()).not.toContain('…');
    } finally {
      await drawn.unmount();
    }
  });
});

test("an error taller than the frame's room scrolls in it by a page, the rows given way to the ❯ row's first line, the frame within half the window (CHD-473)", async () => {
  const items: BackgroundItem[] = [
    'CI run 4812',
    'dev server errors',
    'parser tests',
  ].map((name, index) => ({
    kind: 'monitor',
    id: `m${index}`,
    key: 1,
    name,
    startedAt: Date.now(),
    status: { group: 'running' },
  }));
  const hint = stopRefused(
    new Error(
      [
        'Broken pipe',
        'while writing session/cancel to the agent process',
        'at transport.write (stdio.ts:211)',
        'at Connection.notify (connection.ts:96)',
        'at Session.cancel (session.ts:412)',
        'at Window.stop (window.ts:88)',
        'at Background.stop (background.ts:140)',
        'at keys (keys.ts:612)',
      ].join('\n'),
    ),
  );
  const scroller: { current: RequestScroller | undefined } = {
    current: undefined,
  };
  const drawn = await draw(
    <BackgroundView
      items={items}
      focus={items[0]}
      hint={hint}
      columns={46}
      rows={24}
      scroller={scroller}
    />,
    { columns: 46, rows: 24 },
  );
  const frame = () =>
    drawn
      .frame()
      .split('\n')
      .filter((line) => /^[╭│╰]/.test(line))
      .slice(0, 12);

  try {
    expect(frame()).toStrictEqual([
      '╭────────────────────────────────────────────╮',
      '│ Background · 3 in this tab                 │',
      '│                                            │',
      '│ ❯ CI run 4812        monitor               │',
      '│                                            │',
      '│ could not stop: Broken pipe                │',
      '│ while writing session/cancel to the agent  │',
      '│ process                                    │',
      '│ at transport.write (stdio.ts:211)          │',
      '│ at Connection.notify (connection.ts:96)    │',
      '│ ── ↓ 4 lines below · pagedown to scroll ── │',
      '╰────────────────────────────────────────────╯',
    ]);

    scroller.current?.('page_down');
    await until('a page on', () =>
      frame().some((line) => line.includes('↑ 4 lines above')),
    );
    expect(frame().slice(5, 11)).toStrictEqual([
      '│ ── ↑ 4 lines above · pageup to scroll ──── │',
      '│ at Connection.notify (connection.ts:96)    │',
      '│ at Session.cancel (session.ts:412)         │',
      '│ at Window.stop (window.ts:88)              │',
      '│ at Background.stop (background.ts:140)     │',
      '│ at keys (keys.ts:612)                      │',
    ]);
  } finally {
    await drawn.unmount();
  }
});

describe('CHD-473 T4 tester: error scroller lifetime', () => {
  test('a same-height new error starts at its first line, and unmount removes the callback before remount', async () => {
    const scroller: { current: RequestScroller | undefined } = {
      current: undefined,
    };
    const item: BackgroundItem = {
      kind: 'monitor',
      id: 'm',
      key: 1,
      name: 'CI run',
      startedAt: 0,
      status: { group: 'running' },
    };
    const message = (prefix: string) =>
      Array.from({ length: 20 }, (_, index) => `${prefix} ${index}`).join('\n');
    let update: (hint: string) => void = () => {};

    let mount: (shown: boolean) => void = () => {};

    function Panel() {
      const [hint, setHint] = useState(message('OLD'));
      const [shown, setShown] = useState(true);

      update = setHint;
      mount = setShown;

      return shown ? (
        <BackgroundView
          items={[item]}
          focus={item}
          hint={hint}
          columns={46}
          rows={24}
          scroller={scroller}
        />
      ) : (
        <text>closed panel</text>
      );
    }

    const drawn = await draw(<Panel />, { columns: 46, rows: 24 });

    try {
      expect(scroller.current).toBeDefined();
      scroller.current?.('page_down');
      await until('scrolled old error', () =>
        drawn.frame().includes('lines above'),
      );
      update(message('NEW'));
      await until(
        'new error resets to top',
        () =>
          drawn.frame().includes('NEW 0') &&
          !drawn.frame().includes('lines above'),
      );
      scroller.current?.('page_down');
      await until('scrolled new error', () =>
        drawn.frame().includes('lines above'),
      );
      mount(false);
      await until('panel unmounted', () =>
        drawn.frame().includes('closed panel'),
      );
      expect(scroller.current).toBeUndefined();
      mount(true);
      await until(
        'panel remounted at top',
        () =>
          drawn.frame().includes('NEW 0') &&
          !drawn.frame().includes('lines above'),
      );
      expect(scroller.current).toBeDefined();
    } finally {
      await drawn.unmount();
    }

    expect(scroller.current).toBeUndefined();
  });
});
