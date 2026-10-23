import { describe, expect, test } from 'bun:test';
import assert from 'node:assert/strict';
import { mkdir, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import {
  GATE,
  GATE_RELEASE,
} from '../../fixtures/fake_agent/scenarios/agents.ts';
import { fakeAgentCommand } from '../../fixtures/fake.ts';
import {
  asked,
  CTRL_C,
  left,
  promptRow,
  quitAll,
  ready,
  send,
  statusRow,
  until,
  type Window,
  withWindow,
} from './render.tsx';
import type { ClipboardWriteResult } from '@opentui/core';
import stripAnsi from 'strip-ansi';
import {
  answered,
  cellsOf,
  clipboard,
  dragOver,
  NOT_ATTEMPTED,
  REPLY,
} from './selecting.ts';

/** The left button down on `text`'s first cell. */
async function pressOn(window: Window, text: string): Promise<void> {
  const { x, y } = cellsOf(window, text);

  await window.press(left(x, y, 'down'));
}

describe('a selection (CHD-172)', () => {
  test('a drag highlights, release copies and says so alone, and the note goes after 3 s while the highlight stays for ctrl+c', () => {
    const { copies, copy } = clipboard();

    return withWindow(
      async (window) => {
        await send(window, 'text');
        await window.shows(REPLY);

        // A click selects nothing and copies nothing.
        await pressOn(window, REPLY);
        await window.press(
          left(cellsOf(window, REPLY).x, cellsOf(window, REPLY).y, 'up'),
        );
        expect(window.selected()).toStrictEqual('');

        await dragOver(window, REPLY);
        await window.shows('copied 26 chars to clipboard');
        expect(window.selected()).toStrictEqual(REPLY);
        expect(copies.map(({ text }) => text)).toStrictEqual([REPLY]);
        // Alone: the model and the usage give way to it.
        expect(statusRow(window).trim()).toStrictEqual(
          'copied 26 chars to clipboard',
        );

        await until(
          'the note to go',
          () => !window.frame().includes('copied 26'),
          5_000,
        );
        expect(window.selected()).toStrictEqual(REPLY);
        // The selection's hint stands in the note's place, the model back.
        await window.shows('ctrl + c to copy');
        expect(statusRow(window)).toContain('Fake Large');

        await window.press(CTRL_C);
        await until('the copy key to copy', () => copies.length === 2);
        expect(copies.map(({ text }) => text)).toStrictEqual([REPLY, REPLY]);
        expect(window.selected()).toStrictEqual('');
      },
      { copy },
    );
  });

  test('with copyOnSelect off the selection waits, the line says ctrl + c, and ctrl+c copies it', () => {
    const { copies, copy } = clipboard();

    return withWindow(
      async (window) => {
        await send(window, 'text');
        await window.shows(REPLY);
        await dragOver(window, REPLY);
        await window.shows('ctrl + c to copy');
        // The hint takes the shortcuts' place; the model stays.
        expect(statusRow(window)).toContain('Fake Large');
        expect(copies).toStrictEqual([]);

        await window.press(CTRL_C);
        await window.shows('copied 26 chars to clipboard');
        expect(copies.map(({ text }) => text)).toStrictEqual([REPLY]);
        // The copy key's selection has done its work.
        expect(window.selected()).toStrictEqual('');
        // Nothing else happened: no quit armed.
        expect(window.frame()).not.toContain('again to');
      },
      { copy, copyOnSelect: false },
    );
  });

  test('each failure is said in place of the note, and the selection stays for ctrl+c', () => {
    const { copies, copy } = clipboard(
      answered({ host: { status: 'timed-out' }, terminal: NOT_ATTEMPTED }),
      () =>
        Promise.reject(
          new RangeError('writeText exceeds the configured 8388608 byte limit'),
        ),
      answered({
        host: { status: 'failed', error: new Error('no\npasteboard') },
        terminal: { status: 'local-failure', capability: 'unknown' },
      }),
      answered({
        host: { status: 'failed', error: new Error('no pasteboard') },
        terminal: { status: 'attempted', capability: 'supported' },
      }),
    );

    return withWindow(
      async (window) => {
        await send(window, 'text');
        await window.shows(REPLY);
        await dragOver(window, REPLY);

        for (const note of [
          'could not copy: the clipboard did not answer · ctrl + c to try again',
          'could not copy: too large to copy · ctrl + c to try again',
          'could not copy: no pasteboard · ctrl + c to try again',
        ]) {
          await window.shows(note);
          expect(statusRow(window).trim()).toStrictEqual(note);
          expect(window.selected()).toStrictEqual(REPLY);
          await window.press(CTRL_C);
        }

        await window.shows("sent 26 chars to the terminal's clipboard");
        expect(copies.length).toStrictEqual(4);
      },
      { copy },
    );
  });

  test('a copy superseded says nothing, one unanswered times out, and quit waits on none', () => {
    let settle: ((result: ClipboardWriteResult) => void) | undefined;
    const { copies, copy } = clipboard(
      () => new Promise((resolve) => (settle = resolve)),
      () => new Promise(() => {}),
      () => new Promise(() => {}),
    );

    return withWindow(
      async (window) => {
        await send(window, 'text');
        await window.shows(REPLY);
        await dragOver(window, REPLY);
        await until('the first copy', () => copies.length === 1);
        // A new drag's copy supersedes the first, which says nothing late.
        await dragOver(window, 'This reply');
        await until('the second copy', () => copies.length === 2);
        expect(copies[0]!.signal.aborted).toBe(true);
        settle!({ host: { status: 'written' }, terminal: NOT_ATTEMPTED });
        // The second never answers: chord's bound says so.
        await window.shows('could not copy: the clipboard did not answer');
        expect(window.frame()).not.toContain('copied 26');

        // A third, left out, is aborted by the quit, which does not wait.
        await window.press(CTRL_C);
        await until('the third copy', () => copies.length === 3);
        await quitAll(window);
        expect(copies[2]!.signal.aborted).toBe(true);
      },
      { copy },
    );
  });

  test('a key or a paste over a selection in the draft clears it first and goes in at the cursor', () =>
    withWindow(
      async (window) => {
        await ready(window);
        await window.type('a draft I am still typing');
        await window.shows('› a draft I am still typing');
        await dragOver(window, 'draft I am sti');
        expect(window.selected()).toStrictEqual('draft I am sti');

        // It goes in where the drag left the cursor, and replaces nothing.
        await window.type('Q');
        await until('the key typed', () => promptRow(window)!.includes('Q'));
        expect(promptRow(window)!.replace('Q', '')).toContain(
          '› a draft I am still typing',
        );
        expect(window.selected()).toStrictEqual('');

        await dragOver(window, 'draft I am');
        await window.paste('Z');
        await until('the paste', () => promptRow(window)!.includes('Z'));
        expect(promptRow(window)!.replace(/[QZ]/g, '')).toContain(
          '› a draft I am still typing',
        );
        expect(window.selected()).toStrictEqual('');
      },
      { copyOnSelect: false },
    ));

  test('ctrl+c with a permission open copies, and once the selection has gone does what it did', () => {
    const { copies, copy } = clipboard();

    return withWindow(
      async (window) => {
        await send(window, 'permission');
        await asked(window);
        await dragOver(window, 'permission');
        await window.press(CTRL_C);
        await window.shows('copied 10 chars to clipboard');
        expect(copies.map(({ text }) => text)).toStrictEqual(['permission']);
        // The box is still there to answer.
        await asked(window);

        // The selection gone, ctrl+c is the window's again: quit, armed.
        await window.press(CTRL_C);
        await window.shows('again to');
        expect(copies.length).toStrictEqual(1);
      },
      { copy, copyOnSelect: false },
    );
  });

  test('a press stops the view following, and release brings it back unless the wheel moved it', () =>
    withWindow(
      async (window) => {
        /**
         * The text of the last of the reply's items on screen, which the
         * stream moves; its marker is no place to start a selection.
         */
        const lastLine = () => {
          const lines = stripAnsi(window.frame()).match(/Line \d+ of/g);

          assert(lines !== null, 'no line of the reply on screen');

          return lines.at(-1)!;
        };

        await send(window, 'long');
        await window.shows('20. Line 20');

        const held = lastLine();
        const { y, end } = cellsOf(window, held);

        await pressOn(window, held);
        // New output goes below the view while the button is down.
        await window.shows('new output');
        await window.press(left(end, y, 'up'));
        await until(
          'the view to follow again',
          () => !window.frame().includes('new output'),
        );

        const next = cellsOf(window, lastLine());

        await window.press(left(next.x, next.y, 'down'));
        await window.press(left(next.end, next.y, 'drag'));

        const before = window.selected();

        // A wheel step during the drag moves the text under the pointer,
        // and the selection reaches the cell it is over now.
        await window.press(`\x1b[<64;${next.end + 1};${next.y + 1}M`);
        await until(
          'the selection to grow',
          () => window.selected() !== before,
        );
        await window.press(left(next.end, next.y, 'up'));
        // The person moved the view, so it stays where they left it.
        await window.shows('lines below');
        await new Promise((resolve) => setTimeout(resolve, 300));
        expect(window.frame()).toContain('lines below');
      },
      { copyOnSelect: false },
    ));

  test('a press with no output under it draws no rule, held or released (CHD-397)', () =>
    withWindow(async (window) => {
      await send(window, 'text');
      await window.shows(REPLY);
      await until('the turn to end', () => !window.frame().includes('Working'));

      const { y, end } = cellsOf(window, REPLY);

      await pressOn(window, REPLY);
      await new Promise((resolve) => setTimeout(resolve, 100));
      expect(window.frame()).not.toContain('below');
      await window.press(left(end, y, 'up'));
      await new Promise((resolve) => setTimeout(resolve, 100));
      expect(window.frame()).not.toContain('below');
    }));

  test('a click on a reply taller than the view selects and copies nothing (CHD-410)', () => {
    const { copies, copy } = clipboard();

    return withWindow(
      async (window) => {
        await send(window, 'markdown');
        await window.shows('echo "built $bin"');
        await until(
          'the turn to end',
          () => !window.frame().includes('Working'),
        );

        const line = 'That is the whole loop.';
        const { x, y } = cellsOf(window, line);

        await window.press(left(x + 5, y, 'down'));
        await new Promise((resolve) => setTimeout(resolve, 100));
        expect(window.selected()).toBe('');
        await window.press(left(x + 5, y, 'up'));
        await new Promise((resolve) => setTimeout(resolve, 100));
        expect(window.selected()).toBe('');
        expect(copies).toStrictEqual([]);
      },
      { copy },
    );
  });

  test('a selection held keeps its text mounted under 150 more entries', () =>
    withWindow(
      async (window) => {
        await send(window, 'text');
        await window.shows(REPLY);
        await send(window, 'stepslater');
        // Selected before the calls come, with no key after to clear it.
        await dragOver(window, REPLY);
        await until(
          'the last call',
          () => window.mounted('step-150.ts'),
          30_000,
        );
        expect(window.mounted(REPLY)).toBe(true);
        expect(window.selected()).toStrictEqual(REPLY);
      },
      { copyOnSelect: false },
    ));

  test('with "mouse": false chord selects and copies nothing', () => {
    const { copies, copy } = clipboard();

    return withWindow(
      async (window) => {
        await send(window, 'text');
        await window.shows(REPLY);
        await dragOver(window, REPLY);
        expect(window.selected()).toStrictEqual('');
        expect(copies).toStrictEqual([]);
        expect(window.frame()).not.toContain('copied');
      },
      { copy, mouse: false },
    );
  });
});

test('a resize clears a selection, as its text rewraps (CHD-172)', () =>
  withWindow(
    async (window) => {
      await send(window, 'text');
      await window.shows(REPLY);
      await dragOver(window, REPLY);
      await window.shows('ctrl + c to copy');
      await window.resize({ columns: 90 });
      await until('the selection to go', () => window.selected() === '');
      await window.shows('? for shortcuts');
    },
    { copyOnSelect: false },
  ));

test("a selection whose text has gone is cleared, and ctrl+c is the window's again (CHD-172)", () =>
  withWindow(
    async (window) => {
      // The step goes once the test says so, so it is selected before it
      // goes however slow the drag is (CHD-399).
      await send(window, 'planshrinkgated');
      await window.shows('◐ Read the code');
      await dragOver(window, 'Read the code');
      await window.shows('ctrl + c to copy');
      await mkdir(join(window.dir, GATE), { recursive: true });
      await writeFile(join(window.dir, GATE, GATE_RELEASE), '');
      await window.shows('Dropped a step.');
      // The step and its text went with the drop, and the hint with them.
      await until(
        'the hint to go',
        () => !window.frame().includes('ctrl + c to copy'),
      );
      expect(window.selected()).toStrictEqual('');

      // During the turn, as with no selection ever made: quit, armed.
      await window.press(CTRL_C);
      await window.shows('again to');
    },
    {
      copyOnSelect: false,
      agentCommand: fakeAgentCommand(undefined, '--step-ms', '20'),
    },
  ));

test('a resize mid-drag lets go of the view, which follows again (CHD-172)', () =>
  withWindow(
    async (window) => {
      await send(window, 'long');
      await window.shows('20. Line 20');

      // An item's text, past its marker, where a press starts a selection.
      const lines = stripAnsi(window.frame()).match(/Line \d+ of/g)!;

      await pressOn(window, lines.at(-1)!);
      await window.shows('new output');
      await window.resize({ columns: 90 });
      await until(
        'the view to follow again',
        () => !window.frame().includes('new output'),
      );
      expect(window.selected()).toStrictEqual('');
    },
    { copyOnSelect: false },
  ));
