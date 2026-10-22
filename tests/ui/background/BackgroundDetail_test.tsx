/**
 * An agent's or a task's row opens its detail in the background view: its
 * stop and return keys, its whole task and its work, and its pinned name
 * (CHD-487).
 */
import { describe, expect, test } from 'bun:test';
import { DOWN, END, ready, send, until, withWindow } from '../app/render.tsx';
import { withBackground } from './background_window.tsx';

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
