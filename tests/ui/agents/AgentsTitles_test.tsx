/**
 * An agent's own title for its session in the agents list, on the fake
 * agent and chord's own server: each child's beside its name, renamed in
 * place, and a task's never shown (CHD-445, the owner's Q200).
 */
import { describe, expect, test } from 'bun:test';
import stripAnsi from 'strip-ansi';
import { LONG_SESSION_TITLE } from '../../fixtures/fake_agent/scenarios/text.ts';
import { ready, send, until, type Window } from '../app/render.tsx';
import { withAgents } from './agents_window.tsx';

/** The list's row for `name`, as the screen shows it. */
function rowOf(window: Window, name: string): string | undefined {
  return stripAnsi(window.frame())
    .split('\n')
    .find((line) => new RegExp(`^ {4}${name}  `).test(line));
}

/** Both of `agentstitled`'s children up, each under its own title. */
async function titled(window: Window): Promise<void> {
  await ready(window);
  await send(window, 'agentstitled');
  await until(
    'both children titled',
    () =>
      /Fix the tokenizer/.test(rowOf(window, 'parser') ?? '') &&
      /Fix the parser/.test(rowOf(window, 'docs') ?? ''),
  );
}

describe("an agent's own title in the agents list (CHD-445)", () => {
  test('each child names its own session beside its name, the newest name in place, main blank while it has given none', () =>
    withAgents(async (window) => {
      await titled(window);

      // docs renamed itself: only its newest title stands, with no line of
      // its own about it.
      expect(window.frame()).not.toContain('Look at the parser');

      const main = rowOf(window, 'main')!;
      const parser = rowOf(window, 'parser')!;

      // main's title column is blank, its runtime where parser's is.
      expect(main.indexOf('fake ·')).toStrictEqual(parser.indexOf('fake ·'));
      expect(main.slice(8, main.indexOf('fake ·')).trim()).toStrictEqual('');
    }));

  test("a task's agent titles its session, which is shown nowhere: not in the list, nor on /resume, nor in the header when resumed (Q200)", () =>
    withAgents(async (window) => {
      const head = LONG_SESSION_TITLE.slice(0, 30);

      await titled(window);
      await send(window, 'tasktitled');
      await window.shows('Started.');
      await window.shows('Named at length.');
      expect(window.frame()).not.toContain(head);

      await send(window, '/clear');
      await ready(window);
      await send(window, '/resume');
      await window.shows('Resume a session');
      await window.shows('Name the session · titledlong');
      expect(window.frame()).not.toContain(head);

      // Picked by its number, the task's session opens under its name.
      const rows = stripAnsi(window.frame()).split('\n');
      const number = rows
        .find((line) => line.includes('Name the session · titledlong'))
        ?.match(/(\d+)\./)?.[1];

      await window.press(number!);
      // Its header names it as before: by the task's name, as a child's.
      await until('the header', () =>
        stripAnsi(window.frame())
          .split('\n')
          .some(
            (line) =>
              line.includes('resumed · ') && line.includes('Name the session'),
          ),
      );
      expect(window.frame()).not.toContain(head);
    }));
});
