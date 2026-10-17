/**
 * The background view's enter, on the fake agent and chord's own server: the
 * view closes, the item's owner is picked and its transcript scrolls back to
 * the call that started the item.
 */
import { expect, test } from 'bun:test';
import { serveChord } from '../../../src/server/server.ts';
import {
  DOWN,
  promptRow,
  ready,
  send,
  until,
  type Window,
  withWindow,
} from '../app/render.tsx';

/** Runs `body` in a window with chord's server, the fake its one runtime. */
async function withBackground(body: (window: Window) => Promise<void>) {
  const server = serveChord();

  try {
    await withWindow(body, {
      server,
      runtimes: ['fake'],
      rows: 40,
      columns: 120,
    });
  } finally {
    await server.close();
  }
}

test("enter on a row closes the view and scrolls the transcript back so the item's call is its top line, the keys in the box", () =>
  withBackground(async (window) => {
    await ready(window);
    await send(window, 'monitors');
    await window.shows('Two monitors are running.');
    await window.shows(
      'Received the message from dev server errors · monitor.',
    );
    // Far more than a screen after the calls.
    await send(window, 'steps');
    await window.shows('150 steps read.');
    expect(!window.frame().includes('Monitor(CI run 4812)')).toBeTruthy();

    await window.press(DOWN);
    await window.press('\r');
    await window.shows(' Background · 2 in this tab');
    await window.press('j');
    await window.shows('❯ CI run 4812');
    await window.press('\r');
    await until('the call on top', () =>
      window.frame().split('\n')[0]!.includes('⏺ Monitor(CI run 4812)'),
    );
    await window.shows('lines below');

    // The box has the keys, and the view stays scrolled back meanwhile.
    await window.type('hello');
    await window.shows('› hello');
    expect(promptRow(window)).toContain('hello');
    expect(window.frame().split('\n')[0]).toContain('⏺ Monitor(CI run 4812)');
  }));

test("enter on a child's item picks the child and shows its call", () =>
  withBackground(async (window) => {
    await ready(window);
    await send(window, 'monitorchild');
    await window.shows('parser watches its tests; I watch the dev server.');
    await window.shows('    background  2 monitors running');
    await window.press(DOWN);
    await window.press(DOWN);
    await window.press(DOWN);
    await window.shows('❯ background');
    await window.press('\r');
    await window.shows('❯ dev server errors');

    while (!window.frame().includes('❯ parser tests')) {
      await window.press('j');
    }

    await window.press('\r');
    await window.shows('╭─ parser ');
    await window.shows('⏺ Monitor(parser tests)');
    expect(!window.frame().includes('❯ background')).toBeTruthy();
  }));

test("enter on the second task of a group puts that task's own row on top, not the group's header", () =>
  withBackground(async (window) => {
    await ready(window);
    await send(window, 'tasktwo');
    await window.shows('The build and the deploy are being watched.');
    await window.shows('Running 2 agents');
    // Far more than a screen after them, so the view cannot stop short.
    await send(window, 'steps');
    await window.shows('150 steps read.');

    await window.press(DOWN);
    await window.press('\r');
    await window.shows(' Background · 2 in this tab');
    await window.press('j');
    await window.shows('❯ Watch the deploy');
    await window.press('\r');
    await until('the second task on top', () =>
      /^ +└─ .*Watch the deploy/.test(window.frame().split('\n')[0]!),
    );
    expect(!window.frame().includes('Running 2 agents')).toBeTruthy();
    await window.shows('lines below');
  }));
