/**
 * An agent's own title for its session in the agents list, on the fake
 * agent and chord's own server: each child's beside its name, renamed in
 * place, and a task's never shown (CHD-445, the owner's Q200).
 */
import { describe, expect, test } from 'bun:test';
import stripAnsi from 'strip-ansi';
import { LONG_SESSION_TITLE } from '../../fixtures/fake_agent/scenarios/text.ts';
import { serveChord } from '../../../src/server/server.ts';
import {
  ready,
  send,
  statusReports,
  until,
  type Window,
  withWindow,
} from '../app/render.tsx';
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

  test("a task's session resumed as main stays untitled: the main row and the terminal's title say its first prompt, before and after its agent names it again (Q200)", async () => {
    const head = LONG_SESSION_TITLE.slice(0, 30);
    const log: string[] = [];
    const server = serveChord();
    const status = () => statusReports(log).at(-1)?.title;

    try {
      await withWindow(
        async (window) => {
          await ready(window);
          await send(window, 'tasktitled');
          await window.shows('Named at length.');
          await send(window, '/clear');
          await ready(window);
          await send(window, '/resume');
          await window.shows('Name the session · titledlong');

          const number = stripAnsi(window.frame())
            .split('\n')
            .find((line) => line.includes('Name the session · titledlong'))
            ?.match(/(\d+)\./)?.[1];

          await window.press(number!);
          await window.shows('resumed · ');
          await ready(window);
          // Its record's title is not restored: the first prompt names it.
          await until('the title', () => status() === 'titledlong');

          // The agent names it again, live: still untitled. Its title comes
          // before its reply, and its turn's end is drawn after both, so the
          // reports since the send hold any title it could have told.
          const sent = statusReports(log).length;

          await send(window, 'titled');
          await window.shows('Named.');
          await until(
            'the turn ended',
            () => !window.frame().includes('esc to interrupt'),
          );
          expect(
            statusReports(log)
              .slice(sent)
              .map((report) => report.title),
          ).not.toContain('Fix the tokenizer');
          expect(status()).toStrictEqual('titledlong');
          // A child, so the list is drawn: main's title column is blank.
          await send(window, '/new');
          await until('the list', () => rowOf(window, 'main') !== undefined);

          const main = rowOf(window, 'main')!;

          expect(main).not.toContain(head);
          expect(main).not.toContain('Fix the tokenizer');
        },
        { server, runtimes: ['fake'], rows: 80, columns: 120, log },
      );
    } finally {
      await server.close();
    }
  });
});
