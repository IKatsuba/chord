/**
 * A monitor's detail in the background view: its keys, an ended one kept
 * across keys and inputs, a long stop refusal under it, and a task that
 * ends while its detail is open (CHD-481, CHD-482).
 */
import { describe, expect, spyOn, test } from 'bun:test';
import assert from 'node:assert/strict';
import { fakeAgentCommand } from '../../fixtures/fake.ts';
import { serveChord } from '../../../src/server/server.ts';
import {
  DOWN,
  END,
  ESC,
  ready,
  send,
  until,
  UP,
  type Window,
  withWindow,
} from '../app/render.tsx';
import { withBackground } from './background_window.tsx';

describe("a monitor's detail in the window (CHD-481)", () => {
  const LEFT = '\x1b[D';
  const PAGE_DOWN = '\x1b[6~';

  /** Opens the view over the fake's two monitors, the first's error in. */
  async function opened(window: Window) {
    await ready(window);
    await send(window, 'monitors');
    await window.shows(
      'Received the message from dev server errors · monitor.',
    );
    await window.press(DOWN);
    await window.press('\r');
    await window.shows('Background · 2 in this tab');
  }

  test('enter opens it in place of the rows; ↓ ↑ step to the others, ← and esc go back to the rows, the ❯ on its item', () =>
    withBackground(async (window) => {
      await opened(window);
      await window.shows('Enter for details · x to stop · Esc to close');
      await window.press('\r');
      await window.shows('Background · m1, 1 of 2');
      await window.shows('$ sleep 1; echo "ERROR [router]');
      await window.shows('← ERROR [router] POST /login 500');
      await window.shows(
        'Enter to go to its call · ↑ ↓ for the others · x to stop · Esc ← to go back',
      );
      expect(window.frame()).not.toContain('❯ dev server errors');

      await window.press(DOWN);
      await window.shows('Background · m2, 2 of 2');
      await window.shows('← no events yet');
      await window.press(LEFT);
      await window.shows('❯ CI run 4812');
      await window.shows('Background · 2 in this tab');

      // ← on the rows does nothing; esc there closes the view.
      await window.press(LEFT);
      await window.press(UP);
      await window.shows('❯ dev server errors');
      await window.press('\r');
      await window.shows('Background · m1, 1 of 2');
      await window.press(ESC);
      await window.shows('Background · 2 in this tab');
      await window.press(ESC);
      await until(
        'the view closed',
        () => !window.frame().includes('in this tab'),
      );
    }));

  test('x stops it and it stays, ended, with nothing left to stop, until it is left; then it is gone', () =>
    withBackground(async (window) => {
      await opened(window);
      await window.press('\r');
      await window.shows('Background · m1, 1 of 2');
      await window.press('x');
      await window.shows('Background · m1, 1 of 2 · ended');
      await window.shows('■ stopped after');
      await window.shows(
        'Enter to go to its call · ↑ ↓ for the others · Esc ← to go back',
      );
      await window.press(ESC);
      await window.shows('Background · 1 in this tab');
      await window.shows('❯ CI run 4812');
      expect(window.frame()).not.toContain('dev server errors   ');
    }));

  test('↓ on an ended one steps on, its item gone; on the last one left, it closes the frame (Q126)', () =>
    withBackground(async (window) => {
      await opened(window);
      await window.press('\r');
      await window.press('x');
      await window.shows('Background · m1, 1 of 2 · ended');
      await window.press(DOWN);
      await window.shows('Background · m2, 1 of 1');
      await window.press('x');
      await window.shows('Background · m2, 1 of 1 · ended');
      await window.press(DOWN);
      await until(
        'the frame closed',
        () => !window.frame().includes('Background ·'),
      );
    }));

  test("a monitor that reaches its timeout reads as a stop in its own words, not a failure (CHD-482's Q85)", () =>
    withBackground(async (window) => {
      await ready(window);
      await send(window, 'monitortimeout');
      await window.shows('The heartbeat stops itself in five seconds.');
      await window.press(DOWN);
      await window.press('\r');
      await window.shows('Background · 1 in this tab');
      await window.press('\r');
      await window.shows('Background · m1, 1 of 1 · ended');
      await window.shows('■ timed out after 5s · 1 event');
      await window.shows(
        'Timed out after 5s (timeout_ms 5000); chord stopped it.',
      );
      expect(window.frame()).not.toContain('✗');
    }));

  test('taller than its room at 80×24, it scrolls by a page', () =>
    withBackground(
      async (window) => {
        await opened(window);
        await window.press('\r');
        await window.shows('Background · m1, 1 of 2');
        await window.shows('lines below · pagedown to scroll');
        await window.press(PAGE_DOWN);
        await window.shows('lines above · pageup to scroll');
      },
      { rows: 24, columns: 80 },
    ));
});

describe('CHD-481 U3 tester: ended detail keeps identity across keys and resize', () => {
  for (const [columns, rows] of [
    [80, 24],
    [120, 40],
  ] as const) {
    test(`repeated x leaves its neighbour running and ↑ returns to a whole item's detail at ${columns} columns`, () =>
      withBackground(
        async (window) => {
          await ready(window);
          await send(window, 'monitors');
          await window.shows(
            'Received the message from dev server errors · monitor.',
          );
          await window.press(DOWN);
          await window.press('\r');
          await window.shows('Background · 2 in this session');
          await window.press('\r');
          await window.shows('Background · m1, 1 of 2');
          await window.press('j');
          await window.shows('Background · m2, 2 of 2');
          await window.press('x');
          await window.shows('Background · m2, 2 of 2 · ended');
          await window.press('x');
          await window.resize(
            columns === 80
              ? { columns: 120, rows: 40 }
              : { columns: 80, rows: 24 },
          );
          await window.shows('Background · m2, 2 of 2 · ended');
          expect(window.frame()).not.toContain('x to stop');
          await window.press(UP);
          await window.shows('Background · m1, 1 of 1');
          expect(window.frame()).not.toContain('· ended');
          await window.press('\x1b[D');
          await window.shows('❯ dev server errors');
          await window.shows('Background · 1 in this session');
          expect(window.frame()).not.toMatch(/^│ .*CI run 4812/m);
          await window.press(ESC);
          await until(
            'the background frame closed',
            () => !window.frame().includes('Background ·'),
          );
        },
        { columns, rows },
      ));
  }
});

describe('CHD-481 U3 tester: a modal input preserves an ended detail', () => {
  async function inRunningWindow(
    body: (window: Window) => Promise<void>,
    size: { columns: number; rows: number },
  ) {
    const server = serveChord();
    const agentCommand = fakeAgentCommand(undefined, '--step-ms', '30');

    try {
      await withWindow(body, {
        server,
        runtimes: ['fake'],
        agentCommand,
        startupOf: () => ({ agentCommand }),
        ...size,
      });
    } finally {
      await server.close();
    }
  }

  for (const [columns, rows] of [
    [80, 24],
    [120, 40],
  ] as const) {
    test(`a cancelled link restores the same ended monitor at ${columns} columns`, () =>
      inRunningWindow(
        async (window) => {
          await ready(window);
          await send(window, 'monitors');
          await window.shows(
            'Received the message from dev server errors · monitor.',
          );
          await send(window, 'slow');
          await window.shows('Working');
          await window.press(DOWN);
          await window.press('\r');
          await window.press('j');
          await window.shows('❯ CI run 4812');
          await window.press('\r');
          await window.shows('Background · m2, 2 of 2');
          await window.press('x');
          await window.shows('Background · m2, 2 of 2 · ended');

          const session = window.session();

          assert(session);

          const controller = new AbortController();
          const response = session.elicitations.handler(
            {
              sessionId: session.id,
              mode: 'url',
              message: 'Link while reading an ended monitor',
              url: 'https://example.com/monitor',
              elicitationId: 'detail-link',
            },
            controller.signal,
          );

          try {
            await window.shows('❯ 1. Open in the browser');
            expect(window.frame()).not.toContain('Background ·');
            await window.press(ESC);
            expect(await response).toMatchObject({ action: 'cancel' });
            await window.shows('Background · m2, 2 of 2 · ended');
            expect(window.frame()).not.toContain('x to stop');
            await window.press(UP);
            await window.shows('Background · m1, 1 of 1');
          } finally {
            controller.abort();
          }
        },
        { columns, rows },
      ));
  }
});

describe('a long stop refusal under a detail (CHD-481, Q128)', () => {
  const PAGE_DOWN = '\x1b[6~';
  const HOME = '\x1b[H';
  const body = (window: Window) =>
    window
      .frame()
      .split('\n')
      .filter((line) => line.startsWith('│'))
      .join('\n');

  test('without one, pgup pgdn home end page the detail', () =>
    withBackground(
      async (window) => {
        await ready(window);
        await send(window, 'monitors');
        await window.shows(
          'Received the message from dev server errors · monitor.',
        );
        await window.press(DOWN);
        await window.press('\r');
        await window.shows('Background · 2 in this tab');
        await window.press('\r');
        await window.shows('Background · m1, 1 of 2');
        await window.press(PAGE_DOWN);
        await until(
          'the description paged away',
          () => !body(window).includes('dev server errors'),
        );
        await window.press(HOME);
        await until('home, its description', () =>
          body(window).includes('dev server errors'),
        );
        await window.press(END);
        await until('end, its last batch', () =>
          body(window).includes('at validate'),
        );
      },
      { columns: 80, rows: 24 },
    ));

  test('the detail gives way to its first line and the refusal alone takes pgup pgdn home end; another item clears it', () =>
    withBackground(
      async (window) => {
        await ready(window);
        await send(window, 'monitor');
        await window.shows('I will hear from the dev server when it errs.');
        await send(window, 'claudebackground');
        await window.shows("main's 2 agents running");

        const session = window.session();

        assert(session !== undefined);

        const stop = spyOn(session, 'stopSubagent').mockRejectedValue(
          new Error(
            [
              'Broken pipe',
              ...Array.from(
                { length: 29 },
                (_, at) => `refusal line ${at + 1}`,
              ),
              'REFUSAL TAIL',
            ].join('\n'),
          ),
        );

        try {
          await window.press(DOWN);
          await window.press('\r');
          await window.shows('Background · 3 in this tab');
          await window.press('\r');
          await window.shows('Background · m1, 1 of 3');
          await window.press(DOWN);
          await window.shows('Background · 2 of 3');
          await window.press('x');
          await window.shows('could not stop: Broken pipe');
          // The detail is its first line alone, the refusal the rest.
          await window.shows('lines below · pagedown to scroll');

          const shown = body(window).split('\n');

          expect(shown[2]).toContain('Run the test suite');
          expect(shown[3]).toMatch(/^│ *│$/);
          expect(shown[4]).toContain('could not stop: Broken pipe');

          await window.press(PAGE_DOWN);
          await window.shows('lines above · pageup to scroll');
          expect(body(window)).toContain('Run the test suite');
          await window.press(END);
          await window.shows('REFUSAL TAIL');
          expect(body(window)).toContain('Run the test suite');
          await window.press(HOME);
          await window.shows('could not stop: Broken pipe');
          expect(body(window)).not.toContain('lines above');

          // Another item clears the refusal; the detail has its room back.
          await window.press(UP);
          await window.shows('Background · m1, 1 of 3');
          await until(
            'the refusal gone',
            () => !window.frame().includes('could not stop'),
          );
          await window.shows('$ sleep 1');
        } finally {
          stop.mockRestore();
        }
      },
      { columns: 80, rows: 24 },
    ));
});

describe('CHD-481 Q128 tester: rebound detail boundaries', () => {
  test('rebound top and bottom page the detail while unbound Home and End do nothing', async () => {
    const server = serveChord();

    try {
      await withWindow(
        async (window) => {
          await ready(window);
          await send(window, 'monitors');
          await window.shows(
            'Received the message from dev server errors · monitor.',
          );
          await window.press(DOWN);
          await window.press('\r');
          await window.shows('Background · 2 in this session');
          await window.press('\r');
          await window.shows('Background · m1, 1 of 2');

          const body = () =>
            window
              .frame()
              .split('\n')
              .filter((line) => line.startsWith('│'))
              .join('\n');

          await window.press('\x1b[6~');
          await until(
            'the description paged away',
            () => !body().includes('dev server errors'),
          );
          await window.press('\x1b[H');
          expect(body()).not.toContain('dev server errors');
          await window.press('\x02');
          await until('rebound top returns the description', () =>
            body().includes('dev server errors'),
          );
          await window.press(END);
          expect(body()).toContain('dev server errors');
          await window.press('\x05');
          await until('rebound bottom reaches the batch', () =>
            /^│ +at validate \(src\/routes\/login\.tsx:41:22\)/m.test(body()),
          );
        },
        {
          server,
          runtimes: ['fake'],
          columns: 80,
          rows: 24,
          keybindings: JSON.stringify({
            bindings: [
              {
                context: 'Scroll',
                bindings: {
                  home: null,
                  end: null,
                  'ctrl+b': 'scroll:top',
                  'ctrl+e': 'scroll:bottom',
                },
              },
            ],
          }),
        },
      );
    } finally {
      await server.close();
    }
  });
});

test('a task that ends while its detail is open stays in it until left, then leaves (CHD-482, Q136)', () =>
  withBackground(
    async (window) => {
      await ready(window);
      await send(window, 'monitor');
      await window.shows('I will hear from the dev server when it errs.');
      await send(window, 'tasklong');
      await window.shows('The build is being watched.');
      await window.press(DOWN);
      await window.press('\r');
      await window.shows('Background · 2 in this tab');
      await window.press('\r');
      await window.shows('Background · m1, 1 of 2');
      await window.press(DOWN);
      await window.shows('Background · 2 of 2');
      await window.press('x');
      await window.shows('Background · 2 of 2 · ended');
      await window.press(ESC);
      await window.shows('Background · 1 in this tab');
      await window.shows('■ Watch the build · task · stopped with x after');
    },
    { rows: 40, columns: 120 },
  ));

describe('CHD-482 U3 tester: a later turn stops its running task with esc', () => {
  for (const [columns, rows] of [
    [80, 24],
    [120, 40],
  ] as const) {
    test(`the task leaves and its stop line appears once at ${columns} columns`, async () => {
      const server = serveChord();
      const command = fakeAgentCommand(undefined, '--step-ms 30');

      try {
        await withWindow(
          async (window) => {
            await ready(window);
            await send(window, 'tasklong');
            await window.shows('The build is being watched.');
            await until('the announcing turn is idle', () =>
              /^ {2}1 agent still running/m.test(window.frame()),
            );
            await send(window, 'slow');
            await window.shows('esc to interrupt');
            await window.press(ESC);
            await window.shows('Interrupted by user');

            const line = '■ Watch the build · task · stopped with esc after';

            await window.shows(line);
            await until(
              'the task leaves the summary',
              () => !window.frame().includes('background  '),
            );
            expect(window.frame().split(line)).toHaveLength(2);
            expect(window.frame()).not.toContain('stopped with x');
            await send(window, 'hello');
            await window.shows('came in chunks.');
            expect(window.frame().split(line)).toHaveLength(2);
          },
          {
            server,
            runtimes: ['fake'],
            rows,
            columns,
            agentCommand: command,
            startupOf: () => ({ agentCommand: command }),
          },
        );
      } finally {
        await server.close();
      }
    });
  }
});
