import { describe, expect, test } from 'bun:test';
import { fakeAgentCommand } from '../../fixtures/fake.ts';
import {
  CTRL_C,
  ESC,
  inputAsked,
  isAlive,
  leader,
  promptRow,
  quitAll,
  ready,
  send,
  statusRow,
  until,
  withWindow,
} from './render.tsx';
import type { ClipboardWriteResult } from '@opentui/core';
import {
  answered,
  clipboard,
  dragOver,
  NOT_ATTEMPTED,
  REPLY,
} from './selecting.ts';

describe('tester: selection window boundaries', () => {
  test('the transcript remains selectable after the fake agent exits', () => {
    const { copies, copy } = clipboard();

    return withWindow(
      async (window) => {
        await send(window, 'crash');
        await until(
          'the fake agent to exit',
          async () => !(await isAlive(window.pids[0]!)),
        );
        await dragOver(window, 'crash');
        await window.press(CTRL_C);
        await window.shows('copied 5 chars to clipboard');
        expect(copies.map(({ text }) => text)).toStrictEqual(['crash']);
      },
      { copy, copyOnSelect: false },
    );
  });

  test('a narrow failed copy keeps its selection for a successful retry', () => {
    const { copies, copy } = clipboard(
      () => {
        throw new Error('clipboard closed');
      },
      answered({
        host: { status: 'unsupported' },
        terminal: { status: 'attempted', capability: 'supported' },
      }),
    );

    return withWindow(
      async (window) => {
        await send(window, 'text');
        await window.shows(REPLY);
        await dragOver(window, REPLY);
        await window.shows(
          'could not copy: clipboard closed · ctrl + c to try again',
        );
        expect(window.selected()).toBe(REPLY);
        await window.press(CTRL_C);
        await window.shows("sent 26 chars to the terminal's clipboard");
        expect(window.selected()).toBe('');
        expect(copies.map(({ text }) => text)).toStrictEqual([REPLY, REPLY]);
      },
      { copy, columns: 80, rows: 24 },
    );
  });

  test('a late copy from a cleared tab leaves the next session untouched', () => {
    const pending = Promise.withResolvers<ClipboardWriteResult>();
    const { copies, copy } = clipboard(() => pending.promise);

    return withWindow(
      async (window) => {
        await send(window, 'text');
        await window.shows(REPLY);
        await dragOver(window, REPLY);
        await until('the pending copy', () => copies.length === 1);
        await leader(window, 'c');
        await ready(window);
        expect(window.selected()).toBe('');
        pending.resolve({
          host: { status: 'written' },
          terminal: NOT_ATTEMPTED,
        });
        await window.press('\x1b[F');
        expect(statusRow(window)).not.toContain('copied');
        await leader(window, '1');
        await window.shows(REPLY);
        expect(window.selected()).toBe('');
        expect(statusRow(window)).not.toContain('copied');
      },
      { copy },
    );
  });

  test('copying with a form open leaves the form waiting', () => {
    const { copies, copy } = clipboard();

    return withWindow(
      async (window) => {
        await send(window, 'form');
        await inputAsked(window);
        await dragOver(window, 'form');
        await window.press(CTRL_C);
        await window.shows('copied 4 chars to clipboard');
        await inputAsked(window);
        expect(copies.map(({ text }) => text)).toStrictEqual(['form']);
        expect(window.frame()).not.toContain('again to');
      },
      { copy, copyOnSelect: false, columns: 80, rows: 24 },
    );
  });

  test('a hung turn still copies, cancels and closes its fake agent', () => {
    const { copies, copy } = clipboard();

    return withWindow(
      async (window) => {
        await ready(window);
        await send(window, 'hold');
        await window.shows('Working');
        await dragOver(window, 'hold');
        await window.press(CTRL_C);
        await window.shows('copied 4 chars to clipboard');
        expect(copies.map(({ text }) => text)).toStrictEqual(['hold']);
        await window.press(ESC);
        await quitAll(window);
      },
      {
        copy,
        copyOnSelect: false,
        agentCommand: fakeAgentCommand(undefined, '--hang', 'turn'),
      },
    );
  });

  test('an empty paste clears a draft selection without replacing its text', () =>
    withWindow(
      async (window) => {
        await ready(window);
        await window.type('keep the entire draft');
        await dragOver(window, 'entire');
        expect(window.selected()).toBe('entire');
        await window.paste('');
        await until('the empty paste to clear', () => window.selected() === '');
        expect(promptRow(window)).toContain('keep the entire draft');
      },
      {
        copyOnSelect: false,
        clipboard: () => Promise.resolve({ failed: 'empty test clipboard' }),
      },
    ));

  test('late output preserves a selection and copies the highlighted text', () => {
    const { copies, copy } = clipboard();

    return withWindow(
      async (window) => {
        await send(window, 'late');
        await window.shows('Answered.');
        await dragOver(window, 'Answered.');
        await window.shows('Late, after the answer.');

        const selected = window.selected();

        expect(selected).toBe('Answered.');
        await window.press(CTRL_C);
        await window.shows('copied 9 chars to clipboard');
        expect(copies.map(({ text }) => text)).toStrictEqual([selected]);
      },
      {
        copy,
        copyOnSelect: false,
        agentCommand: fakeAgentCommand(undefined, '--step-ms', '150'),
      },
    );
  });
});

describe('tester: selection after the auto-copy note', () => {
  test('a narrow draft keeps its highlight after the note, then a typed key clears it and the hint', () => {
    const { copies, copy } = clipboard();

    return withWindow(
      async (window) => {
        await ready(window);
        await window.type('keep this draft');
        await dragOver(window, 'this');
        await window.shows('copied 4 chars to clipboard');
        await window.shows('ctrl + c to copy');
        expect(window.selected()).toBe('this');
        await window.type('!');
        await until(
          'the key to clear the selection',
          () =>
            window.selected() === '' &&
            !statusRow(window).includes('ctrl + c to copy'),
        );
        expect(promptRow(window)).toContain('keep thi!s draft');
        expect(copies.map(({ text }) => text)).toStrictEqual(['this']);
      },
      { copy, columns: 80, rows: 24 },
    );
  });

  test('an auto-copied selection holds its mounted text beyond the note under 150 new entries', () => {
    const { copies, copy } = clipboard();

    return withWindow(
      async (window) => {
        await send(window, 'text');
        await window.shows(REPLY);
        await send(window, 'stepslater');
        await dragOver(window, REPLY);
        await window.shows('copied 26 chars to clipboard');
        await window.shows('ctrl + c to copy');
        await until('the last call', () => window.mounted('step-150.ts'));
        expect(window.mounted(REPLY)).toBe(true);
        expect(window.selected()).toBe(REPLY);
        await window.press(CTRL_C);
        await until(
          'the retained text to copy again',
          () => copies.length === 2,
        );
        expect(copies.map(({ text }) => text)).toStrictEqual([REPLY, REPLY]);
        expect(window.selected()).toBe('');
      },
      { copy, agentCommand: fakeAgentCommand(undefined, '--step-ms', '20') },
    );
  });

  test('an auto-copy failure keeps its note and selection beyond a successful note lifetime', () => {
    const { copies, copy } = clipboard(() =>
      Promise.reject(new Error('test clipboard unavailable')),
    );

    return withWindow(
      async (window) => {
        await send(window, 'text');
        await window.shows(REPLY);
        await dragOver(window, REPLY);
        await window.shows('could not copy: test clipboard unavailable');
        // A failure has no expiry event to await; observe beyond the 3 s bound.
        await new Promise((resolve) => setTimeout(resolve, 3_200));
        expect(statusRow(window)).toContain(
          'could not copy: test clipboard unavailable',
        );
        expect(window.selected()).toBe(REPLY);
        await window.press(CTRL_C);
        await window.shows('copied 26 chars to clipboard');
        expect(copies.map(({ text }) => text)).toStrictEqual([REPLY, REPLY]);
        expect(window.selected()).toBe('');
      },
      { copy },
    );
  });
});
