/**
 * Monitors in the window, on the fake agent and chord's own server: their
 * events as message rows, their rows in the list under the prompt, stopped
 * by `x`, and their rows again after a resume.
 */
import { expect, test } from 'bun:test';
import { serveChord } from '../../../src/server/server.ts';
import {
  DOWN,
  leader,
  ready,
  send,
  until,
  UP,
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

test("a monitor's event is a message row of its lines as printed, and the running monitors are rows under the prompt", () =>
  withMonitors(async (window) => {
    await started(window);

    const frame = window.frame();

    expect(frame).toContain('← from dev server errors · monitor\n');
    // Verbatim: the indented trace line is its own line, as printed.
    expect(frame).toContain(
      "   ⎿  ERROR [router] POST /login 500: Cannot read properties of undefined (reading 'trim')\n" +
        '          at validate (src/routes/login.tsx:41:22)\n',
    );
    // No agent rows without a child; the monitors alone, in start order.
    expect(!frame.includes('    main ')).toBeTruthy();
    expect(
      / {4}dev server errors {2}\$ sleep 1; .* {2}running \d+s · 1 event\n/.test(
        frame,
      ),
    ).toBeTruthy();
    expect(
      / {4}CI run 4812 {8}\$ sleep 600 +running \d+s · no events/.test(frame),
    ).toBeTruthy();
  }));

test('x stops the focused monitor at once: its row goes, its agent is told, and the ❯ goes up', () =>
  withMonitors(async (window) => {
    await started(window);

    // ↓ lands on the first monitor, which picks nothing.
    await window.press(DOWN);
    await window.shows('❯ dev server errors');
    await window.shows('↑ ↓ to pick · x to stop it · enter esc to go back');
    await window.press(DOWN);
    await window.shows('❯ CI run 4812');
    await window.press('x');
    await window.shows('← from CI run 4812 · monitor · stopped');
    await window.shows('The person stopped it after');
    await window.shows(
      'Received the message from CI run 4812 · monitor · stopped.',
    );
    await window.shows('❯ dev server errors');
    expect(!window.frame().includes('    CI run 4812 ')).toBeTruthy();

    // The last one stopped, the list goes and the box has the keys again.
    await window.press('x');
    await window.shows('← from dev server errors · monitor · stopped');
    await until(
      'the list gone',
      () => !window.frame().includes('dev server errors  $'),
    );
    await send(window, '/echo back in the box');
    await window.shows('back in the box');

    // ↑ from the first row hands the keys back too.
    await send(window, 'monitor');
    await window.shows('    dev server errors  $');
    await window.press(DOWN);
    await window.shows('❯ dev server errors');
    await window.press(UP);
    await until('the ❯ gone', () => !window.frame().includes('❯ dev server'));
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
    // Not restarted: no rows under the prompt.
    expect(!window.frame().includes('dev server errors  $')).toBeTruthy();
  }));
