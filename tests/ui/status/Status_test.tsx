import { expect, test } from 'bun:test';
import { CTRL_C, send, until, withWindow } from '../app/render.tsx';
import { STEER_REFUSED, UNSTEERED } from '../../../src/ui/status/Status.tsx';

const SHIFT_TAB = '\x1b[Z';

test('the status line names the mode on the left, the model, the effort and the context on the right', () =>
  withWindow(async (window) => {
    await window.shows('Fake Large with a 1M context window');
    await send(window, 'status');
    await window.shows('1% used');

    const status = window.frame().split('\n').at(-1) ?? '';

    expect(!status.includes('? for shortcuts'), status).toBeTruthy();
    expect(
      status.trimStart().startsWith('⏸ plan mode on (shift+tab to cycle)'),
      status,
    ).toBeTruthy();
    // Beside the mode's hint, the effort and the context lose their words.
    expect(status).toContain(
      'Fake Large with a 1M context window · medium · 1% used',
    );
  }));

test('a draft hides the shortcut hint but not the mode', () =>
  withWindow(
    async (window) => {
      const status = () => window.frame().split('\n').at(-1) ?? '';

      await window.shows('Fake Large with a 1M context window');
      await window.type('x');
      await until('the hint gone', () => !status().includes('? for shortcuts'));
      await window.press(SHIFT_TAB);
      await window.press(SHIFT_TAB);
      await window.shows('⏸ plan mode on (shift+tab to cycle)');
      expect(window.frame()).toContain('› x');
    },
    { columns: 80 },
  ));

test("shift+tab walks the agent's modes and wraps back to the start", () =>
  withWindow(async (window) => {
    const status = () => window.frame().split('\n').at(-1) ?? '';

    await window.shows('Fake Large with a 1M context window');
    await window.press(SHIFT_TAB);
    await window.shows('⏵⏵ accept edits on');
    await window.press(SHIFT_TAB);
    await window.shows('⏸ plan mode on');
    expect(!status().includes('accept edits'), status()).toBeTruthy();
    await window.press(SHIFT_TAB);
    // The default mode says nothing, as in Claude Code.
    await until('the plan mode gone', () => !status().includes('plan mode'));
    expect(status()).toContain('Fake Large with a 1M context window');
    expect(
      !window.frame().includes('Could not switch'),
      window.frame(),
    ).toBeTruthy();
  }));

test('a mode the agent leaves by itself leaves the status line', () =>
  withWindow(async (window) => {
    await window.shows('Fake Large with a 1M context window');
    await window.press(SHIFT_TAB);
    await window.press(SHIFT_TAB);
    await window.shows('⏸ plan mode on');
    await send(window, 'exitplan');
    await window.shows('Plan approved.');
    await until(
      'the plan mode gone',
      () => !window.frame().includes('plan mode on'),
    );
  }));

test('shift+tab goes on from a mode the agent moved to in a turn', () =>
  withWindow(async (window) => {
    await send(window, 'status');
    await window.shows('⏸ plan mode on');
    await until('the turn over', () => !window.frame().includes('Working…'));
    // From plan, the last of the agent's modes, round to its first.
    await window.press(SHIFT_TAB);
    await until(
      'the plan mode gone',
      () => !window.frame().includes('plan mode on'),
    );
    await window.press(SHIFT_TAB);
    await window.shows('⏵⏵ accept edits on');
  }));

test('a refused mode change leaves the mode the agent reported', () =>
  withWindow(async (window) => {
    // Plan by `current_mode_update` alone: the config option still says
    // default, the mode shift+tab asks for next.
    await send(window, 'lock');
    await window.shows('⏸ plan mode on');
    await until('the turn over', () => !window.frame().includes('Working…'));
    await window.press(SHIFT_TAB);
    await window.shows('Could not switch to default mode');
    await new Promise((resolve) => setTimeout(resolve, 150));
    expect(window.frame()).toContain('⏸ plan mode on');
  }));

test('at 80 columns the status line keeps the mode whole and shortens', () =>
  withWindow(
    async (window) => {
      await send(window, 'status');
      await window.shows('1% used');

      const status = window.frame().split('\n').at(-1) ?? '';

      expect(!status.includes('shift+tab to cycle'), status).toBeTruthy();
      expect(
        status.trimStart().startsWith('⏸ plan mode on '),
        status,
      ).toBeTruthy();
      expect(status).toContain(
        'Fake Large with a 1M context window · medium · 1% used',
      );
    },
    { columns: 80 },
  ));

test('at 40 columns the ctrl+c warning stays whole beside the facts', () =>
  withWindow(
    async (window) => {
      await send(window, 'status');
      await window.shows('1% used');
      await window.press(CTRL_C);
      await window.shows('Press ctrl+c again to quit');

      const status = window.frame().split('\n').at(-1) ?? '';

      expect(status).toContain('Press ctrl+c again to quit');
      expect(!status.includes('…'), status).toBeTruthy();
    },
    { columns: 40 },
  ));

test("the working line turns Chorded's mark where the star was", () =>
  withWindow(async (window) => {
    await send(window, 'slow');
    await window.shows('››› Working…');
  }));

test("Tab's notes say the message stays queued, whole at 80 columns (CHD-535)", () => {
  expect(UNSTEERED).toStrictEqual(
    'This agent does not take messages into a running turn · it stays queued',
  );
  expect(STEER_REFUSED).toStrictEqual(
    'Not taken into the running turn · it stays queued',
  );
  expect(UNSTEERED.length).toBeLessThanOrEqual(78);
});
