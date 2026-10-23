/**
 * A transcript scrolled back keeps the entry on top in view: across ctrl+o,
 * a resize, and two sessions scrolled to the same row.
 */
import { openOther, pickAgent, withChild } from '../app/child_window.tsx';
import { expect, test } from 'bun:test';
import {
  CTRL_O,
  ready,
  send,
  until,
  type Window,
  withWindow,
} from '../app/render.tsx';
import { SHIFT_UP, PAGE_UP } from './transcript_keys.ts';

/**
 * A transcript with a folded call near its start and a page of replies
 * after it, scrolled back a page and on until a prompt below the call is
 * the view's top row, which it returns.
 */
async function backToAPrompt(window: Window): Promise<string> {
  await send(window, 'calls');
  await window.shows('Two calls worked, one failed.');

  for (let turn = 1; turn <= 10; turn++) {
    await send(window, `turn ${turn}`);
    await until(`reply ${turn}`, () => {
      const frame = window.frame();

      return (
        frame.indexOf('came in chunks.', frame.indexOf(`› turn ${turn}`)) > 0 &&
        !frame.includes('Working')
      );
    });
  }

  const top = () => window.frame().split('\n')[0]!;

  await window.press(PAGE_UP);

  // Then line by line, so a prompt lands exactly on the top row.
  for (let step = 0; step < 4 && !top().includes('› turn'); step++) {
    await window.press(SHIFT_UP);
  }

  expect(top()).toContain('› turn');

  return top();
}

test('ctrl+o while scrolled back keeps the entry on top in view', () =>
  withWindow(
    async (window) => {
      const top = await backToAPrompt(window);

      const drawn = window.written().length;

      // The call's output above the view opens, four rows more of it, and
      // no frame drawn meanwhile moved the view.
      await window.press(CTRL_O);
      await window.press(CTRL_O);
      await window.press(CTRL_O);

      for (const frame of window.written().slice(drawn)) {
        expect(frame.split('\n')[0]).toStrictEqual(top);
      }

      expect(window.frame()).toContain('lines below');
      // It did open: at the top, the call shows all its output.
      await window.press('\x1b[H');
      await window.shows('.parse(Deno.args)');
    },
    { rows: 24 },
  ));

test('a resize while scrolled back keeps the entry on top in view', () =>
  withWindow(
    async (window) => {
      const top = await backToAPrompt(window);

      await window.resize({ columns: 60 });
      await until(
        'the window to narrow',
        () => window.frame().split('\n')[0]!.trim() === top.trim(),
      );
      expect(window.frame()).toContain('lines below');
      await window.resize({ columns: 100, rows: 30 });
      await until(
        'the window to widen',
        () => window.frame().split('\n')[0]!.trim() === top.trim(),
      );
      expect(window.frame()).toContain('lines below');
    },
    { rows: 24 },
  ));

test('main and a child scrolled back to the same row each keep their own entry on top', () =>
  withChild(
    async (window) => {
      // Stopped, so nothing more comes in while the view moves.
      const stopped = async () => {
        await send(window, 'long');
        await window.shows('60. Line 60 of 200');
        await window.press('\x1b');
        await until(
          'the turn to end',
          () => !window.frame().includes('Working'),
        );
      };

      // The top, then the same rows down in each: one row, other entries.
      const back = async () => {
        await window.press('\x1b[H');
        await window.press('\x1b[1;2B'.repeat(30));
        await window.shows('lines below');
      };

      const top = () => window.frame().split('\n').slice(1, 4).join('\n');

      await ready(window);
      await openOther(window);
      await stopped();
      await pickAgent(window, 'other');
      await send(window, 'calls');
      await window.shows('Two calls worked, one failed.');
      await stopped();
      await back();

      const second = top();

      await pickAgent(window, 'main');
      await back();

      const first = top();

      expect(first).not.toStrictEqual(second);
      await pickAgent(window, 'other');
      await until('the child', () => top() === second);
      await pickAgent(window, 'main');
      await until('main', () => top() === first);
    },
    { rows: 24, columns: 100 },
  ));

test('a thought folds to one line and ctrl+o opens and closes it', () =>
  withWindow(async (window) => {
    await send(window, 'thought');
    await window.shows('Here is the answer.');
    expect(window.frame()).toContain('∴ Thinking…');
    // As in Claude Code the line names no key; the ? panel does.
    expect(
      !window.frame().includes('(ctrl+o'),
      'the thought names its key',
    ).toBeTruthy();
    expect(
      !window.frame().includes('Considering'),
      'the thought was open',
    ).toBeTruthy();
    await window.press(CTRL_O);
    await window.shows('Considering the question.');
    await window.press(CTRL_O);
    await until(
      'the thought to fold',
      () => !window.frame().includes('Considering'),
    );
    // ctrl+o typed nothing into the prompt.
    expect(
      !window.frame().includes('› o'),
      'ctrl+o typed into the draft',
    ).toBeTruthy();
  }));
