/** The plan box on the fake: cursor's and grok's plans put to the person. */
import { describe, expect, test } from 'bun:test';
import {
  DOWN,
  ESC,
  UP,
  ready,
  send,
  until,
  withWindow,
} from '../app/render.tsx';

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
      // OpenTUI may wrap the reply inside a word (after `.`, as in
      // `connection.ts`), so the rows are read with no whitespace at all.
      expect(window.frame().replace(/\s+/g, '')).toContain(
        JSON.stringify({ outcome: 'rejected', reason: note }).replace(
          /\s+/g,
          '',
        ),
      );
    },
    { rows: 24, columns: 80 },
  ));

test('a note taller than its room at 80x24: the box stays on screen whole, the note pages from the Note, and goes whole (CHD-437)', () =>
  withWindow(
    async (window) => {
      const note = Array.from(
        { length: 40 },
        (_, at) => `step${at} keeps the routing`,
      ).join(' ');
      const box = () => {
        const lines = window.frame().split('\n');
        const top = lines.findIndex((line) => line.includes('Approve Plan'));

        return lines.slice(
          top - 1,
          lines.indexOf(
            lines.find((line, at) => at > top && line.startsWith('╰'))!,
          ) + 1,
        );
      };

      await ready(window);
      await send(window, 'cursorplan');
      await window.shows('Approve Plan');
      await window.press(DOWN);
      await window.press(DOWN);
      await window.paste(note);
      await window.shows('lines above · pageup to scroll');

      // The frame fits the window: its top border, title, choices and hint.
      expect(box()[0]!.startsWith('╭')).toBe(true);
      expect(window.frame().split('\n').length).toBeLessThanOrEqual(24);
      expect(box().join('\n')).toContain('2. No, keep planning');
      expect(box().join('\n')).toContain(
        'Enter to keep planning with this note',
      );
      // The cursor is at the note's end, on its last line.
      expect(box().join('\n')).toContain('step39 keeps the routing');

      // Page by page, up to the note's first line.
      for (
        let page = 0;
        page < 6 && !box().join('\n').includes('step0 ');
        page++
      ) {
        await window.press('\x1b[5~');
      }

      expect(box().join('\n')).toContain('Note  step0 keeps the routing');
      expect(box().join('\n')).toContain('lines below · pagedown to scroll');
      // Typing brings the view back to the cursor.
      await window.type('!');
      await window.shows('step39 keeps the routing!');
      await window.press('\r');
      await window.shows('Plan answer:');
      expect(window.frame().replace(/\s+/g, ' ')).toContain(
        JSON.stringify({ outcome: 'rejected', reason: `${note}!` }),
      );
    },
    { rows: 24, columns: 80 },
  ));

test('a long Note in a window shrunk under it keeps the box inside its border, a lone row saying what it hides (CHD-437)', () =>
  withWindow(
    async (window) => {
      await ready(window);
      await send(window, 'grokplan');
      await window.shows('Approve Plan');
      await window.press(DOWN);
      await window.press(DOWN);
      await window.press(DOWN);
      await window.paste(
        Array.from({ length: 30 }, (_, at) => `word${at} 日本語`).join(' '),
      );
      await window.resize({ columns: 80, rows: 20 });
      await window.shows('lines above');

      const lines = window.frame().split('\n');
      const top = lines.findIndex((line) => line.includes('Approve Plan'));
      const bottom = lines.findIndex(
        (line, at) => at > top && line.startsWith('╰'),
      );
      const box = lines.slice(top, bottom).join('\n');

      // Nothing drawn past the box: its hint inside, the prompt whole below.
      expect(box).toContain('3. No, and leave plan mode');
      expect(box).toContain('Enter to keep planning with this note');
      expect(box).toContain('word29 日本語');
      expect(lines.slice(bottom + 1).join('\n')).not.toContain('word');
      expect(lines.slice(bottom + 1).join('\n')).toContain('│ ›');
    },
    { rows: 24, columns: 80 },
  ));

describe('CHD-437 U2 tester: paging ownership and isolated answers', () => {
  for (const columns of [80, 120]) {
    const rows = columns === 80 ? 24 : 40;

    for (const rebound of [false, true]) {
      test(`the choice pages the transcript, the overflowing Note pages alone, at ${columns} columns (${rebound ? 'rebound' : 'default'})`, () =>
        withWindow(
          async (window) => {
            const up = rebound ? '\x10' : '\x1b[5~';
            const down = rebound ? '\x0e' : '\x1b[6~';
            const note = Array.from(
              { length: 160 },
              (_, i) => `row${i} stays unchanged`,
            ).join(' ');
            const box = () =>
              window.frame().slice(window.frame().indexOf('Approve Plan'));

            await ready(window);
            await send(window, 'steps');
            await window.shows('150 steps read.');
            await until('the long turn is idle', () =>
              window.frame().includes('? for shortcuts'),
            );
            await send(window, 'cursorplan');
            await window.shows('Approve Plan');

            const before = box();

            await window.press(up);
            await until('a transcript row is hidden below', () =>
              window.frame().split('Approve Plan')[0]!.includes('lines below'),
            );
            expect(box()).toBe(before);
            await window.press(down);
            await until(
              'the transcript is back at its end',
              () =>
                !window
                  .frame()
                  .split('Approve Plan')[0]!
                  .includes('lines below'),
            );
            await window.press(DOWN);
            await window.press(DOWN);
            await window.paste(note);
            await window.shows('row159');

            for (let page = 0; page < 50 && !box().includes('row0 '); page++) {
              await window.press(up);
            }

            await window.shows('Note  row0 stays unchanged');
            expect(window.frame()).toContain(
              rebound ? 'ctrl+n to scroll' : 'pagedown to scroll',
            );
            await window.press(UP);
            await window.shows('❯ 2. No, keep planning');

            let heard = '';
            const unsubscribe = window.session()!.subscribe((update) => {
              if (
                update.sessionUpdate === 'agent_message_chunk' &&
                update.content.type === 'text'
              ) {
                heard += update.content.text;
              }
            });

            try {
              await window.press('2');
              await until('the fake heard the entire note', () =>
                heard.includes(
                  JSON.stringify({ outcome: 'rejected', reason: note }),
                ),
              );
            } finally {
              unsubscribe();
            }
          },
          {
            columns,
            rows,
            ...(rebound
              ? {
                  keybindings: JSON.stringify({
                    bindings: [
                      {
                        context: 'Scroll',
                        bindings: {
                          pageup: null,
                          'shift+pageup': null,
                          pagedown: null,
                          'shift+pagedown': null,
                          'ctrl+p': 'scroll:pageUp',
                          'ctrl+n': 'scroll:pageDown',
                        },
                      },
                    ],
                  }),
                }
              : {}),
          },
        ));
    }

    test(`a one-row Note has a count, reaches both ends, and editing restores the tail at ${columns} columns`, () =>
      withWindow(
        async (window) => {
          const note = Array.from(
            { length: 30 },
            (_, i) => `word${i} 日本語`,
          ).join(' ');

          await ready(window);
          await send(window, 'grokplan');
          await window.shows('Approve Plan');

          for (let row = 0; row < 3; row++) {
            await window.press(DOWN);
          }

          await window.paste(note);
          await window.resize({ rows: 20 });
          await window.shows('above');
          expect(window.frame()).toContain('3. No, and leave plan mode');
          expect(window.frame()).toContain('Esc to keep');
          expect(window.frame().split('\n').length).toBeLessThanOrEqual(20);

          for (
            let page = 0;
            page < 60 && !window.frame().includes('Note  word0 ');
            page++
          ) {
            await window.press('\x1b[5~');
          }

          await window.shows('Note  word0 ');
          expect(window.frame()).toContain('below');
          await window.type('!');
          await window.shows('word29 日本語!');
          await window.resize({ rows });
          await window.press('\r');
          await window.shows('Plan answer:');
          expect(window.frame().replace(/\s+/g, '')).toContain(
            JSON.stringify({ outcome: 'revise', feedback: `${note}!` }).replace(
              /\s+/g,
              '',
            ),
          );
        },
        { columns, rows },
      ));

    test(`a Note and its digits cannot answer the waiting form; Esc sends no note at ${columns} columns`, () =>
      withWindow(
        async (window) => {
          await ready(window);
          await send(window, 'planform');
          await window.shows('Approve Plan');
          await window.press(DOWN);
          await window.press(DOWN);
          await window.type('123jk keep this separate');
          await window.shows('123jk keep this separate');
          expect(window.frame()).not.toContain('Name the branch');
          await window.press(ESC);
          await window.shows('Name the branch');
          expect(window.frame()).not.toContain('123jk keep this separate');
          await window.press(ESC);
          await window.shows(
            'Plan answer: {"outcome":"rejected"} · form: cancel',
          );
          await until('the form turn is idle', () =>
            window.frame().includes('? for shortcuts'),
          );
          await send(window, 'grokplanempty');
          await window.shows('has written no plan. Do you want to proceed?');
          expect(window.frame()).not.toContain('123jk keep this separate');
          await window.press('1');
          await window.shows('Plan answer: {"outcome":"approved"}');
        },
        { columns, rows },
      ));
  }
});
