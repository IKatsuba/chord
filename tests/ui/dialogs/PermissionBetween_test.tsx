/**
 * A request that waits on the person between turns: the prompt sent
 * meanwhile, attendance, and who asked, an agent or its task (CHD-158).
 */
import { describe, expect, test } from 'bun:test';
import assert from 'node:assert/strict';
import { serveChord } from '../../../src/server/server.ts';
import {
  DOWN,
  ESC,
  leader,
  promptRow,
  send,
  until,
  withWindow,
} from '../app/render.tsx';

describe('a request between turns (CHD-158)', () => {
  test("a subagent's waits without the keys until ctrl+x a, a typed digit going to the draft, then its form the same", () =>
    withWindow(async (window) => {
      await send(window, 'claudebetween');
      await window.shows(
        'Agent(tester (general-purpose)) asks · between turns',
      );
      await window.shows('ctrl+x a to answer');

      let frame = window.frame();

      expect(frame).toMatch(
        /● permission( asked between turns)? · ctrl\+x a to answer/,
      );
      expect(frame).not.toContain('❯ 1. Allow');
      expect(frame).not.toContain('Esc to reject');

      // A digit typed for the prompt is the draft's, not an answer.
      await window.type('2');
      expect(promptRow(window)).toContain('› 2');
      expect(window.frame()).toContain('1. Allow');

      await leader(window, 'a');
      await window.shows('❯ 1. Allow');
      await window.shows('Esc to reject');
      expect(promptRow(window)).toContain('› 2');
      await window.press('1');

      // The form after it waits the same way, above the prompt.
      await window.shows(
        'Agent(tester (general-purpose)) asks for input · between turns',
      );

      frame = window.frame();

      expect(frame).toContain('ctrl+x a to answer');
      expect(frame).toMatch(
        /● input( asked between turns)? · ctrl\+x a to answer/,
      );
      expect(promptRow(window)).toContain('› 2');
      await leader(window, 'a');
      await window.press(ESC);
      await window.shows('⏺ fake asked: Which suite should run next?');
      expect(promptRow(window)).toContain('› 2');
    }));

  test("the session's own agent is named, and answered once the keys are in", () =>
    withWindow(async (window) => {
      await send(window, 'mainbetween');
      await window.shows('main asks · between turns');
      await leader(window, 'a');
      await window.shows('❯ 1. Allow');
      await window.press('2');
      await window.shows('Permission: deny.');
      expect(window.frame()).not.toContain('between turns');
    }));

  test('a held form names who asks and shows no ❯ until ctrl+x a', () =>
    withWindow(async (window) => {
      await send(window, 'claudebetween');
      await window.shows('ctrl+x a to answer');
      await leader(window, 'a');
      await window.press('1');
      await window.shows(
        'Agent(tester (general-purpose)) asks for input · between turns',
      );

      const held = window.frame();

      expect(held).toContain('ctrl+x a to answer');
      expect(held).not.toContain('❯');
      await leader(window, 'a');
      await window.shows('❯   Suite');
      await window.press(ESC);
      await window.shows('⏺ fake asked: Which suite should run next?');
    }));

  test('with session:attention unbound, the box takes the keys at once, as in a turn', () =>
    withWindow(
      async (window) => {
        await send(window, 'mainbetween');
        await window.shows('main asks · between turns');
        await window.shows('❯ 1. Allow');

        const frame = window.frame();

        expect(frame).toContain('Esc to reject');
        expect(frame).not.toContain('to answer');
        await window.press('2');
        await window.shows('Permission: deny.');
      },
      {
        keybindings: JSON.stringify({
          bindings: [{ context: 'Global', bindings: { 'ctrl+x a': null } }],
        }),
      },
    ));

  test('the asker row wraps rather than cut at a narrow width', () =>
    withWindow(
      async (window) => {
        await send(window, 'claudebetween');
        await window.shows('ctrl+x a to answer');

        const frame = window.frame();

        expect(frame).toContain('Agent(tester (general-purpose)) asks');
        expect(frame).toContain('between turns');
        // Never cut from the left, as the row in a turn was.
        expect(frame).not.toMatch(/│ …/);
      },
      { columns: 44 },
    ));
});

describe('a prompt sent while a request waits between turns (CHD-158)', () => {
  test('waits in the queue after your answer, and goes once answered', () =>
    withWindow(async (window) => {
      await send(window, 'mainbetween');
      await window.shows('main asks · between turns');
      await window.type('text');
      await window.press('\r');
      await window.shows('› after your answer: text');
      // The request still waits, on the person.
      expect(window.frame()).toContain('main asks · between turns');
      await leader(window, 'a');
      await window.press('1');
      await window.shows('Permission: allow.');
      // The held prompt goes once the agent has gone quiet, and is answered.
      await window.shows('Hello, world.');

      const frame = window.frame();

      expect(frame).not.toContain('after your answer');
      // The answer's follow-up is a block of its own, above the prompt.
      expect(frame).toMatch(
        /⏺ Permission: allow\.\n\n › text\n\n ⏺ Hello, world\./,
      );
    }));
});

describe('CHD-158 tester: attendance in the window', () => {
  for (const [columns, rows] of [
    [80, 24],
    [120, 40],
  ] as const) {
    for (const focus of ['search'] as const) {
      test(`attention answers from ${focus} and preserves the draft at ${columns} columns`, () =>
        withWindow(
          async (window) => {
            await send(window, 'mainbetween');
            await window.shows('ctrl+x a to answer');
            await window.type('keep-this-draft');

            if (focus === 'search') {
              await window.press('\x12');
              await window.shows('search prompts:');
            }

            await window.press('\x18');
            await window.press('a');
            await window.shows('❯ 1. Allow');
            expect(window.frame()).not.toContain('search prompts:');
            expect(window.frame()).not.toContain('Enter to go');
            expect(promptRow(window)).toContain('keep-this-draft');
            await window.press(ESC);
            await window.shows('Permission: deny.');
            expect(promptRow(window)).toContain('keep-this-draft');
          },
          { columns, rows },
        ));
    }
  }

  test('a second queued permission needs its own attendance before a digit can answer it', () =>
    withWindow(async (window) => {
      const session = window.session();

      assert(session);

      const request = (id: string) =>
        session.permissions.handler(
          {
            sessionId: session.id,
            toolCall: { toolCallId: id, title: `Write ${id}.md` },
            options: [
              { optionId: 'allow', name: 'Allow', kind: 'allow_once' },
              { optionId: 'deny', name: 'Deny', kind: 'reject_once' },
            ],
          },
          new AbortController().signal,
        );
      const first = request('first');
      const second = request('second');

      await window.shows('Write first.md');
      await leader(window, 'a');
      await window.shows('❯ 1. Allow');
      await window.press('1');
      expect(await first).toStrictEqual({
        outcome: { outcome: 'selected', optionId: 'allow' },
      });
      await window.shows('Write second.md');
      await window.shows('ctrl+x a to answer');
      expect(window.frame()).not.toContain('❯ 1. Allow');
      await window.type('2');
      expect(promptRow(window)).toContain('› 2');
      await leader(window, 'a');
      await window.shows('❯ 1. Allow');
      await window.press('2');
      expect(await second).toStrictEqual({
        outcome: { outcome: 'selected', optionId: 'deny' },
      });
      await until(
        'the second permission to close',
        () => !window.frame().includes('Do you want to proceed?'),
      );
      expect(promptRow(window)).toContain('› 2');
    }));
});

describe('CHD-158 tester: agent and task requesters', () => {
  for (const [columns, rows] of [
    [80, 24],
    [120, 40],
  ] as const) {
    test(`attention takes the keys from agents focus at ${columns} columns`, async () => {
      const server = serveChord();

      try {
        await withWindow(
          async (window) => {
            await send(window, 'agents');
            await window.shows('All 214 parser tests pass now.');
            await until(
              'the parent to finish its replies',
              () => !window.frame().includes('Working…'),
            );
            await send(window, 'mainbetween');
            await window.shows('main asks · between turns');
            await window.press(DOWN);
            await window.shows('❯ main');
            await window.press('\x18');
            await window.press('a');
            await window.shows('❯ 1. Allow');
            expect(window.frame()).not.toContain('❯ main');
            await window.press(ESC);
            await window.shows('Permission: deny.');
            await window.type('after-focus');
            expect(promptRow(window)).toContain('after-focus');
          },
          { server, runtimes: ['fake'], columns, rows },
        );
      } finally {
        await server.close();
      }
    });

    test(`a spawn_task permission is held with its requester named after the parent ends at ${columns} columns`, async () => {
      const server = serveChord();

      try {
        await withWindow(
          async (window) => {
            const parent = window.session()!;
            const prompt = parent.prompt.bind(parent);
            let ended = false;

            parent.prompt = (...args) => {
              const turn = prompt(...args);

              void turn.result.then(() => {
                ended = true;
              });

              return turn;
            };

            await send(window, 'taskbetween');
            await window.shows(
              'Agent(Fix the tokenizer) · fake asks · between turns',
            );
            await window.shows('ctrl+x a to answer');
            expect(ended).toBe(true);
            expect(window.frame()).not.toContain('❯ 1. Allow');
            await window.type('3');
            expect(promptRow(window)).toContain('› 3');
            await leader(window, 'a');
            await window.shows('❯ 1. Allow');
            await window.press('1');
            await window.shows(
              'Received the message from Fix the tokenizer · fake · report.',
            );
            expect(promptRow(window)).toContain('› 3');
            expect(window.frame()).not.toContain('ctrl+x a to answer');
          },
          { server, runtimes: ['fake'], columns, rows },
        );
      } finally {
        await server.close();
      }
    });
  }
});
