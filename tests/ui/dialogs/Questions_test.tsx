import { expect, test } from 'bun:test';
import assert from 'node:assert/strict';
import { enricherRelay } from '../../../src/session/enrich.ts';
import { ENRICHERS } from '../../../src/session/enrichers.ts';
import { type Questions, questionsOf } from '../../../src/session/questions.ts';
import { QuestionBox } from '../../../src/ui/dialogs/Questions.tsx';
import { CODEX_QUESTIONS } from '../../fixtures/questions.ts';
import { draw } from '../harness.tsx';
import {
  DOWN,
  ESC,
  inputAsked,
  send,
  TAB,
  withWindow,
} from '../app/render.tsx';

test("an agent's questions are asked one at a time, with their text and options, and the answers go back under its fields", () =>
  withWindow(
    async (window) => {
      await send(window, 'askclaude');
      await inputAsked(window, 'fake asks you 2 questions');

      const first = window.frame();

      expect(first).toContain('← ◉ Language   ○ Checks   ○ Submit →');
      expect(first).toContain('Which language should helper scripts use?');
      expect(first).toContain('❯ 1. Deno (TypeScript) (Recommended)');
      expect(first).toContain(
        'Runs from source with inline npm: and jsr: imports, no package manager',
      );
      expect(first).toContain('  2. Python');
      expect(first).toContain(
        'Note  Type your own answer, or add a note to the option you chose above (optional).',
      );
      expect(first).toContain(
        'Enter to pick · 1–2 · ↑↓ to move · ←→ or Tab for the questions · Esc to cancel',
      );

      // The first option, then Types and Tests on the second question.
      await window.press('\r');
      await window.shows('Which checks should run before a commit? (pick any)');
      await window.press(' ');
      await window.press(DOWN);
      await window.press(DOWN);
      await window.press(' ');
      await window.shows('❯ [✔] 3. Tests');
      await window.press('\r');
      await window.shows('Checks    Types, Tests');
      expect(window.frame()).toContain(
        'Language  Deno (TypeScript) (Recommended)',
      );
      await window.press('\r');
      await window.shows(
        '{"question_0":"Deno (TypeScript) (Recommended)","question_1":["Types","Tests"]}',
      );
    },
    { rows: 40, columns: 120 },
  ));

test("a multi-select's rows stay in line as its ticks change", () =>
  withWindow(
    async (window) => {
      await send(window, 'askclaude');
      await inputAsked(window, 'fake asks you 2 questions');
      await window.press(TAB);
      await window.press(' ');
      await window.press(DOWN);
      await window.press(DOWN);
      await window.press(' ');
      await window.shows('❯ [✔] 3. Tests');

      const lines = window.frame().split('\n');
      const column = (text: string) =>
        lines.find((line) => line.includes(text))?.indexOf(text);

      expect(column('[ ] 2. Lint')).toBe(column('[✔] 1. Types'));
      expect(column('[✔] 3. Tests')).toBe(column('[✔] 1. Types'));
    },
    { rows: 40, columns: 120 },
  ));

test("codex's questions at 80 columns: its wait, a secret typed as dots, and Send out of reach until it has its answers", () =>
  withWindow(async (window) => {
    await send(window, 'askcodex');
    await inputAsked(window, 'fake asks you 2 questions');
    expect(window.frame()).toMatch(/answers itself in [45]:\d\d/);
    expect(window.frame()).toContain(
      '← * ◉ Next step   * ○ Token   ○ Submit →',
    );
    expect(window.frame()).toContain('Note  Additional answer or note');
    await window.press(TAB);
    await window.shows('Paste the API token for the staging deploy.');
    await window.type('sk-1');
    await window.shows('❯ ••••');
    await window.press(TAB);
    await window.shows('Next step  no answer yet, and fake needs one');
    expect(window.frame()).toContain('Token      ••••');
    expect(window.frame()).toContain('❯ 2. Skip these questions');
    expect(window.frame()).not.toContain('sk-1');
    await window.press(ESC);
    await window.shows('Elicitation answer: cancel');
  }));

test('a form with no questions read in it keeps the field table', () =>
  withWindow(async (window) => {
    await send(window, 'form');
    await inputAsked(window);
    expect(window.frame()).toContain('❯ * Project name');
    expect(window.frame()).not.toContain('Submit →');
  }));

test('a Note placeholder too long for 80 columns is cut at its end', () =>
  withWindow(
    async (window) => {
      await send(window, 'askclaude');
      await inputAsked(window, 'fake asks you 2 questions');

      const note = window
        .frame()
        .split('\n')
        .find((line) => line.includes('Note  '));

      expect(note).toContain('Note  Type your own answer, or add a note to');
      expect(note).toMatch(/…\s*│$/);
    },
    { rows: 24, columns: 80 },
  ));

test('an answered box leaves a row per question under the turn, saying who asked', () =>
  withWindow(
    async (window) => {
      await send(window, 'askcodex');
      await inputAsked(window, 'fake asks you 2 questions');
      await window.press('2');
      await window.type('sk-1');
      await window.press('\r');
      await window.press('\r');
      await window.shows('⎿  fake asked · Next step  Review existing work');
      expect(window.frame()).toMatch(/^ +Token {6}\(hidden\)/m);

      await send(window, 'askclaude');
      await inputAsked(window, 'fake asks you 2 questions');
      await window.press(TAB);
      await window.press(TAB);
      await window.press(DOWN);
      await window.press('\r');
      await window.shows('⎿  fake asked · Skipped');

      await send(window, 'askdroid');
      await inputAsked(window, 'fake asks you 3 questions');
      await window.press(ESC);
      await window.shows('⎿  fake asked · Cancelled');
    },
    { rows: 40, columns: 120 },
  ));

test("a box withdrawn as the agent's wait runs out reads Timed out", () =>
  withWindow(async (window) => {
    await send(window, 'askcodexwait');
    await window.shows('⎿  fake asked · Timed out');
    await window.shows('Elicitation answer: timed out');
  }));

test('a bracketed paste goes into the text row, a secret as dots', () =>
  withWindow(async (window) => {
    await send(window, 'askcodex');
    await inputAsked(window, 'fake asks you 2 questions');
    // On an option row it picks nothing.
    await window.paste('2');
    await window.press(TAB);
    await window.paste('sk-1');
    await window.shows('❯ ••••');
    await window.press(TAB);
    await window.shows('Token      ••••');
    expect(window.frame()).toContain('Next step  no answer yet');
  }));

test('the countdown runs from when the request came, not from when the box is drawn, and goes on as it is drawn again', async () => {
  const { questions } = askedCodex();
  const box = (now: number) => (
    <QuestionBox
      wait={{
        id: 'e1',
        mode: 'form',
        message: 'Codex needs your input to continue.',
        schema: { type: 'object', properties: {} },
        questions,
        at: 1_000,
      }}
      questions={questions}
      agent='codex'
      windowRows={24}
      width={80}
      active={false}
      now={() => now}
      onAnswer={() => {}}
    />
  );

  for (const [now, left] of [
    [1_000 + 60_000, 'answers itself in 4:00'],
    // Switched away and back two minutes later: drawn afresh.
    [1_000 + 180_000, 'answers itself in 2:00'],
  ] as const) {
    const drawn = await draw(box(now), { columns: 80, rows: 24 });

    expect(drawn.frame()).toContain(left);
    await drawn.unmount();
  }
});

/** codex's questions as the enrichers read them. */
function askedCodex(): { questions: Questions } {
  const [message] = enricherRelay(ENRICHERS).fromAgent({
    jsonrpc: '2.0',
    id: 1,
    method: 'elicitation/create',
    params: { ...CODEX_QUESTIONS, sessionId: 's' },
  });

  assert(message !== undefined && 'params' in message);

  const questions = questionsOf(message.params as typeof CODEX_QUESTIONS);

  assert(questions !== undefined);

  return { questions };
}

test("an option's description longer than an 80x24 box is cut, and the hint stays on screen", async () => {
  const long = Array.from({ length: 60 }, (_, index) => `word${index}`).join(
    ' ',
  );
  const questions: Questions = {
    agent: 'claude',
    questions: [
      {
        id: 'q',
        text: 'Which one?',
        options: [
          { value: 'a', title: 'First', description: long.repeat(4) },
          { value: 'b', title: 'Second' },
        ],
        multiSelect: false,
        required: false,
      },
    ],
  };
  const drawn = await draw(
    <QuestionBox
      wait={{
        id: 'e1',
        mode: 'form',
        message: 'Which one?',
        schema: { type: 'object', properties: {} },
      }}
      questions={questions}
      agent='claude'
      windowRows={24}
      width={80}
      active={false}
      onAnswer={() => {}}
    />,
    { columns: 80, rows: 24 },
  );
  const frame = drawn.frame();

  await drawn.unmount();
  expect(frame).toContain('❯ 1. First');
  expect(frame).toContain('…');
  expect(frame).toContain('↓ 1 more');
  expect(frame).toContain('Esc to cancel');
  expect(frame).toContain('╰');
});
