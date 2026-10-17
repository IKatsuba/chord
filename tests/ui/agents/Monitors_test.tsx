/**
 * Monitors in the window, on the fake agent and chord's own server: their
 * events as message rows, and those rows again after a resume, which
 * restarts none of them.
 */
import { expect, test } from 'bun:test';
import { serveChord } from '../../../src/server/server.ts';
import {
  DOWN,
  leader,
  ready,
  send,
  type Window,
  withWindow,
} from '../app/render.tsx';

/** Runs `body` in a window with chord's server, the fake its one runtime. */
async function withMonitors(body: (window: Window) => Promise<void>) {
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

/** `monitors`, until the first monitor's event has been answered. */
async function started(window: Window): Promise<void> {
  await ready(window);
  await send(window, 'monitors');
  await window.shows('Two monitors are running.');
  await window.shows('Received the message from dev server errors · monitor.');
}

test("a monitor's event is a message row of its lines as printed, and the running monitors are counted under the prompt", () =>
  withMonitors(async (window) => {
    await started(window);

    const frame = window.frame();

    expect(frame).toContain('← from dev server errors · monitor\n');
    // Verbatim: the indented trace line is its own line, as printed.
    expect(frame).toContain(
      "   ⎿  ERROR [router] POST /login 500: Cannot read properties of undefined (reading 'trim')\n" +
        '          at validate (src/routes/login.tsx:41:22)\n',
    );
    // No agent rows without a child, and no rows of monitors: the summary
    // line counts them.
    expect(!frame.includes('    main ')).toBeTruthy();
    expect(frame).toContain('    background  2 monitors running');
    expect(!frame.includes('dev server errors  $')).toBeTruthy();
  }));

test("a resumed session draws its monitors' event rows again and names those it left running", () =>
  withMonitors(async (window) => {
    await started(window);
    await leader(window, 'c');
    await window.shows(' 2 fake ');
    await ready(window);
    await leader(window, '1');
    await leader(window, 'k');
    await window.type('/resume');
    await window.press('\r');
    await window.shows('just now  monitors');

    while (!/❯ \d\. just now {2}monitors/.test(window.frame())) {
      await window.press(DOWN);
    }

    await window.press('\r');
    await window.shows(
      'dev server errors and CI run 4812 were running when this session was ' +
        'left and are not restarted',
    );
    expect(window.frame()).toContain('← from dev server errors · monitor\n');
    expect(window.frame()).toContain(
      '       at validate (src/routes/login.tsx:41:22)\n',
    );
    // Not restarted: nothing under the prompt counts them.
    expect(!window.frame().includes('background  ')).toBeTruthy();
  }));
