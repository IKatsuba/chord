/**
 * ctrl+r's search over earlier prompts in the window, and a permission asked
 * while it is open.
 */
import { expect, test } from 'bun:test';
import chalk from 'chalk';
import {
  asked,
  CTRL_R,
  ESC,
  promptRow,
  ready,
  send,
  TAB,
  until,
  type Window,
  withWindow,
} from '../app/render.tsx';

test('ctrl+r finds an earlier prompt, steps older, and Enter takes it', () =>
  withWindow(async (window) => {
    for (const prompt of ['fix auth', 'text', 'explain auth']) {
      await send(window, prompt);
      await until('the turn to end', () => !window.frame().includes('Working'));
    }

    await window.type('half typed');
    await window.press(CTRL_R);
    await window.shows('search prompts:');
    // Nothing typed yet: the box still shows the draft.
    expect(
      promptRow(window)?.includes('› half typed'),
      'the draft went',
    ).toBeTruthy();
    await window.type('auth');
    await until(
      'the newest match',
      () => promptRow(window)?.includes('› explain auth') ?? false,
    );
    expect(window.frame()).toContain('search prompts: auth');
    await window.press(CTRL_R);
    await until(
      'the older match',
      () => promptRow(window)?.includes('› fix auth') ?? false,
    );
    await window.press(CTRL_R);
    await window.shows('no matching prompt: auth');
    expect(
      promptRow(window)?.includes('› fix auth'),
      'the match went',
    ).toBeTruthy();

    await window.press('\r');
    await until(
      'the search to close',
      () => !window.frame().includes('matching prompt'),
    );
    // Taken to edit, not sent: typing goes on from its end.
    await window.type(' now');
    expect(
      promptRow(window)?.includes('› fix auth now'),
      'not editable',
    ).toBeTruthy();
  }));

/**
 * Sends `before` and `auth` as one paste, searches for `auth`, and expects
 * the box's row to mark all of `auth` inverse and nothing before it.
 */
async function markedAfter(window: Window, before: string): Promise<void> {
  await window.paste(`${before}auth`);
  await window.press('\r');
  await until('the turn to end', () => !window.frame().includes('Working'));
  await window.press(CTRL_R);
  await window.type('auth');
  await window.shows('search prompts: auth');

  // The frame's escapes are written only while chalk sees colour.
  chalk.level = 3;

  const frame = (() => {
    try {
      return window.frame();
    } finally {
      chalk.level = 0;
    }
  })();
  const row = frame.split('\n').find((line) => line.includes('› '))!;

  expect(row).toContain('\x1b[7mauth\x1b[0m');
  expect(row.slice(row.indexOf('› '), row.indexOf('\x1b[7m'))).not.toContain(
    '\x1b',
  );
}

test('ctrl+r marks the query inverse after a tab, drawn as its spaces (CHD-306)', () =>
  withWindow((window) => markedAfter(window, 'say a\t')));

test('ctrl+r marks the query inverse after a decomposed accent or a joined emoji (CHD-306, CHD-319)', () =>
  withWindow(async (window) => {
    await markedAfter(window, 'say e\u0301 ');
    await window.press(ESC);
    await markedAfter(window, 'say 👩‍💻 ');
  }));

/**
 * Sends `slow`, queues `permission` and opens a search for `slow` while the
 * first turn runs, so the permission is asked with the search open.
 */
async function askedWhileSearching(window: Window): Promise<void> {
  await send(window, 'slow');
  await window.shows('esc to interrupt');
  await send(window, 'permission');
  await window.type('draft');
  await window.press(CTRL_R);
  await window.type('slow');
  await until(
    'the match',
    () => promptRow(window)?.includes('› slow') ?? false,
  );
  await asked(window);
  expect(
    !window.frame().includes('search prompts'),
    'still searching',
  ).toBeTruthy();
  expect(
    promptRow(window)?.includes('› draft'),
    'the draft did not come back',
  ).toBeTruthy();
}

test('a permission asked during a search takes Enter alone', () =>
  withWindow(async (window) => {
    await askedWhileSearching(window);
    await window.press('\r');
    await window.shows('Permission: allow.');
    expect(
      promptRow(window)?.includes('› draft'),
      'Enter took the match',
    ).toBeTruthy();
    expect(
      !promptRow(window)?.includes('slow'),
      'Enter took the match',
    ).toBeTruthy();
  }));

test('a number key answers a permission asked during a search', () =>
  withWindow(async (window) => {
    await askedWhileSearching(window);
    await window.press('2');
    await window.shows('Permission: always.');
    expect(
      promptRow(window)?.includes('› draft'),
      'the draft went',
    ).toBeTruthy();
    expect(!window.frame().includes('draft2'), 'typed into it').toBeTruthy();
  }));

test('Esc on a permission asked during a search rejects it, nothing more', () =>
  withWindow(async (window) => {
    await askedWhileSearching(window);
    await window.press(ESC);
    await window.shows('Permission: deny.');
    expect(
      !window.frame().includes('Interrupted'),
      'Esc interrupted the turn',
    ).toBeTruthy();
    // The draft takes keys again, from its end.
    await window.type('!');
    expect(
      promptRow(window)?.includes('› draft!'),
      'the draft took no keys',
    ).toBeTruthy();
  }));

test('Esc leaves a search with the draft as it was', () =>
  withWindow(async (window) => {
    await send(window, 'text');
    await until('the turn to end', () => !window.frame().includes('Working'));
    await window.type('draft');
    await window.press(CTRL_R);
    await window.type('tex');
    await until(
      'the match',
      () => promptRow(window)?.includes('› text') ?? false,
    );
    await window.press(ESC);
    await until(
      'the draft',
      () => promptRow(window)?.includes('› draft') ?? false,
    );
    expect(
      !window.frame().includes('search prompts'),
      'still searching',
    ).toBeTruthy();
    // The draft takes keys again, from where its cursor was.
    await window.type('!');
    expect(
      promptRow(window)?.includes('› draft!'),
      'the draft took no keys',
    ).toBeTruthy();
  }));

test('a command found by ctrl+r comes back in bash mode', () =>
  withWindow(async (window) => {
    await window.type('!');
    await window.shows('! for bash mode');
    await window.type('echo found');
    await window.press('\r');
    await window.shows('⎿  found');
    await ready(window);
    await window.press(CTRL_R);
    await window.type('found');
    await until(
      'the command',
      () => promptRow(window)?.includes('! echo found') ?? false,
    );
    await window.press(TAB);
    await window.shows('! for bash mode');
    expect(
      promptRow(window)?.includes('! echo found'),
      'not in bash mode',
    ).toBeTruthy();
  }));
