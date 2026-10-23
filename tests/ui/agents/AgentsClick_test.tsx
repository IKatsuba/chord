/**
 * The keys a click on the prompt box takes back from the agents list and its
 * summary line, and what the click leaves of the box and the dialogs beside it.
 */
import { describe, expect, test } from 'bun:test';
import {
  DOWN,
  ESC,
  left,
  ready,
  send,
  until,
  type Window,
} from '../app/render.tsx';
import { withAgents } from './agents_window.tsx';

/** A left click on the prompt box's text row, as a terminal reports one. */
async function clickBox(window: Window): Promise<void> {
  const y = window
    .frame()
    .split('\n')
    .findLastIndex((line) => line.startsWith('│ ›'));

  expect(y).toBeGreaterThan(0);
  await window.press(left(10, y, 'down'));
  await window.press(left(10, y, 'up'));
}

test("a click on the box takes the keys back from the list: the ❯ goes, the child picked stays the box's, and typing goes in in order (CHD-384)", () =>
  withAgents(async (window) => {
    await ready(window);
    await send(window, 'agents');
    await window.shows('Waiting on parser.');
    await window.press(DOWN);
    await window.press(DOWN);
    await window.shows('❯ parser ');
    await clickBox(window);
    await until('the ❯ gone', () => !window.frame().includes('❯ parser '));
    await window.type('abc');
    await window.type('def');
    await window.shows('│ › abcdef');
    // Still parser's box, and the list's hint gone from the status line.
    expect(window.frame()).toContain('╭─ parser ');
    expect(!window.frame().includes('↑ ↓ to pick')).toBeTruthy();
    // ↓ is the box's again: it stays in the draft, not in the list.
    await window.press(DOWN);
    expect(!window.frame().includes('❯ ')).toBeTruthy();
  }));

test('a click on the box takes the keys back from the summary line too (CHD-384)', () =>
  withAgents(async (window) => {
    await ready(window);
    await send(window, 'monitors');
    await window.shows('    background  2 monitors running');
    await window.press(DOWN);
    await window.shows('❯ background');
    await clickBox(window);
    await until('the ❯ gone', () => !window.frame().includes('❯ background'));
    await window.type('abc');
    await window.type('def');
    await window.shows('│ › abcdef');
    // Enter is the box's: it sends the draft, not opening the view.
    await window.press('\r');
    await window.shows('› abcdef');
    expect(!window.frame().includes(' Background · ')).toBeTruthy();
  }));

describe('CHD-384 tester: click focus and neighboring dialogs', () => {
  for (const columns of [80, 120]) {
    for (const target of ['child', 'summary'] as const) {
      test(`clicking from ${target} focus at ${columns} columns restores cursor edits and keyboard list navigation`, () =>
        withAgents(async (window) => {
          await window.resize({ columns, rows: columns === 80 ? 24 : 40 });
          await ready(window);
          await send(window, target === 'child' ? 'monitorchild' : 'monitors');
          await window.shows('background  2 monitors running');
          await window.press(DOWN);

          if (target === 'child') {
            await window.press(DOWN);
            await window.shows('❯ parser ');
          } else {
            await window.shows('❯ background');
          }

          await clickBox(window);
          await until(
            'list highlight released by click',
            () =>
              !window
                .frame()
                .includes(target === 'child' ? '❯ parser ' : '❯ background'),
          );
          await window.type('abc');
          await window.type('def');
          await window.shows('│ › abcdef');
          await window.press('\x1b[D');
          await window.press('\x1b[D');
          await window.type('XY');
          await window.shows('│ › abcdXYef');
          await window.press('\x7f');
          await window.shows('│ › abcdXef');
          expect(window.frame()).not.toContain('↑ ↓ pick');
          expect(window.frame()).not.toContain('↑ ↓ to pick');

          if (target === 'child') {
            expect(window.frame()).toContain('╭─ parser ');
          }

          await window.press('\x03');
          await window.press(DOWN);
          await window.shows(target === 'child' ? '❯ parser ' : '❯ background');
          await window.press(ESC);
          await until(
            'keyboard exit releases list',
            () =>
              !window
                .frame()
                .includes(target === 'child' ? '❯ parser ' : '❯ background'),
          );
          await window.type('ghi');
          await window.shows('│ › ghi');
        }));
    }
  }

  test('a click releases a selected asking child to its permission box without answering it at 80x24', () =>
    withAgents(async (window) => {
      await window.resize({ columns: 80, rows: 24 });
      await ready(window);
      await send(window, 'agents');
      await window.shows('Waiting on parser.');
      await window.press(DOWN);
      await window.press(DOWN);
      await window.press(DOWN);
      await window.shows('❯ docs ');
      await window.shows('Do you want to proceed?');
      await clickBox(window);
      await until(
        'docs list highlight released',
        () => !window.frame().includes('❯ docs '),
      );
      expect(window.frame()).toContain('Do you want to proceed?');
      expect(window.frame()).not.toContain('Permission: allow.');
      await window.press('1');
      await window.shows('Permission: allow.');
      expect(window.frame()).toContain('╭─ docs ');
    }));
});
