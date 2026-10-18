/**
 * The background's summary line in the window, on the fake agent and chord's
 * own server: counted by state, reached with ↓ as the list's last stop, and
 * cleared of what ended by the person's next prompt.
 */
import { describe, expect, test } from 'bun:test';
import { serveChord } from '../../../src/server/server.ts';
import { SummaryLine } from '../../../src/ui/background/Background.tsx';
import { BackgroundView } from '../../../src/ui/background/BackgroundView.tsx';
import type { BackgroundItem } from '../../../src/ui/background/background.ts';
import { fakeAgentCommand } from '../../fixtures/fake.ts';
import { draw } from '../harness.tsx';
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

test("an ended monitor stays until the person's next prompt, which clears it", () =>
  withBackground(async (window) => {
    await ready(window);
    await send(window, 'monitorexit');
    await window.shows('    background  1 monitor running');
    // Its end reaches the agent as a message, which clears nothing.
    await window.shows('← from CI run 4812 · monitor · exit code 1');
    await window.shows('    background  ✗ 1 monitor failed');
    await window.shows('Received the message from CI run 4812');
    await new Promise((resolve) => setTimeout(resolve, 200));
    expect(window.frame()).toContain('    background  ✗ 1 monitor failed');

    await send(window, 'hello');
    await until(
      'the summary line gone',
      () => !window.frame().includes('background  '),
    );
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
  test('a prompt in another tab leaves ended items alone; a prompt in their tab clears only ended items', () =>
    withBackground(async (window) => {
      await ready(window);
      await send(window, 'monitors');
      await window.shows('background  2 monitors running');
      await send(window, 'monitorexit');
      await window.shows('background  ✗ 1 monitor failed · 2 monitors running');
      await window.shows('Received the message from CI run 4812');

      await leader(window, 'c');
      await ready(window);
      await send(window, 'monitor');
      await window.shows('background  1 monitor running');
      expect(window.frame()).not.toContain('1 monitor failed');
      await send(window, 'hello');
      await window.shows('background  1 monitor running');

      await leader(window, '1');
      await window.shows('background  ✗ 1 monitor failed · 2 monitors running');
      await send(window, 'hello');
      await window.shows('background  2 monitors running');
      expect(window.frame()).not.toContain('background  ✗');
      await leader(window, '2');
      await window.shows('background  1 monitor running');
    }));

  test('a child prompt clears the whole tab; closing that child removes its items without adding an ended row', () =>
    withBackground(
      async (window) => {
        await ready(window);
        await send(window, 'monitorchild');
        await window.shows('background  2 monitors running');
        await send(window, 'monitorexit');
        await window.shows(
          'background  ✗ 1 monitor failed · 2 monitors running',
        );
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

test('enter on the summary line opens the view; ↑ ↓ and j k move, x stops a monitor in place, esc goes back to the summary line', () =>
  withBackground(async (window) => {
    await ready(window);
    await send(window, 'monitors');
    await window.shows(
      'Received the message from dev server errors · monitor.',
    );
    await window.press(DOWN);
    await window.shows('❯ background');
    await window.press('\r');
    await window.shows(' Background · 2 in this tab');
    await window.shows(
      '↑ ↓ to move · enter to go to its call · x to stop · esc to close',
    );
    // The whole window: no prompt box, no status line.
    expect(!window.frame().includes('╭')).toBeTruthy();
    expect(window.frame()).toMatch(
      /❯ dev server errors {2}monitor {2}running \d+s · 1 event +main/,
    );

    await window.press('j');
    await window.shows('❯ CI run 4812');
    // The last row stays the last.
    await window.press(DOWN);
    await window.press('x');
    await window.shows('■ stopped after');
    expect(window.frame()).toMatch(/❯ CI run 4812 .*■ stopped after \d+s/);
    await window.press('k');
    await window.shows('❯ dev server errors');

    await window.press(ESC);
    await window.shows('❯ background  1 monitor running · ■ 1 monitor stopped');
    // The stop is told in the transcript as before.
    await window.shows('← from CI run 4812 · monitor · stopped');
    await window.press('\r');
    await window.shows(' Background · 2 in this tab');
    await window.press(ESC);
    await window.press(ESC);
    await until('the ❯ gone', () => !window.frame().includes('❯ background'));
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
    await window.shows(' Background · 2 in this tab');

    // ctrl+x w would open the sessions picker; ctrl+x c a new tab.
    await window.press(CTRL_X);
    await window.press('w');
    await window.press(CTRL_X);
    await window.press('c');
    await new Promise((resolve) => setTimeout(resolve, 300));
    expect(window.frame()).toContain(' Background · 2 in this tab');
    expect(!window.frame().includes('╭')).toBeTruthy();

    await window.press(ESC);
    await window.shows('❯ background  2 monitors running');
    expect(!window.frame().includes(' 2 fake ')).toBeTruthy();
    expect(window.frame()).toContain('Two monitors are running.');
  }));

describe('CHD-424 tester: full-screen background edges', () => {
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

  test('x stops a permission-waiting task immediately and a second x on its ended row changes nothing', () =>
    withSlowTask(async (window) => {
      await ready(window);
      await send(window, 'task');
      await window.shows('background  1 task running');
      await window.press(DOWN);
      await window.press('\r');
      await window.shows('● permission');
      await window.shows('❯ Fix the tokenizer');
      await window.press('x');
      await window.shows('■ stopped after');

      const stopped = window.frame();

      await window.press('x');
      await window.press(UP);
      expect(window.frame()).toBe(stopped);
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
        await window.shows('… 3 below');

        for (let index = 0; index < 25; index++) {
          await window.press('j');
        }

        await window.shows('… 3 above');
        expect(window.frame()).toContain('❯ Watch the build');
        expect(window.frame()).not.toContain(' below');
        expect(window.frame().split('\n')).toHaveLength(24);
        await window.press('x');
        await window.shows('■ stopped after');
        expect(window.frame()).toMatch(/❯ Watch the build .*■ stopped after/);
        await window.press(ESC);
        await window.shows('❯ background  21 tasks running · ■ 1 task stopped');
        await window.press('\r');
        await window.shows('❯ Watch the build');
        await window.shows('… 3 below');
        expect(window.frame()).not.toContain(' above');
      },
      { rows: 24, columns: 80 },
    ));

  test('a stopped monitor duration freezes while another monitor keeps ticking', () =>
    withBackground(async (window) => {
      await ready(window);
      await send(window, 'monitors');
      await window.shows('background  2 monitors running');
      await window.press(DOWN);
      await window.press('\r');
      await window.shows('❯ dev server errors');
      await window.press('x');
      await window.shows('■ stopped after');

      const row = () =>
        window
          .frame()
          .split('\n')
          .find((line) => line.includes('❯ dev server errors'));
      const stopped = row();
      const running = /running ([^·\n]+)/.exec(window.frame())?.[1];

      await until(
        'running monitor time advances',
        () => /running ([^·\n]+)/.exec(window.frame())?.[1] !== running,
      );
      await window.press('x');
      expect(row()).toBe(stopped);
      expect(window.frame()).toContain('Background · 2 in this tab');
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
      const kept = [
        lines[at]!.trim().split(/\s+/)[1],
        lines[at + 1]!.trim(),
        lines[at + 2]!.trim(),
      ].join('');

      expect(kept).toBe(items[29]!.name);
      expect(drawn.frame()).toContain(' above');
      expect(drawn.frame()).not.toContain(' below');
      expect(lines).toHaveLength(24);
      expect(lines[23]).toContain('esc to close');
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
      await window.shows('background  ✗ 1 agent failed · ? 1 agent untracked');
      expect(window.frame()).toContain('✓ 1 agent done');
      expect(window.frame()).toContain('■ 1 agent stopped');
      await window.press(DOWN);
      await window.press('\r');
      await window.shows(' Background · 4 in this tab');

      const frame = window.frame();

      for (const words of [
        'Find the session layer',
        'agent',
        '✓ done in',
        '✗ failed after',
        '■ stopped after',
        '? untracked',
      ]) {
        expect(frame).toContain(words);
      }

      await window.press('j');
      await window.shows('❯ Review the transcript');
      await window.press('\r');
      // At the transcript's end, it goes as high as scrolling allows.
      await until("the view to close on the reviewer's own row", () =>
        window.frame().includes('├─ Agent(reviewer (general-purpose))'),
      );
      expect(window.frame()).not.toContain('Background ·');
    }, size));
}

test('an agent its agent says waits, with no request on screen, is asking: ● waiting on its row', () =>
  withWindow(
    async (window) => {
      await send(window, 'claudewaiting');
      await window.shows('background  ● 1 agent asking');
      await window.press(DOWN);
      await window.press('\r');
      await window.shows('● waiting');
      await window.shows('✓ done in');
      await window.press(ESC);
      await window.shows('background  ✓ 1 agent done');
    },
    { rows: 24, columns: 80 },
  ));
