/**
 * A box that asks beside a team's member: which comes first, what its hint
 * names, and how it fits at 80x24 and 120x40.
 */
import { describe, expect, test } from 'bun:test';
import { serveChord } from '../../../src/server/server.ts';
import {
  DOWN,
  END,
  leader,
  ready,
  send,
  until,
  type Window,
  withWindow,
} from '../app/render.tsx';
import { BUGFIX, withTeams } from './teams_window.tsx';

describe('a task of main asking beside a member (CHD-431)', () => {
  /** `teamtask`, until main's task and tester both ask. */
  async function bothAsk(window: Window): Promise<void> {
    await ready(window);
    await send(window, 'teamtask');
    await window.shows('The team and the task are both at work.');
    await window.shows('Agent(Fix the tokenizer) · fake asks');
    await window.shows('├─ tester');
    await until('tester asks', () =>
      /├─ tester .*● permission/.test(window.frame()),
    );
  }

  /** tester picked from the list, its prompt given the keys. */
  async function toTester(window: Window): Promise<void> {
    for (let presses = 0; presses < 8; presses++) {
      if (/❯ ├─ tester/.test(window.frame())) {
        break;
      }

      await window.press(DOWN);
    }

    await window.press('\r');
    await window.shows('╭─ tester · bugfix ─');
  }

  test("main's held box comes first, then ctrl+x a goes on to the member", () =>
    withTeams(async (window) => {
      await bothAsk(window);
      // main's own request between turns is the line's, naming nobody behind.
      // Wide or short, as the line has room.
      expect(window.frame()).toMatch(
        /● permission( asked between turns)? · ctrl\+x a to answer/,
      );
      expect(window.frame()).not.toContain('tester needs your permission');
      await leader(window, 'a');
      await window.shows('Esc to reject');
      await window.press('1');
      await window.shows('● tester needs your permission · ctrl+x a to go');
      await leader(window, 'a');
      await window.shows('╭─ tester · bugfix ─');
      await window.shows('tester · bugfix asks');
    }));

  test("from the member, the hint names main's task as its box does, and ctrl+x a reaches it", () =>
    withTeams(async (window) => {
      await bothAsk(window);
      await toTester(window);
      // Wide, or short where tester's mode leaves no room for the task's name.
      await until('the task named', () =>
        /● (Agent\(Fix the tokenizer\) · fake|main's task) needs your permission · ctrl\+x a/.test(
          window.frame(),
        ),
      );

      // From a session picked by hand, ctrl+x a goes first to what the hint
      // names, main's task, however coder's reply came (the owner's Q46).
      const shown = () =>
        /╭─ (\w+) · bugfix ─/.exec(window.frame())?.[1] ?? 'main';
      const task = 'Agent(Fix the tokenizer) · fake asks';

      await leader(window, 'a');
      await until('ctrl+x a moves on', () => shown() !== 'tester');
      await window.shows(task);
      expect(shown()).toStrictEqual('main');
    }));

  test("at 80x24 tester's box keeps its hint inside its border, the agents list folding to fit and the summary line whole (CHD-464)", async () => {
    const server = serveChord();

    try {
      await withWindow(
        async (window) => {
          await bothAsk(window);
          await toTester(window);

          const lines = window.frame().split('\n');
          const hint = lines.findIndex((line) =>
            /^│ Esc to reject +│$/.test(line.trimEnd()),
          );

          expect(hint, window.frame()).toBeGreaterThan(0);
          expect(lines[hint + 1]?.trimEnd()).toMatch(/^╰─+╯$/);
          expect(window.frame()).toMatch(/… \+\d+ more/);
          expect(window.frame()).toContain('background  ● 1 task asking');
        },
        {
          server,
          runtimes: ['fake'],
          rows: 24,
          columns: 80,
          teams: { bugfix: BUGFIX },
        },
      );
    } finally {
      await server.close();
    }
  });

  test("at 80x24 a tall request's ↓ rule sits under its last shown row, the hint inside the border (CHD-464)", async () => {
    const server = serveChord();

    try {
      await withWindow(
        async (window) => {
          await bothAsk(window);
          await leader(window, 'a');
          await window.shows('Esc to reject');
          await window.press('1');
          await send(window, 'bigask');
          await window.shows('mcp__files__write_file');
          await window.shows('lines below · pagedown to scroll');

          const lines = window.frame().split('\n');
          const rule = lines.findIndex((line) =>
            /^│ ── ↓ \d+ lines below · pagedown to scroll ─+ │$/.test(
              line.trimEnd(),
            ),
          );
          const hint = lines.findIndex((line) =>
            /^│ Esc to reject +│$/.test(line.trimEnd()),
          );

          // Drawn over the request's last row, the rule left its own row
          // blank: two blank rows before the question instead of one.
          expect(rule, window.frame()).toBeGreaterThan(0);
          expect(lines[rule - 1]?.trimEnd(), window.frame()).toMatch(
            /^│ (mcp__files__write_file| {2}.*) +│$/,
          );
          expect(lines[rule + 1]?.trimEnd(), window.frame()).toMatch(/^│ +│$/);
          expect(lines[rule + 2]?.trimEnd(), window.frame()).toMatch(
            /^│ Do you want to proceed\? +│$/,
          );
          expect(hint, window.frame()).toBeGreaterThan(rule);
          expect(lines[hint + 1]?.trimEnd()).toMatch(/^╰─+╯$/);
        },
        {
          server,
          runtimes: ['fake'],
          rows: 24,
          columns: 80,
          teams: { bugfix: BUGFIX },
        },
      );
    } finally {
      await server.close();
    }
  });

  test("at 120x40 under the folded list, a tall request's room holds still and its end view shows its last row (CHD-464)", async () => {
    const server = serveChord();

    try {
      await withWindow(
        async (window) => {
          await bothAsk(window);
          await leader(window, 'a');
          await window.shows('Esc to reject');
          await window.press('1');
          await send(window, 'bigask');
          await window.shows('lines below · pagedown to scroll');
          await window.press(END);
          await window.shows('lines above · pageup to scroll');

          // The request, from its title to the question under it.
          const request = () => {
            const lines = window.frame().split('\n');
            const from = lines.findIndex((line) =>
              line.includes('mcp__files__write_file'),
            );
            const to = lines.findIndex((line) =>
              line.includes('Do you want to proceed?'),
            );

            return lines.slice(from, to + 1).map((line) => line.trimEnd());
          };

          // The list folding and the box giving way traded rows on every
          // frame, so the room, and with it the view, never held.
          const seen = new Set<string>();

          for (let frame = 0; frame < 10; frame++) {
            seen.add(request().join('\n'));
            await new Promise((resolve) => setTimeout(resolve, 50));
          }

          const shown = request();

          expect(seen.size, [...seen].join('\n\n')).toStrictEqual(1);
          expect(shown.join('\n')).not.toContain('lines below');
          expect(shown.at(-3), shown.join('\n')).toMatch(
            /^│ {3}mode: overwrite +│$/,
          );
          expect(shown.at(-2)).toMatch(/^│ +│$/);
        },
        {
          server,
          runtimes: ['fake'],
          rows: 40,
          columns: 120,
          teams: { bugfix: BUGFIX },
        },
      );
    } finally {
      await server.close();
    }
  });
});

describe('a task of main asking beside a member, at 80 columns (CHD-431)', () => {
  test("the hint names whose task it is where the task's name does not fit", async () => {
    const server = serveChord();

    try {
      await withWindow(
        async (window) => {
          await ready(window);
          await send(window, 'teamtask');
          await window.shows('The team and the task are both at work.');
          await window.shows('├─ tester');
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
          await window.shows("● main's task needs your permission · ctrl+x a");
        },
        {
          server,
          runtimes: ['fake'],
          rows: 40,
          columns: 80,
          teams: { bugfix: BUGFIX },
        },
      );
    } finally {
      await server.close();
    }
  });
});
