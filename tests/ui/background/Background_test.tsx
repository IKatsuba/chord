/**
 * The background's summary line in the window, on the fake agent and chord's
 * own server: counted by state, reached with ↓ as the list's last stop,
 * cleared of what ended by the person's next prompt, and the view it opens
 * with its stops.
 */
import { describe, expect, test } from 'bun:test';
import {
  withChild,
  openOther,
  pickAgent,
  readyAgent,
} from '../app/child_window.tsx';
import { SummaryLine } from '../../../src/ui/background/Background.tsx';
import type { BackgroundItem } from '../../../src/ui/background/background.ts';
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
} from '../app/render.tsx';
import { withBackground } from './background_window.tsx';

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
  test('ended monitors stay absent across prompts in main and a child', () =>
    withChild(async (window) => {
      await readyAgent(window);
      await openOther(window);
      await send(window, 'monitors');
      await window.shows('background  2 monitors running');
      await send(window, 'monitorexit');
      await window.shows('background  2 monitors running');
      await window.shows('Received the message from CI run 4812');

      await pickAgent(window, 'other');
      await readyAgent(window);
      await send(window, 'monitor');
      await window.shows('background  3 monitors running');
      expect(window.frame()).not.toContain('1 monitor failed');
      await send(window, 'hello');
      await window.shows('background  3 monitors running');

      await pickAgent(window, 'main');
      await window.shows('background  3 monitors running');
      await send(window, 'hello');
      await window.shows('background  3 monitors running');
      expect(window.frame()).not.toContain('background  ✗');
      await pickAgent(window, 'other');
      await window.shows('background  3 monitors running');
    }));

  test('a child prompt keeps running monitors; closing that child removes its items without adding an ended row', () =>
    withBackground(
      async (window) => {
        await readyAgent(window);
        await send(window, 'monitorchild');
        await window.shows('background  2 monitors running');
        await send(window, 'monitorexit');
        await window.shows('Received the message from CI run 4812');
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
        await window.shows('Received the message from parser tests · monitor.');
        // A busy child's first x only arms closing; wait for its monitor reply.
        await until('parser idle before closing', () =>
          /❯ parser .*◦ idle/.test(window.frame()),
        );
        await window.press('x');
        await window.shows('background  1 monitor running');
        expect(window.frame()).not.toMatch(/^.*parser +fake.*$/m);
        expect(window.frame()).not.toContain('╭─ parser ─');
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

  test('a task asks without creating an agent row; its report replaces the ended row', () =>
    withBackground(async (window) => {
      await readyAgent(window);
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
      await window.shows(
        'Received the message from Fix the tokenizer · fake · report.',
      );
      await until(
        'reported task leaves without another prompt',
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
    await window.shows('│ Background · 2 in this session');
    await window.shows('Enter for details · x to stop · Esc to close');
    // A picker's frame above the prompt: the transcript, the prompt box,
    // the status line and the summary line stay, the summary's ❯ gone as
    // the keys are the frame's (CHD-462).
    expect(window.frame()).toContain('Two monitors are running.');
    expect(window.frame()).toContain('│ ›');
    expect(window.frame()).toContain('? for shortcuts');
    expect(window.frame()).toContain('    background  2 monitors running');
    expect(window.frame()).not.toContain('❯ background');
    expect(window.frame()).toMatch(
      /❯ dev server errors {2}monitor · m1 {2}running \d+s · 1 event +main/,
    );

    await window.press('j');
    await window.shows('❯ CI run 4812');
    // The last row stays the last.
    await window.press(DOWN);
    await window.press('x');
    // It leaves at once, the ❯ on the row above, as it was the last
    // (CHD-479).
    await window.shows('│ Background · 1 in this session');
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
    await window.shows('│ Background · 1 in this session');
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

test('x on a working task cancels its turn: it leaves, the last row closing the view, and its line says the x stopped it (CHD-482)', () =>
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
      await window.shows('■ Watch the build · task · stopped with x after');
      await until(
        'the view closed with its last row',
        () => !window.frame().includes('Background ·'),
      );
      expect(window.frame()).not.toContain('background  ');
    },
    { rows: 24, columns: 80 },
  ));

test("esc on its parent's later turn stops a task too: it leaves, and its line says the esc stopped it (CHD-482)", () =>
  withBackground(
    async (window) => {
      await ready(window);
      await send(window, 'tasklong');
      await window.shows('The build is being watched.');
      await window.shows('    background  1 task running');
      await send(window, 'slow');
      await window.shows('esc to interrupt');
      await window.press(ESC);
      await window.shows('■ Watch the build · task · stopped with esc after');
      await until(
        'the summary line gone',
        () => !window.frame().includes('background  '),
      );
    },
    { rows: 24, columns: 80 },
  ));

test('the view is modal: keys the window does not bind do nothing in it, and esc gives the window back as it was', () =>
  withBackground(async (window) => {
    await ready(window);
    await send(window, 'monitors');
    await window.shows('    background  2 monitors running');
    await window.press(DOWN);
    await window.press('\r');
    await window.shows('│ Background · 2 in this session');

    // ctrl+x w and ctrl+x c, which tabs had, are bound to nothing.
    await window.press(CTRL_X);
    await window.press('w');
    await window.press(CTRL_X);
    await window.press('c');
    await new Promise((resolve) => setTimeout(resolve, 300));
    expect(window.frame()).toContain('│ Background · 2 in this session');

    await window.press(ESC);
    await window.shows('❯ background  2 monitors running');
    expect(window.frame()).toContain('Two monitors are running.');
  }));
