/**
 * A team's rows folded in the agents list, and a request scrolled beside
 * it (CHD-464).
 */
import { describe, expect, test } from 'bun:test';
import { serveChord } from '../../../src/server/server.ts';
import {
  DOWN,
  ESC,
  leader,
  ready,
  send,
  until,
  withWindow,
} from '../app/render.tsx';
import { BUGFIX } from './teams_window.tsx';

describe('CHD-464 tester: folded list recovery and permission keys', () => {
  test('resizing keeps the hint and summary, and rejecting restores all team rows', async () => {
    const server = serveChord();

    try {
      await withWindow(
        async (window) => {
          await ready(window);
          await send(window, 'teamtask');
          await window.shows('The team and the task are both at work.');
          await until('tester asks', () =>
            /├─ tester .*● permission/.test(window.frame()),
          );

          for (let presses = 0; presses < 8; presses++) {
            if (/❯ ├─ tester/.test(window.frame())) {
              break;
            }

            await window.press(DOWN);
          }

          await window.press('\r');
          await window.shows('╭─ tester · bugfix ─');

          for (const size of [
            { columns: 80, rows: 24 },
            { columns: 120, rows: 40 },
            { columns: 80, rows: 24 },
          ]) {
            await window.resize(size);
            await until('hint and border on separate rows', () =>
              /│ Esc to reject +│ *\n╰─+╯/.test(window.frame()),
            );
            await window.shows('background  ● 1 task asking');

            if (size.rows === 24) {
              await until('the list folds', () =>
                /… \+\d+ more/.test(window.frame()),
              );
            } else {
              await window.shows('└─ coder');
              expect(window.frame()).not.toMatch(/… \+\d+ more/);
            }
          }

          await window.press(ESC);
          await window.shows('Not run; I will ask bugfix how to go on.');
          await window.shows('└─ coder');
          expect(window.frame()).not.toContain('Esc to reject');
          expect(window.frame()).not.toMatch(/… \+\d+ more/);
          expect(window.frame()).toContain('background  ● 1 task asking');
        },
        {
          server,
          runtimes: ['fake'],
          teams: { bugfix: BUGFIX },
          columns: 120,
          rows: 40,
        },
      );
    } finally {
      await server.close();
    }
  });
});

describe('CHD-464 tester: request scrolling and list recovery', () => {
  for (const [columns, rows] of [
    [80, 24],
    [120, 40],
  ] as const) {
    test(`paging loses no content and shrinking keeps the answers at ${columns}×${rows}`, async () => {
      const server = serveChord();

      try {
        await withWindow(
          async (window) => {
            await ready(window);
            await send(window, 'teamtask');
            await window.shows('The team and the task are both at work.');
            await until('the team member asks', () =>
              /├─ tester .*● permission/.test(window.frame()),
            );
            await leader(window, 'a');
            await window.shows('Esc to reject');
            await window.press('1');
            // The task's report adds fixed rows; wait for it before paging.
            await window.shows(
              'Received the message from Fix the tokenizer · fake · report.',
            );
            await send(window, 'bigask');
            await window.shows('lines below · pagedown to scroll');

            const seen = new Set<number>();

            for (let page = 0; page < 60; page++) {
              const frame = window.frame();

              for (const match of frame.matchAll(/Change (\d+):/g)) {
                seen.add(Number(match[1]));
              }

              expect(frame).toContain('3. No, and tell Claude');
              expect(frame).toMatch(/│ Esc to reject +│ *\n╰─+╯/);

              if (frame.includes('mode: overwrite')) {
                break;
              }

              await window.press('\x1b[6~');
              await until(
                'the request page changes',
                () => window.frame() !== frame,
              );
            }

            for (let change = 1; change <= 30; change++) {
              expect(seen.has(change), `Change ${change} was skipped`).toBe(
                true,
              );
            }

            await window.press('\x1b[F');
            await until(
              'the request reaches its last row',
              () =>
                window.frame().includes('mode: overwrite') &&
                !window.frame().includes('lines below'),
            ).catch((error: Error) => {
              throw new Error(
                `${error.message}; the screen:\n${window.frame()}`,
              );
            });

            for (const height of [22, 20, rows]) {
              await window.resize({
                columns: height === rows ? columns : 80,
                rows: height,
              });
              await window.press('\x1b[H');
              await window.shows('lines below');
              expect(window.frame()).toContain('3. No, and tell Claude');
              expect(window.frame()).toMatch(/│ Esc to reject +│ *\n╰─+╯/);

              if (height === rows) {
                await window.shows('path: docs/release.md');
                await window.press('\x1b[F');
                await until(
                  'the recovered request reaches its end',
                  () =>
                    window.frame().includes('mode: overwrite') &&
                    !window.frame().includes('lines below'),
                );
              }
            }

            await window.press(ESC);
            await until(
              'the tall request closes',
              () => !window.frame().includes('Esc to reject'),
            );
            await window.shows('└─ coder');
            expect(window.frame()).not.toMatch(/… \+\d+ more/);
            await send(window, 'permission');
            await window.shows('Write notes.txt');
            expect(window.frame()).not.toContain('lines below');
            expect(window.frame()).not.toContain('lines above');
            expect(window.frame()).toMatch(/│ Esc to reject +│ *\n╰─+╯/);
            await window.press(ESC);
            await window.shows('└─ coder');
            expect(window.frame()).not.toMatch(/… \+\d+ more/);
          },
          {
            server,
            runtimes: ['fake'],
            teams: { bugfix: BUGFIX },
            columns,
            rows,
          },
        );
      } finally {
        await server.close();
      }
    });
  }
});
