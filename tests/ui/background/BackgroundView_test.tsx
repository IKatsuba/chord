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
          await window.shows('■ stopped after');
          await window.press('j');
          await window.shows('❯ parser tests');
          await window.press('\x1b[1;2A');
          expect(window.frame()).toContain('❯ parser tests');
          await window.press('z');
          await until(
            'both monitors stopped',
            () => (window.frame().match(/■ stopped after/g) ?? []).length === 2,
          );
          await window.press(ESC);
          await window.shows('❯ background  ■ 2 monitors stopped');
          await window.press(UP);
          await window.shows('❯ parser ');
          await window.press('z');
          await window.press('z');
          await window.shows('background  ■ 1 monitor stopped');
          expect(window.frame()).not.toContain('❯ parser ');
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

test('a Claude agent that takes a while to stop reads stopping until it says it stopped, and a second x changes nothing', () =>
  withWindow(
    async (window) => {
      await send(window, 'claudeslowstop');
      await window.shows('background  2 agents running');
      await window.press(DOWN);
      await window.press('\r');
      await window.shows('❯ Run the test suite');
      await window.press('x');
      await window.shows('■ stopping');
      await window.press('x');
      expect(window.frame()).toContain('■ stopping');
      expect(window.frame()).not.toContain('could not stop');
      await window.shows('■ stopped after');
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
          await window.shows('background  2 agents running');
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
          await window.shows('background  2 agents running');
          await window.press('\r');
          await window.shows('■ stopping');
          await writeFile(join(window.dir, '.fake-gate', 'stop-release'), '');
          await window.shows('■ stopped after');
          await window.shows('✓ done in');
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
          await window.shows('background  2 agents running');

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
        await window.shows('background  2 agents running');
        await window.press(DOWN);
        await window.press('\r');
        await window.shows('❯ Run the test suite');
        await window.press('x');
        await window.shows('■ stopping');
        await window.shows('✓ done in');
        await until(
          'both children done despite the held stop',
          () => (window.frame().match(/✓ done in/g) ?? []).length === 2,
        );
        expect(window.frame()).not.toContain('■ stopping');
        await window.press('x');
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
            await window.shows('background  2 agents running');

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
