/**
 * The background view's enter, on the fake agent and chord's own server: the
 * view closes, the item's owner is picked and its transcript scrolls back to
 * the call that started the item.
 */
import { describe, expect, spyOn, test } from 'bun:test';
import assert from 'node:assert/strict';
import { readFile, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { fakeAgentCommand } from '../../fixtures/fake.ts';
import { serveChord } from '../../../src/server/server.ts';
import {
  DOWN,
  END,
  ESC,
  promptRow,
  ready,
  send,
  until,
  UP,
  type Window,
  withWindow,
} from '../app/render.tsx';

/**
 * Runs `body` in a window with chord's server, the fake its one runtime,
 * 120×40 unless `size` says otherwise.
 */
async function withBackground(
  body: (window: Window) => Promise<void>,
  size = { rows: 40, columns: 120 },
) {
  const server = serveChord();

  try {
    await withWindow(body, {
      server,
      runtimes: ['fake'],
      ...size,
    });
  } finally {
    await server.close();
  }
}

test("enter in a monitor's detail closes the view and scrolls the transcript back so its call is the top line, the keys in the box", () =>
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
    // Enter on a monitor's row opens its detail; enter in it, the call
    // (CHD-481).
    await window.press('\r');
    await window.shows('Background · m2, 2 of 2');
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
    // Its detail first, then its call from there (CHD-487).
    await window.press('\r');
    await window.shows('Enter to go to its call');
    await window.press('\r');
    await until('the second task on top', () =>
      /^ +└─ .*Watch the deploy/.test(window.frame().split('\n')[0]!),
    );
    expect(!window.frame().includes('Running 2 agents')).toBeTruthy();
    await window.shows('lines below');
  }));

describe('CHD-424 tester: call navigation edges', () => {
  for (const columns of [80, 120]) {
    test(`a lone task jump at ${columns} columns holds while typing and End returns to the tail with the draft intact`, () =>
      withBackground(async (window) => {
        await window.resize({ rows: 24, columns });
        await ready(window);
        await send(window, 'tasklong');
        await window.shows('background  1 task running');
        await send(window, 'steps');
        await window.shows('150 steps read.');
        expect(window.frame()).not.toContain('Agent(Watch the build)');
        await window.press(DOWN);
        await window.press('\r');
        await window.shows('Background · 1 in this tab');
        await window.press('\r');
        await window.shows('Enter to go to its call');
        await window.press('\r');
        await until('the lone task call on the first line', () =>
          window.frame().split('\n')[0]!.includes('⏺ Agent(Watch the build)'),
        );
        await window.type('draft stays');
        expect(promptRow(window)).toContain('draft stays');
        expect(window.frame().split('\n')[0]).toContain(
          'Agent(Watch the build)',
        );
        await window.press(END);
        await window.shows('150 steps read.');
        expect(promptRow(window)).toContain('draft stays');
        expect(window.frame()).not.toContain('lines below');
      }));
  }

  test('enter picks parser from a different picked child and mounts parser’s old call on top at 80x24', () =>
    withBackground(async (window) => {
      await window.resize({ rows: 24, columns: 80 });
      await ready(window);
      await send(window, 'monitorchild');
      await window.shows('background  2 monitors running');
      await window.press(DOWN);
      await window.press(DOWN);
      await window.shows('❯ parser ');
      await window.press('\r');
      await send(window, 'steps');
      await window.shows('150 steps read.');
      await window.press(DOWN);
      await window.press(UP);
      await window.shows('❯ main ');
      await window.press('\r');
      await send(window, 'agents');
      await window.shows('Waiting on parser.');
      await window.press(DOWN);
      await window.press(DOWN);
      await window.press(DOWN);
      await window.press(DOWN);
      await window.shows('❯ docs ');
      await window.press(DOWN);
      await window.shows('❯ background');
      expect(window.frame()).toContain('╭─ docs ');
      await window.press('\r');
      await window.shows('Background · 2 in this tab');

      for (
        let index = 0;
        index < 2 && !window.frame().includes('❯ parser tests');
        index++
      ) {
        await window.press('j');
      }

      await window.shows('❯ parser tests');
      await window.press('\r');
      await window.shows('Background · m1, 2 of 2');
      await window.press('\r');
      await window.shows('╭─ parser ');
      await until('parser’s own monitor call at the top', () =>
        window.frame().split('\n')[0]!.includes('⏺ Monitor(parser tests)'),
      );
      await window.type('parser draft');
      expect(promptRow(window)).toContain('parser draft');
      expect(window.frame()).not.toContain('Do you want to proceed?');
    }));
});

describe('CHD-424 tester: rebound background stop', () => {
  test('the rebound key leaves the summary alone, stops view items, and closes an agent; shift arrows leave the view focus alone', async () => {
    const server = serveChord();

    try {
      await withWindow(
        async (window) => {
          await ready(window);
          await send(window, 'monitorchild');
          await window.shows('background  2 monitors running');
          await window.press(DOWN);
          await window.press(DOWN);
          await window.press(DOWN);
          await window.shows('❯ background');
          await window.press('z');
          await window.shows('❯ background  2 monitors running');
          await window.press('\r');
          await window.shows('❯ dev server errors');
          await window.press('\x1b[1;2B');
          expect(window.frame()).toContain('❯ dev server errors');
          await window.press('x');
          expect(window.frame()).not.toContain('■ stopped after');
          await window.press('z');
          await window.shows('❯ parser tests');
          await window.press('\x1b[1;2A');
          expect(window.frame()).toContain('❯ parser tests');
          await window.press('z');
          await until(
            'last monitor closes view',
            () => !window.frame().includes('Background ·'),
          );
          expect(window.frame()).not.toContain('background  ');
          await window.press(DOWN);
          await window.press(DOWN);
          await window.shows('❯ parser ');
          await window.press('z');
          await until(
            'child closed',
            () => !window.frame().includes('❯ parser '),
          );
          expect(window.frame()).not.toContain('background  ');
        },
        {
          server,
          runtimes: ['fake'],
          rows: 24,
          columns: 80,
          keybindings: JSON.stringify({
            bindings: [
              {
                context: 'Agents',
                bindings: {
                  x: null,
                  z: 'agents:close',
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

test('a Claude agent that takes a while to stop reads stopping until it says it stopped, then leaves, and a second x changes nothing', () =>
  withWindow(
    async (window) => {
      await send(window, 'claudeslowstop');
      await window.shows("background  main's 2 agents running");
      await window.press(DOWN);
      await window.press('\r');
      await window.shows('❯ Run the test suite');
      await window.press('x');
      await window.shows('■ stopping');
      await window.press('x');
      expect(window.frame()).toContain('■ stopping');
      expect(window.frame()).not.toContain('could not stop');
      // Once it says it stopped, its row leaves (CHD-479).
      await until(
        'its row gone',
        () => !window.frame().includes('Run the test suite  agent'),
      );
      expect(window.frame()).not.toContain('■ stopped after');
    },
    { rows: 24, columns: 80 },
  ));

describe('CHD-2 tester: pending stops and deferred refusals in the window', () => {
  for (const [columns, rows] of [
    [120, 40],
    [80, 24],
  ] as const) {
    test(`repeated x sends one actual child notice while the gate holds stopping at ${columns} columns`, () =>
      withWindow(
        async (window) => {
          await send(window, 'claudebackground');
          await window.shows("background  main's 2 agents running");
          await window.press(DOWN);
          await window.press('\r');
          await window.shows('❯ Run the test suite');
          await window.press('x');
          await window.shows('■ stopping');

          const log = join(window.dir, '.fake-gate', 'stops');

          await until(
            'the child stop notice recorded',
            async () =>
              (await readFile(log, 'utf8').catch(() => '')).trim() !== '',
          );
          await window.press('x');
          await window.press('x');

          const ids = (await readFile(log, 'utf8')).trim().split('\n');

          expect(ids).toHaveLength(1);
          expect(ids[0]).not.toBe(window.session()?.id);
          expect(window.frame()).toContain('■ stopping');
          await window.press(ESC);
          await window.shows("background  main's 2 agents running");
          await window.press('\r');
          await window.shows('■ stopping');
          await writeFile(join(window.dir, '.fake-gate', 'stop-release'), '');
          await until(
            'stopped agent row leaves',
            () => !window.frame().includes('❯ Run the test suite'),
          );
          expect(window.frame()).not.toContain('■ stopped after');
          expect(
            (await readFile(log, 'utf8')).trim().split('\n'),
          ).toStrictEqual(ids);
        },
        {
          columns,
          rows,
          agentCommand: fakeAgentCommand(undefined, '--stop-gate'),
        },
      ));

    test(`a deferred refusal rolls back and stale replies after cursor/view changes stay silent at ${columns} columns`, () =>
      withWindow(
        async (window) => {
          await send(window, 'claudebackground');
          await window.shows("background  main's 2 agents running");

          const session = window.session();

          assert(session !== undefined);

          const notices = Array.from({ length: 3 }, () =>
            Promise.withResolvers<void>(),
          );
          let calls = 0;
          const stop = spyOn(session, 'stopSubagent').mockImplementation(() => {
            const pending = notices[calls++];

            assert(pending !== undefined);

            return pending.promise;
          });

          try {
            await window.press(DOWN);
            await window.press('\r');
            await window.shows('❯ Run the test suite');
            await window.press('x');
            await window.shows('■ stopping');
            await window.press('x');
            expect(calls).toBe(1);
            notices[0]!.reject(
              new Error('Broken pipe\nprivate transport detail'),
            );
            await window.shows('could not stop: Broken pipe');
            expect(window.frame()).toContain('private transport detail');
            expect(window.frame()).toMatch(
              /could not stop: Broken pipe[^\n]*\n[^\n]*private transport detail/,
            );
            expect(window.frame()).not.toContain('■ stopping');
            await window.press('x');
            await window.shows('■ stopping');
            expect(calls).toBe(2);
            await window.press('j');
            await window.press('k');
            notices[1]!.reject(new Error('old cursor refusal'));
            await until(
              'the second stop rolled back',
              () => !window.frame().includes('■ stopping'),
            );
            expect(window.frame()).not.toContain('could not stop');
            await window.press('x');
            await window.shows('■ stopping');
            expect(calls).toBe(3);
            await window.press(ESC);
            await window.shows('❯ background');
            await window.press('\r');
            await window.shows('■ stopping');
            notices[2]!.reject(new Error('old view refusal'));
            await until(
              'the third stop rolled back',
              () => !window.frame().includes('■ stopping'),
            );
            expect(window.frame()).not.toContain('could not stop');
          } finally {
            for (const notice of notices) {
              notice.resolve();
            }

            stop.mockRestore();
          }
        },
        {
          columns,
          rows,
          agentCommand: fakeAgentCommand(undefined, '--step-ms', '50'),
        },
      ));
  }

  test('natural wire completion wins while the stop is held and shutdown needs no release', () =>
    withWindow(
      async (window) => {
        await send(window, 'claudebackground');
        await window.shows("background  main's 2 agents running");
        await window.press(DOWN);
        await window.press('\r');
        await window.shows('❯ Run the test suite');
        await window.press('x');
        await window.shows('■ stopping');
        await until(
          'natural completion removes last row and summary',
          () =>
            !window.frame().includes('Background ·') &&
            !window.frame().includes('background  '),
        );
        expect(window.frame()).not.toContain('■ stopping');
        await window.type('back in prompt');
        expect(promptRow(window)).toContain('back in prompt');
        expect(
          (await readFile(join(window.dir, '.fake-gate', 'stops'), 'utf8'))
            .trim()
            .split('\n'),
        ).toHaveLength(1);
        // withWindow closes with no stop-release and proves every process gone.
      },
      {
        rows: 24,
        columns: 80,
        agentCommand: fakeAgentCommand(undefined, '--stop-gate'),
      },
    ));
});

describe('CHD-473 T4 tester: error paging through the window', () => {
  for (const [columns, rows, rebound] of [
    [46, 24, false],
    [80, 24, false],
    [46, 24, true],
    [120, 40, true],
  ] as const) {
    test(`every refused-stop line is reachable, reset and capped at ${columns} columns with ${rebound ? 'rebound' : 'default'} paging`, async () => {
      const server = serveChord();
      const details = Array.from(
        { length: 16 },
        (_, index) => `Detail ${String(index).padStart(2, '0')} 日本語`,
      );
      const down = rebound ? '\x0e' : '\x1b[6~';
      const up = rebound ? '\x10' : '\x1b[5~';

      try {
        await withWindow(
          async (window) => {
            await ready(window);
            await send(window, 'claudebackground');
            await window.shows("background  main's 2 agents running");

            const session = window.session();

            assert(session);

            const stop = spyOn(session, 'stopSubagent')
              .mockRejectedValueOnce(
                new Error(['Broken pipe', ...details].join('\n')),
              )
              .mockRejectedValueOnce(
                new Error('Replacement refusal\nFinal detail'),
              );
            const cap = () => {
              const lines = window.frame().split('\n');
              const top = lines.findIndex(
                (line, index) =>
                  line.startsWith('╭') &&
                  lines[index + 1]?.includes('Background'),
              );
              const bottom = lines.findIndex(
                (line, index) => index > top && line.startsWith('╰'),
              );

              expect(top).toBeGreaterThanOrEqual(0);
              expect(bottom - top + 1).toBeLessThanOrEqual(
                Math.floor(window.frame().split('\n').length / 2),
              );
              expect(window.frame()).toContain('❯ Run the test suite');
            };

            try {
              await window.press(DOWN);
              await window.press('\r');
              await window.shows('❯ Run the test suite');
              await window.press('x');
              await window.shows('could not stop: Broken pipe');
              await window.shows(
                rebound ? 'ctrl+n to scroll' : 'pagedown to scroll',
              );
              cap();

              if (rebound) {
                await window.press('\x1b[6~');
                expect(window.frame()).toContain('could not stop: Broken pipe');
                expect(window.frame()).not.toContain('lines above');
              }

              const seen = new Set<string>();

              for (let page = 0; page < 20; page++) {
                const frame = window.frame();

                for (const detail of details) {
                  if (frame.includes(detail)) {
                    seen.add(detail);
                  }
                }

                cap();

                if (!frame.includes('lines below')) {
                  break;
                }

                await window.press(down);
                await until(
                  'the next error page',
                  () => window.frame() !== frame,
                );
              }

              expect([...seen].sort()).toEqual([...details].sort());
              expect(window.frame()).toContain('lines above');
              await window.resize({ columns: columns + 2, rows: 20 });
              cap();

              for (
                let page = 0;
                page < 20 && window.frame().includes('lines above');
                page++
              ) {
                const frame = window.frame();

                await window.press(up);
                await until(
                  'the previous error page',
                  () => window.frame() !== frame,
                );
              }

              await window.shows('could not stop: Broken pipe');
              await window.press(down);
              await window.shows('lines above');
              await window.press('x');
              await window.shows('Replacement refusal');
              await window.shows('Final detail');
              expect(window.frame()).not.toContain('lines above');
              expect(window.frame()).not.toContain('Detail 15');
              cap();
              await window.press('j');
              await until(
                'moving clears the refusal',
                () => !window.frame().includes('Replacement refusal'),
              );
              await window.press(ESC);
              await window.press(down);
              expect(window.frame()).not.toContain('Final detail');
              expect(stop).toHaveBeenCalledTimes(2);
            } finally {
              stop.mockRestore();
            }
          },
          {
            columns,
            rows,
            server,
            runtimes: ['fake'],
            agentCommand: fakeAgentCommand(undefined, '--stop-gate'),
            ...(rebound
              ? {
                  keybindings: JSON.stringify({
                    bindings: [
                      {
                        context: 'Scroll',
                        bindings: {
                          pageup: null,
                          'shift+pageup': null,
                          pagedown: null,
                          'shift+pagedown': null,
                          'ctrl+n': 'scroll:pageDown',
                          'ctrl+p': 'scroll:pageUp',
                        },
                      },
                    ],
                  }),
                }
              : {}),
          },
        );
      } finally {
        await server.close();
      }
    });
  }
});

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
          await window.shows('Background · 2 in this tab');
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
          await window.shows('Background · 1 in this tab');
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
          await window.shows('Background · 2 in this tab');
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

describe("an agent's or a task's row opens its detail (CHD-487)", () => {
  test("enter on an agent's row opens its detail, and enter in it goes to its call (Q134)", () =>
    withWindow(async (window) => {
      await send(window, 'claudebackground');
      await window.shows("background  main's 2 agents running");
      await window.press(DOWN);
      await window.press('\r');
      await window.shows('❯ Run the test suite');
      await window.shows('Enter for details · x to stop · Esc to close');
      await window.press('\r');
      await window.shows('Background · ');
      await window.shows(
        'Enter to go to its call · ↑ ↓ for the others · x to stop · Esc ← to go back',
      );
      await window.press('\r');
      await until(
        'the view closed on its call',
        () => !window.frame().includes('Background · '),
      );
    }));

  test("codex's subagents, which offer no cancel, are rows too, and x on one says so (Q135)", () =>
    withWindow(async (window) => {
      await send(window, 'subagent');
      await window.shows('background ');
      await window.press(DOWN);
      await window.press('\r');
      await window.shows('❯ ');
      await window.press('x');
      await window.shows('this agent offers no stop');
    }));
});

describe('CHD-487 U1 tester: detail stop and return keys', () => {
  for (const [columns, rows] of [
    [80, 24],
    [120, 40],
  ] as const) {
    test(`a stopped agent detail stays until left and x cannot stop it twice at ${columns} columns`, () =>
      withWindow(
        async (window) => {
          await send(window, 'claudeslowstop');
          await window.shows("background  main's 2 agents running");
          await window.press(DOWN);
          await window.press('\r');
          await window.shows('❯ Run the test suite');
          await window.press('\r');
          await window.shows('Enter to go to its call');
          await window.press('x');
          await window.shows('· ended');
          await window.shows('■ stopped after');
          expect(window.frame()).not.toContain('x to stop');
          await window.press('x');
          expect(window.frame()).toContain('· ended');
          await window.press('\x1b[D');
          await until(
            'the ended detail released',
            () => !window.frame().includes('· ended'),
          );
          expect(window.frame()).not.toContain('❯ Run the test suite');
        },
        { columns, rows },
      ));
  }
});

describe("an agent's detail draws its whole task and its work, following its end (CHD-487 U2)", () => {
  for (const [columns, rows] of [
    [120, 40],
    [80, 24],
  ] as const) {
    test(`pinned description and state, the task after ›, the work as its block draws it, kept once ended, at ${columns}x${rows}`, () =>
      withWindow(
        async (window) => {
          const frame = () =>
            window.frame().slice(window.frame().indexOf('Background · '));

          await send(window, 'claudebackground');
          await window.shows("background  main's 2 agents running");
          await window.press(DOWN);
          await window.press('\r');
          await window.shows('❯ Run the test suite');
          await window.press('\r');
          await window.shows('Background · 1 of 1');
          expect(frame()).toContain('Run the test suite');
          expect(frame()).toMatch(/running \d+s · 1 tool use · main/);
          await window.shows('⏺ Bash(bun test)');
          // Ended with its detail open: kept, its end in CHD-2's words, at
          // the end of its work.
          await window.shows('Background · 1 of 1 · ended');
          await window.shows('⏺ Every test passed.');
          expect(frame()).toMatch(/✓ done in \d+s · 1 tool use · main/);

          if (rows === 24) {
            // Too tall for its room: opened at its end, paged up to the
            // task, and end follows again.
            expect(frame()).toContain('── ↑ 2 lines above');
            await window.press('\x1b[5~');
            await window.shows(
              '› Run bun test in the background and report what fails.',
            );
            await window.shows('── ↓ 2 lines below');
            await window.press(END);
            await window.shows('── ↑ 2 lines above');
            expect(frame()).toContain('⏺ Every test passed.');
          } else {
            expect(frame()).toContain(
              '› Run bun test in the background and report what fails.',
            );
          }
        },
        { rows, columns },
      ));
  }

  test("a task's detail says its kind among its state, and its work", () =>
    withBackground(async (window) => {
      await ready(window);
      await send(window, 'tasklong');
      await window.shows('The build is being watched.');
      await window.press(DOWN);
      await window.press('\r');
      await window.shows('❯ Watch the build');
      await window.press('\r');
      await window.shows('Background · 1 of 1');
      await window.shows('· task · fake · main');
      await window.shows('⏺ Watching the build.');
    }));
});

test('a detail pins its name on one line, cut with … when longer, and its whole task after › only when cut (CHD-487)', () =>
  withWindow(async (window) => {
    await send(window, 'subagent');
    await window.shows('Do you want to proceed?');
    await window.press('1');
    await window.shows('background ');
    await window.press(DOWN);
    await window.press('\r');
    await window.shows('❯ ');
    await window.press('\r');
    await window.shows('Background · ');

    const frame = window.frame().slice(window.frame().indexOf('Background · '));
    const inside = (line: string) =>
      line.replace(/^│ ?/, '').replace(/ *│$/, '').trim();
    const [, , name, state] = frame.split('\n').map(inside);

    // One line for the name, the state line right under it.
    expect(state).toMatch(/^(running|✓|✗|■|●)/);

    if (name!.endsWith('…')) {
      expect(frame).toContain('› ');
    } else {
      expect(frame).not.toContain(`› ${name}`);
    }
  }));

describe("an agent's detail in a short window keeps the frame within its cap (CHD-487)", () => {
  test("at 80x18 the work is one row, its count beside it; at 80x16 none, its count at the state line's end; the hint and the prompt always shown", () =>
    withWindow(
      async (window) => {
        const frame = () =>
          window.frame().slice(window.frame().indexOf('Background · '));

        await send(window, 'claudebackground');
        await window.shows("background  main's 2 agents running");
        await window.press(DOWN);
        await window.press('\r');
        await window.shows('❯ Run the test suite');
        await window.press('\r');
        await window.shows('Background · 1 of 1 · ended');
        await window.shows('⏺ Every test passed.');

        await window.resize({ columns: 80, rows: 18 });
        await until('a lone row with its count', () =>
          / ↑ \d+ lines? above\s*│/.test(frame()),
        );
        expect(frame()).not.toContain('── ↑');
        expect(window.frame()).toContain('Enter to go to its call');
        expect(window.frame()).toContain('│ ›');

        await window.resize({ columns: 80, rows: 16 });
        await until('the count on the state line', () =>
          /✓ done in \d+s · .*↑ \d+ lines? above/.test(frame()),
        );
        expect(window.frame()).toContain('Enter to go to its call');
        expect(window.frame()).toContain('│ ›');
        await window.press('\x1b[5~');
        await until('paged with no row', () =>
          /↓ \d+ (lines? )?below/.test(frame()),
        );
      },
      { rows: 24, columns: 80 },
    ));
});

test('a detail one row tall pages its log to its last line, its blocks spaced so the scrollbox counts them (opentui#1739, CHD-487)', () =>
  withWindow(
    async (window) => {
      const frame = () =>
        window.frame().slice(window.frame().indexOf('Background · '));

      await send(window, 'claudebackground');
      await window.shows("background  main's 2 agents running");
      await window.press(DOWN);
      await window.press('\r');
      await window.shows('❯ Run the test suite');
      await window.press('\r');
      await window.shows('Background · 1 of 1 · ended');
      await window.shows('⏺ Every test passed.');
      await window.resize({ columns: 80, rows: 18 });
      // At its end, its last line in the one row.
      await window.press(END);
      await until('the last line in the one row', () =>
        /⏺ Every test passed\.\s+↑ \d+ lines? above/.test(frame()),
      );
      // To its top and back down a line at a time, every line reached.
      await window.press('\x1b[H');
      await window.shows('› Run bun test');

      for (
        let step = 0;
        step < 12 && !/Every test passed/.test(frame());
        step++
      ) {
        await window.press('\x1b[6~');
      }

      expect(frame()).toContain('⏺ Every test passed.');
    },
    { rows: 24, columns: 80 },
  ));
