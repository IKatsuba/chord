/**
 * The background's summary line in the window, on the fake agent and chord's
 * own server: counted by state, reached with ↓ as the list's last stop, and
 * cleared of what ended by the person's next prompt.
 */
import { describe, expect, test } from 'bun:test';
import { serveChord } from '../../../src/server/server.ts';
import { SummaryLine } from '../../../src/ui/background/Background.tsx';
import type { BackgroundItem } from '../../../src/ui/background/background.ts';
import { draw } from '../harness.tsx';
import {
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

test('with no child open the summary line stands alone; ↓ reaches it, x and enter do nothing there, esc and ↑ go back to the box', () =>
  withBackground(async (window) => {
    await ready(window);
    await send(window, 'monitors');
    await window.shows('Two monitors are running.');
    await window.shows('    background  2 monitors running');

    await window.press(DOWN);
    await window.shows('  ❯ background  2 monitors running');
    await window.shows('↑ ↓ to move · enter to open · esc to go back');

    // Not an item: x stops nothing, and enter leaves the ❯ where it is.
    await window.press('x');
    await window.press('\r');
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
