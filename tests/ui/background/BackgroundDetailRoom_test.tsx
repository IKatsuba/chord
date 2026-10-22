/**
 * An agent's detail in a short window, one row tall, under a request, and
 * as its work goes on (CHD-487).
 */
import { describe, expect, setSystemTime, test } from 'bun:test';
import assert from 'node:assert/strict';
import { useState } from 'react';
import type { Subagent } from '../../../src/session/transcript/types.ts';
import type { RequestScroller } from '../../../src/ui/dialogs/Permission.tsx';
import { BackgroundView } from '../../../src/ui/background/BackgroundView.tsx';
import { draw } from '../harness.tsx';
import { fakeAgentCommand } from '../../fixtures/fake.ts';
import {
  DOWN,
  END,
  ESC,
  promptRow,
  ready,
  send,
  until,
  type Window,
  withWindow,
} from '../app/render.tsx';
import { withBackground } from './background_window.tsx';

describe("an agent's detail in a short window keeps the frame within its cap (CHD-487)", () => {
  test("at 80x18 the work is one row, its count beside it; at 80x16 none, its count at the state line's end; the hint and the prompt always shown", () =>
    withWindow(
      async (window) => {
        const frame = () =>
          window.frame().slice(window.frame().indexOf('Background · '));

        await send(window, 'claudebackground');
        await window.shows("background  main's 2 agents running");
        await window.press(DOWN);
        await window.press('\r');
        await window.shows('❯ Run the test suite');
        await window.press('\r');
        await window.shows('Background · 1 of 1 · ended');
        await window.shows('⏺ Every test passed.');

        await window.resize({ columns: 80, rows: 18 });
        await until('a lone row with its count', () =>
          / ↑ \d+ lines? above\s*│/.test(frame()),
        );
        expect(frame()).not.toContain('── ↑');
        expect(window.frame()).toContain('Enter to go to its call');
        expect(window.frame()).toContain('│ ›');

        await window.resize({ columns: 80, rows: 16 });
        await until('the count on the state line', () =>
          /✓ done in \d+s · .*↑ \d+ lines? above/.test(frame()),
        );
        expect(window.frame()).toContain('Enter to go to its call');
        expect(window.frame()).toContain('│ ›');
        await window.press('\x1b[5~');
        await until('paged with no row', () =>
          /↓ \d+ (lines? )?below/.test(frame()),
        );
      },
      { rows: 24, columns: 80 },
    ));

  test("opened at 80x16, never a row tall, its count is at the state line's end all the same", () =>
    withWindow(
      async (window) => {
        const frame = () =>
          window.frame().slice(window.frame().indexOf('Background · '));

        await send(window, 'claudebackground');
        await window.shows("background  main's 2 agents running");
        await window.press(DOWN);
        await window.press('\r');
        await window.shows('❯ Run the test suite');
        await window.press('\r');
        await window.shows('Background · 1 of 1 · ended');
        await until('the count on the state line', () =>
          /✓ done in \d+s · .*↑ \d+ lines? above/.test(frame()),
        );
        // Laid out to be counted, none of its work is drawn.
        expect(frame()).not.toContain('⏺ Every test passed.');
        await window.press('\x1b[5~');
        await until('paged with no row', () =>
          /↓ \d+ (lines? )?below/.test(frame()),
        );
        // Given a row, it draws its work in it, its count beside it.
        await window.resize({ columns: 80, rows: 18 });
        await window.press(END);
        await until('the last line in the one row', () =>
          /⏺ Every test passed\.\s+↑ \d+ lines? above/.test(frame()),
        );
      },
      { rows: 16, columns: 80 },
    ));

  test('where its work is read stays as its row goes and comes back, with no key pressed after', () =>
    withWindow(
      async (window) => {
        const frame = () =>
          window.frame().slice(window.frame().indexOf('Background · '));

        await send(window, 'claudebackground');
        await window.shows("background  main's 2 agents running");
        await window.press(DOWN);
        await window.press('\r');
        await window.shows('❯ Run the test suite');
        await window.press('\r');
        await window.shows('Background · 1 of 1 · ended');
        await until('at its end', () =>
          /⏺ Every test passed\.\s+↑ \d+ lines? above/.test(frame()),
        );

        // To its top with no row, then a row given back.
        await window.resize({ columns: 80, rows: 16 });
        await until('the count on the state line', () =>
          /✓ done in \d+s · .*↑ \d+ lines? above/.test(frame()),
        );
        await window.press('\x1b[H');
        await until('at its top with no row', () =>
          /✓ done in \d+s · .*↓ \d+ lines? below/.test(frame()),
        );
        await window.resize({ columns: 80, rows: 18 });
        await until('its top in the one row', () =>
          /│ › Run bun test.*↓ \d+ lines? below/.test(frame()),
        );

        // Within it, three pages up from the end, through no row and back:
        // more than a line from the end at either width, which wrap wider
        // with no row. Within a line of it, a scrollbox whose lines change
        // follows the end again, as OpenTUI's does.
        await window.press(END);
        await window.press('\x1b[5~');
        await window.press('\x1b[5~');
        await window.press('\x1b[5~');
        await until('three pages up from its end', () =>
          /↑ \d+ above · ↓ 3 below/.test(frame()),
        );

        const paged = frame().match(/↑ \d+ above · ↓ 3 below/)![0];

        await window.resize({ columns: 80, rows: 16 });
        await until('within it with no row', () =>
          /✓ done in \d+s · .*↓ \d+ (lines? )?below/.test(frame()),
        );
        await window.resize({ columns: 80, rows: 18 });
        await until('the same page in the one row', () =>
          frame().includes(paged),
        );
        expect(frame()).not.toContain('⏺ Every test passed.');
      },
      { rows: 18, columns: 80 },
    ));
});

test('a detail one row tall pages its log to its last line, its blocks spaced so the scrollbox counts them (opentui#1739, CHD-487)', () =>
  withWindow(
    async (window) => {
      const frame = () =>
        window.frame().slice(window.frame().indexOf('Background · '));

      await send(window, 'claudebackground');
      await window.shows("background  main's 2 agents running");
      await window.press(DOWN);
      await window.press('\r');
      await window.shows('❯ Run the test suite');
      await window.press('\r');
      await window.shows('Background · 1 of 1 · ended');
      await window.shows('⏺ Every test passed.');
      await window.resize({ columns: 80, rows: 18 });
      // At its end, its last line in the one row.
      await window.press(END);
      await until('the last line in the one row', () =>
        /⏺ Every test passed\.\s+↑ \d+ lines? above/.test(frame()),
      );
      // To its top and back down a line at a time, every line reached.
      await window.press('\x1b[H');
      await window.shows('› Run bun test');

      for (
        let step = 0;
        step < 12 && !/Every test passed/.test(frame());
        step++
      ) {
        await window.press('\x1b[6~');
      }

      expect(frame()).toContain('⏺ Every test passed.');
    },
    { rows: 24, columns: 80 },
  ));

describe('a request asked while the view is open hides it, and it comes back where it was read (CHD-481, CHD-487)', () => {
  /** Asks the front session's permission, and answers it from its box. */
  async function askAndAnswer(window: Window) {
    const session = window.session();

    assert(session);

    const abort = new AbortController();
    const answer = session.permissions.handler(
      {
        sessionId: session.id,
        toolCall: { toolCallId: 'asked-over-view', title: 'Write notes.md' },
        options: [{ optionId: 'allow', name: 'Allow', kind: 'allow_once' }],
      },
      abort.signal,
    );

    try {
      await window.shows('Do you want to proceed?');
      expect(window.frame()).not.toContain('Background ·');
      await window.press('1');
      expect(await answer).toEqual({
        outcome: { outcome: 'selected', optionId: 'allow' },
      });
    } finally {
      abort.abort();
    }
  }

  test("an agent's log paged to its top", () =>
    withWindow(
      async (window) => {
        const frame = () =>
          window.frame().slice(window.frame().indexOf('Background · '));

        await send(window, 'claudebackground');
        await window.shows("background  main's 2 agents running");
        await window.press(DOWN);
        await window.press('\r');
        await window.shows('❯ Run the test suite');
        await window.press('\r');
        await window.shows('⏺ Bash(bun test)');
        await window.resize({ columns: 80, rows: 18 });
        await window.press('\x1b[H');
        await until('at its top in the one row', () =>
          /│ › Run bun test.*↓ \d+ lines? below/.test(frame()),
        );

        const read = frame().match(/↓ \d+ lines? below/)![0];

        await askAndAnswer(window);
        await until('back at its top', () => /│ › Run bun test/.test(frame()));
        expect(frame()).toContain(read);
      },
      {
        rows: 24,
        columns: 80,
        agentCommand: fakeAgentCommand(undefined, '--step-ms', '20'),
      },
    ));

  // The detail says its event's age, which a slow answer would move on:
  // chord's clock held from before the window opens, so every frame says
  // the age at the held time, and let go after (CHD-501).
  test("a monitor's detail paged down", async () => {
    setSystemTime(new Date());

    try {
      await withBackground(
        async (window) => {
          const body = () =>
            window
              .frame()
              .split('\n')
              .filter((line) => line.startsWith('│'))
              .join('\n');

          await ready(window);
          await send(window, 'monitors');
          await window.shows(
            'Received the message from dev server errors · monitor.',
          );
          // The request is asked in a turn, as one between turns is held.
          await send(window, 'slow');
          await window.shows('esc to interrupt');
          await window.press(DOWN);
          await window.press('\r');
          await window.shows('Background · 2 in this tab');
          await window.press('\r');
          await window.shows('Background · m1, 1 of 2');
          await window.press('\x1b[6~');
          await until(
            'the description paged away',
            () => !body().includes('dev server errors'),
          );

          const read = body();

          await askAndAnswer(window);
          await window.shows('Background · m1, 1 of 2');
          expect(body()).toBe(read);
        },
        { rows: 24, columns: 80 },
      );
    } finally {
      setSystemTime();
    }
  });
});

describe('CHD-487 U2 tester: live work, metadata and dialog isolation', () => {
  for (const [columns, rows] of [
    [80, 24],
    [120, 40],
  ] as const) {
    test(`rebound top survives a permission and form, then rebound End finds the live tail at ${columns} columns`, () =>
      withWindow(
        async (window) => {
          const body = () =>
            window.frame().slice(window.frame().indexOf('Background · '));

          await send(window, 'claudebackground');
          await window.shows("background  main's 2 agents running");
          await window.press(DOWN);
          await window.press('\r');
          await window.shows('❯ Run the test suite');
          await window.press('\r');
          await window.shows('⏺ Bash(bun test)');
          await window.resize({ columns: 80, rows: 18 });
          await window.press('\x02');
          await until('task at the top', () =>
            body().includes('› Run bun test'),
          );
          expect(window.frame()).toContain('esc to interrupt');
          expect(body()).toContain('› Run bun test');
          expect(body()).not.toContain('⏺ Every test passed.');

          const session = window.session();

          assert(session);

          const abort = new AbortController();
          let answered = false;
          const answer = session.permissions
            .handler(
              {
                sessionId: session.id,
                toolCall: {
                  toolCallId: 'detail-attendance',
                  title: 'Write attendance.md',
                },
                options: [
                  { optionId: 'allow', name: 'Allow', kind: 'allow_once' },
                ],
              },
              abort.signal,
            )
            .then((result) => {
              answered = true;

              return result;
            });

          try {
            await window.shows('Do you want to proceed?');
            expect(window.frame()).not.toContain('Background ·');
            await window.press('1');
            await until('the permission answered', () => answered);
            expect(await answer).toEqual({
              outcome: { outcome: 'selected', optionId: 'allow' },
            });
            await until('same detail page restored', () =>
              body().includes('› Run bun test'),
            );

            const formAbort = new AbortController();
            const form = session.elicitations.handler(
              {
                sessionId: session.id,
                mode: 'form',
                message: 'Incoming detail form',
                requestedSchema: {
                  type: 'object',
                  properties: {
                    name: { type: 'string', title: 'Project name' },
                  },
                  required: ['name'],
                },
              },
              formAbort.signal,
            );

            try {
              await window.shows('❯ * Project name');
              expect(window.frame()).not.toContain('Background ·');
              await window.press(ESC);
              expect(await form).toMatchObject({ action: 'cancel' });
              await until('same page after form', () =>
                body().includes('› Run bun test'),
              );
            } finally {
              formAbort.abort();
              await form;
            }

            expect(body()).not.toContain('⏺ Every test passed.');
            await window.press('\x05');
            await until('rebound End reaches newest work', () =>
              /⎿ +Running…/.test(body()),
            );
            await window.press(ESC);
            await window.shows('Enter for details');
            await window.press(ESC);
            await until(
              'view closed after returning to the list',
              () => !window.frame().includes('Background ·'),
            );
            await window.press(ESC);
            await until(
              'summary releases the keys',
              () => !window.frame().includes('❯ background'),
            );
            await window.type('draft after detail');
            await until(
              'draft typed after detail',
              () => promptRow(window)?.includes('draft after detail') === true,
            );
          } finally {
            abort.abort();
            await answer;
          }
        },
        {
          columns,
          rows,
          agentCommand: fakeAgentCommand(undefined, '--step-ms', '20'),
          keybindings: JSON.stringify({
            bindings: [
              {
                context: 'Scroll',
                bindings: {
                  home: null,
                  end: null,
                  'ctrl+b': 'scroll:top',
                  'ctrl+e': 'scroll:bottom',
                },
              },
            ],
          }),
        },
      ));
  }

  for (const [columns, rows] of [
    [80, 20],
    [120, 40],
  ] as const) {
    test(`a long-model task follows growth, pauses at its top and keeps nested work folded at ${columns}x${rows}`, async () => {
      const scroller: { current: RequestScroller | undefined } = {
        current: undefined,
      };
      const item = {
        kind: 'task' as const,
        id: 'task',
        key: 1,
        name: 'Analyse 日本語 ' + 'long task '.repeat(15),
        runtime: 'runtime-' + 'long'.repeat(10),
        model: 'model-' + '日本語'.repeat(20),
        startedAt: Date.now(),
        status: { group: 'running' as const },
      };
      const initial: Subagent = {
        id: 'task',
        state: 'running',
        plan: [],
        prompt: 'Whole task 日本語: preserve every line.',
        entries: Array.from({ length: 12 }, (_, n) => ({
          kind: 'assistant' as const,
          turnId: 't',
          text: `Work row ${n} 日本語`,
        })),
      };
      let update: ((value: Subagent) => void) | undefined;

      function View() {
        const [subagent, set] = useState(initial);

        update = set;

        return (
          <BackgroundView
            items={[item]}
            focus={item}
            detail={item}
            columns={columns}
            rows={rows}
            scroller={scroller}
            work={{ subagent, turn: { status: 'idle' }, agent: 'fake' }}
          />
        );
      }

      const drawn = await draw(<View />, { columns, rows });

      try {
        await until('initial newest work', () =>
          drawn.frame().includes('Work row 11'),
        );
        assert(update);

        const grown: Subagent = {
          ...initial,
          entries: [
            ...initial.entries,
            {
              kind: 'subagent',
              turnId: 't',
              subagent: {
                id: 'nested',
                title: 'Nested helper',
                state: 'completed',
                entries: [
                  {
                    kind: 'assistant',
                    turnId: 'n',
                    text: 'HIDDEN NESTED INTERNAL',
                  },
                ],
                plan: [],
              },
            },
            { kind: 'assistant', turnId: 't', text: 'First live tail 日本語' },
          ],
        };

        update(grown);
        await until('following appended work', () =>
          drawn.frame().includes('First live tail'),
        );
        scroller.current?.('top');
        await until('whole task at top', () =>
          drawn.frame().includes('Whole task 日本語'),
        );
        update({
          ...grown,
          entries: [
            ...grown.entries,
            { kind: 'assistant', turnId: 't', text: 'Second live tail 日本語' },
          ],
        });
        await until('update laid out without leaving top', () =>
          drawn.mounted('Second live tail 日本語'),
        );
        expect(drawn.frame()).toContain('Whole task 日本語');
        expect(drawn.frame()).not.toContain('Second live tail');

        let seen = drawn.frame();

        for (
          let n = 0;
          n < 100 && !drawn.frame().includes('Second live tail');
          n++
        ) {
          const before = drawn.frame();

          scroller.current?.('line_down');
          await until(
            'the next work line drawn',
            () => drawn.frame() !== before,
          );

          seen += drawn.frame();
        }

        expect(seen).toContain('Nested helper');
        expect(seen).not.toContain('HIDDEN NESTED INTERNAL');
        expect(drawn.frame()).toContain('Second live tail');
        expect(drawn.frame()).toContain('Enter to go to its call');
      } finally {
        await drawn.unmount();
      }
    });
  }
});
