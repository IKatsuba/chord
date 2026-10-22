/** The plan box on the fake: cursor's and grok's plans put to the person. */
import { expect, test } from 'bun:test';
import { DOWN, ESC, ready, send, withWindow } from '../app/render.tsx';

test("cursor's plan: drawn under its call, the box asks, and enter on the Note keeps planning with it (CHD-437)", () =>
  withWindow(
    async (window) => {
      await ready(window);
      await send(window, 'cursorplan');
      await window.shows('Approve Plan');

      const frame = window.frame();

      expect(frame).toContain('⏺ Plan(Route updates by session)');
      expect(frame).toContain('⎿  Waiting…');
      expect(frame).toContain(
        'Split the session routing out of the connection.',
      );
      expect(frame).toContain('◐ Move the routing');
      expect(frame).toContain('Waiting for your answer to the plan…');
      expect(frame).toContain('fake has a plan. Do you want to proceed?');
      expect(frame).toContain('❯ 1. Yes, accept the plan');
      expect(frame).toContain(
        'Note  Tell fake what to change, sent with 2 (optional)',
      );
      expect(frame).toContain(
        'Enter to pick · 1–2 · ↑↓ to move · Esc to keep planning',
      );

      await window.press(DOWN);
      await window.press(DOWN);
      await window.type('two tests');
      await window.shows('❯ Note  two tests');
      await window.press('\r');
      await window.shows('⎿  Kept planning: two tests');
      await window.shows(
        'Plan answer: {"outcome":"rejected","reason":"two tests"}',
      );
      expect(window.frame()).not.toContain('Approve Plan');
      // The note went to the box alone: never into the prompt, never sent.
      await new Promise((resolve) => setTimeout(resolve, 300));
      expect(window.frame()).not.toContain('› two tests');
      expect(window.frame()).not.toContain('Hello, world');
    },
    { rows: 40, columns: 120 },
  ));

test("grok's plan at 80x24: its third choice leaves plan mode; esc keeps planning; with no plan it says so (CHD-457)", () =>
  withWindow(
    async (window) => {
      await ready(window);
      await send(window, 'grokplan');
      await window.shows('3. No, and leave plan mode');
      await window.press(ESC);
      await window.shows('Plan answer: {"outcome":"revise"}');
      await send(window, 'grokplanempty');
      // The box and the call say so alike, the agent named as the window does.
      await window.shows('fake has written no plan. Do you want to proceed?');
      await window.shows('   fake has written no plan.');
      await window.press('3');
      await window.shows('⎿  Left plan mode');
      await window.shows('Plan answer: {"outcome":"abandoned"}');
    },
    { rows: 24, columns: 80 },
  ));

test('a plan and a form asked at once: the plan box alone has the keys, and the form only once it is answered (CHD-437)', () =>
  withWindow(
    async (window) => {
      await ready(window);
      await send(window, 'planform');
      await window.shows('Approve Plan');
      expect(window.frame()).not.toContain('Name the branch');
      // A key typed for a form reaches the box alone: no letter types, no
      // enter accepts on the form's behalf; 2 is the person's choice.
      await window.type('main');
      expect(window.frame()).toContain('❯ 1. Yes, accept the plan');
      await window.press('2');
      await window.shows('Name the branch');
      expect(window.frame()).not.toContain('Approve Plan');
      await window.press(ESC);
      await window.shows('Plan answer: {"outcome":"rejected"} · form: cancel');
    },
    { rows: 40, columns: 120 },
  ));

test('a long note at 80x24 wraps in the box, read whole as typed, and goes whole (CHD-437)', () =>
  withWindow(
    async (window) => {
      const note =
        'Keep the routing in connection.ts and only add a test for it; ' +
        'leave session.ts as it is until the next release, and ' +
        'name the test after the bug it covers so it reads back later.';

      await ready(window);
      await send(window, 'cursorplan');
      await window.shows('Approve Plan');
      await window.press(DOWN);
      await window.press(DOWN);
      await window.type(note);

      const box = window
        .frame()
        .split('\n')
        .filter((line) => line.startsWith('│'))
        .map((line) => line.slice(1, -1).trim())
        .join(' ');

      expect(box.replace(/\s+/g, ' ')).toContain(
        `Note ${note}`.replace(/\s+/g, ' '),
      );
      expect(window.frame()).toContain('Enter to keep planning with this note');
      await window.press('\r');
      await window.shows('Plan answer:');
      expect(window.frame().replace(/\s+/g, ' ')).toContain(
        JSON.stringify({ outcome: 'rejected', reason: note }),
      );
    },
    { rows: 24, columns: 80 },
  ));
