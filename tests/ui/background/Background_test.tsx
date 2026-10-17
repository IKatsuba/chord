/**
 * The background's summary line in the window, on the fake agent and chord's
 * own server: counted by state, reached with ↓ as the list's last stop, and
 * cleared of what ended by the person's next prompt.
 */
import { expect, test } from 'bun:test';
import { serveChord } from '../../../src/server/server.ts';
import {
  DOWN,
  ESC,
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
