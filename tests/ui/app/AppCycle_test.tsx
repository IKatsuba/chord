/**
 * The window while the agent works on its own after its turn: shown working,
 * its permissions held, Esc stopping it, and what is typed meanwhile.
 */
import { describe, expect, test } from 'bun:test';
import { fakeAgentCommand } from '../../fixtures/fake.ts';
import {
  ESC,
  leader,
  promptRow,
  ready,
  send,
  until,
  withWindow,
} from './render.tsx';

import { OSC9, writes } from './app_window.tsx';

test("an agent's own cycle after its turn shows it working until its end is marked, then the window is as after a turn (CHD-426)", () =>
  withWindow(
    async (window) => {
      await ready(window);
      await send(window, 'claudecycle');
      await window.shows(
        'The build runs in the background; I will read it after.',
      );
      await until('the turn over', () => !window.frame().includes('Working…'));
      // The cycle: the agent at work again with no prompt of the person's.
      await window.shows('Working…');
      await window.shows('The build passed.');
      await until('the cycle over', () => !window.frame().includes('Working…'));
      expect(window.frame()).toContain(
        'The background build ended; reading its log. The build passed.',
      );
    },
    {
      agentCommand: fakeAgentCommand(undefined, '--adapter', 'claude'),
      columns: 120,
      rows: 40,
    },
  ));

test("a permission asked in the agent's own cycle is held: a digit typed is the draft's, ctrl+x a answers it, and the cycle works on to its end (the owner's Q48, CHD-426)", () =>
  withWindow(
    async (window) => {
      await ready(window);
      await send(window, 'claudecycleask');
      await window.shows('main asks · between turns');
      await window.shows('ctrl+x a to answer');
      expect(window.frame()).not.toContain('❯ 1. Allow');

      await window.type('1');
      expect(promptRow(window)).toContain('› 1');
      expect(window.frame()).not.toContain('Permission: allow.');

      await leader(window, 'a');
      await window.shows('❯ 1. Allow');
      await window.press('1');
      await window.shows('Permission: allow.');
      await until('the cycle over', () => !window.frame().includes('Working…'));
      expect(promptRow(window)).toContain('› 1');
    },
    {
      agentCommand: fakeAgentCommand(undefined, '--adapter', 'claude'),
      columns: 120,
      rows: 40,
    },
  ));

describe('CHD-426 U1 tester: inputs during autonomous work', () => {
  for (const [columns, rows] of [
    [80, 24],
    [120, 40],
  ] as const) {
    for (const kind of ['form', 'link'] as const) {
      test(`${kind} stays held and answering returns to the running cycle at ${columns} columns`, () =>
        withWindow(
          async (window) => {
            await ready(window);
            await send(window, 'claudecyclebare');
            await window.shows('The build passed.');
            await window.shows('Working…');

            const session = window.session()!;
            const answer = session.elicitations.handler(
              kind === 'form'
                ? {
                    sessionId: session.id,
                    mode: 'form',
                    message: 'Cycle details',
                    requestedSchema: {
                      type: 'object',
                      properties: { note: { type: 'string', title: 'Note' } },
                    },
                  }
                : {
                    sessionId: session.id,
                    mode: 'url',
                    message: 'Cycle approval',
                    url: 'https://example.com/cycle',
                    elicitationId: 'cycle-window-link',
                  },
              new AbortController().signal,
            );

            await window.shows('between turns');
            await window.shows('ctrl+x a to answer');
            await window.type('1');
            expect(promptRow(window)).toContain('› 1');
            await leader(window, 'a');
            await window.shows('Esc to cancel');
            await window.press(ESC);
            expect(await answer).toMatchObject({ action: 'cancel' });
            await window.shows('Working…');
            await until(
              'the held input is gone',
              () => !window.frame().includes('between turns'),
            );
            expect(promptRow(window)).toContain('› 1');
          },
          {
            columns,
            rows,
            agentCommand: fakeAgentCommand(undefined, '--adapter', 'claude'),
          },
        ));
    }
  }
});

test("Esc in the agent's own cycle stops it: the working line goes, and a prompt after it is a turn as any (CHD-426 U2)", () =>
  withWindow(
    async (window) => {
      await ready(window);
      await send(window, 'claudecyclebare');
      await window.shows('The build passed.');
      await window.shows('Working…');
      await window.press(ESC);
      await until(
        'the cycle stopped',
        () => !window.frame().includes('Working…'),
      );
      await send(window, 'text');
      await window.shows('Hello, world. This reply came in chunks.');
    },
    {
      agentCommand: fakeAgentCommand(undefined, '--adapter', 'claude'),
      columns: 120,
      rows: 40,
    },
  ));

describe('CHD-426 U2 tester: held inputs and cancellation silence', () => {
  for (const [columns, rows] of [
    [80, 24],
    [120, 40],
  ] as const) {
    test(`Esc stays quiet while held form and link are withdrawn at ${columns} columns`, () =>
      withWindow(
        async (window) => {
          await ready(window);
          await send(window, 'claudecyclebare');
          await window.shows('The build passed.');

          const before = writes(
            window,
            '\x1b]9;fake is waiting for your input\x07',
          );
          const session = window.session()!;
          const withdrawn = new AbortController();
          const responses = [
            session.elicitations.handler(
              {
                sessionId: session.id,
                mode: 'form',
                message: 'Cancel cycle form',
                requestedSchema: { type: 'object', properties: {} },
              },
              withdrawn.signal,
            ),
            session.elicitations.handler(
              {
                sessionId: session.id,
                mode: 'url',
                message: 'Cancel cycle link',
                url: 'https://example.com/cancel',
                elicitationId: 'cancel-cycle-link',
              },
              withdrawn.signal,
            ),
          ];

          await window.shows('between turns');
          await window.press(ESC);
          await window.shows('Cancel heard with no turn.');
          withdrawn.abort();
          expect(await Promise.all(responses)).toEqual([
            { action: 'cancel' },
            { action: 'cancel' },
          ]);
          await until(
            'the cycle and held boxes are gone',
            () =>
              !window.frame().includes('Working…') &&
              !window.frame().includes('between turns'),
          );
          expect(
            writes(window, '\x1b]9;fake is waiting for your input\x07'),
          ).toBe(before);
          await window.press(ESC);
          await send(window, 'cancels');
          await window.shows('Cancels with no turn: 1.');
        },
        {
          columns,
          rows,
          notifications: OSC9,
          agentCommand: fakeAgentCommand(
            undefined,
            '--adapter',
            'claude',
            '--say-cancels',
          ),
        },
      ));
  }
});
