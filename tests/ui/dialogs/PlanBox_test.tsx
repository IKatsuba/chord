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
      await window.shows('grok has written no plan.');
      await window.press('3');
      await window.shows('⎿  Left plan mode');
      await window.shows('Plan answer: {"outcome":"abandoned"}');
    },
    { rows: 24, columns: 80 },
  ));
