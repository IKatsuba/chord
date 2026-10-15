import { expect, test } from 'bun:test';
import stripAnsi from 'strip-ansi';
import { ESC, left, send, until, withWindow } from '../app/render.tsx';

test('the plan is a list above the prompt while the turn runs', () =>
  withWindow(async (window) => {
    await send(window, 'text');
    await window.shows('came in chunks.');
    await until('the spinner to go', () => !window.frame().includes('Working'));

    // No plan, no list and no room kept for one.
    for (const mark of ['☐', '◐', '☒', '⎿']) {
      expect(
        !window.frame().includes(mark),
        `"${mark}" is on screen`,
      ).toBeTruthy();
    }

    await send(window, 'plan');
    await window.shows('☒ Read the code');

    const frame = window.frame();
    const lines = frame.split('\n');
    const below = (text: string) =>
      lines.findIndex((line) => line.includes(text));

    expect(frame).toContain('⎿  ☒ Read the code');
    expect(frame).toContain('◐ Write the change');
    expect(frame).toContain('☐ Run the tests');
    expect(
      below('Working…') < below('Read the code'),
      'under the spinner',
    ).toBeTruthy();
    expect(
      below('Run the tests') < below('╭'),
      'above the prompt',
    ).toBeTruthy();

    // A finished plan leaves the prompt for the transcript, once.
    await window.shows('Step 3 done.');
    await until('the spinner to go', () => !window.frame().includes('Working'));

    const after = window.frame().split('\n');
    const at = (text: string) => after.findIndex((line) => line.includes(text));

    const record = after.findIndex((line) => /⏺ Plan\s*$/.test(line));

    expect(
      record > at('Step 3 done.'),
      'the record follows the reply',
    ).toBeTruthy();
    expect(after[record + 1]?.trim()).toStrictEqual('⎿  ☒ Read the code');
    expect(
      at('☒ Run the tests') < at('╭'),
      'the record is above the prompt',
    ).toBeTruthy();
    expect(
      after.filter((line) => line.includes('☒ Read')).length,
    ).toStrictEqual(1);
    expect(
      !window.frame().includes('Plan ·'),
      'a live list is left',
    ).toBeTruthy();
  }));

test('an interrupted plan hangs from a line of its own', () =>
  withWindow(async (window) => {
    await send(window, 'plan');
    await window.shows('◐ Write the change');
    await window.press(ESC);
    await window.shows('Interrupted by user');
    await until('the spinner to go', () => !window.frame().includes('Working'));

    const lines = window.frame().split('\n');
    const at = (text: string) => lines.findIndex((line) => line.includes(text));

    expect(window.frame()).toContain('Plan · 1 of 3 done');
    expect(window.frame()).toContain('⎿  ☒ Read the code');
    expect(at('⎿  ☒ Read the code')).toStrictEqual(
      at('Plan · 1 of 3 done') + 1,
    );
    expect(at('☐ Run the tests') < at('╭'), 'above the prompt').toBeTruthy();
  }));

test('a step removed under a selection does not hand it to the step drawn in its place (CHD-172)', () =>
  withWindow(
    async (window) => {
      await send(window, 'planshrink');
      await window.shows('◐ Read the code');

      const rows = stripAnsi(window.frame()).split('\n');
      const y = rows.findIndex((row) => row.includes('◐ Read the code'));
      const x = rows[y]!.indexOf('Read the code');

      await window.press(left(x, y, 'down'));
      await window.press(left(x + 'Read the code'.length - 1, y, 'drag'));
      await window.press(left(x + 'Read the code'.length - 1, y, 'up'));
      expect(window.selected()).toStrictEqual('Read the code');

      await window.shows('Dropped a step.');
      // Its text has gone; none of the step now first is selected.
      expect(window.selected()).not.toContain('Write');
    },
    { copyOnSelect: false },
  ));
