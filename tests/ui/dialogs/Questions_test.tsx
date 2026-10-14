import { expect, test } from 'bun:test';
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
