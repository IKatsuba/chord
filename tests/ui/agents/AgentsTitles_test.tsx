/**
 * An agent's own title for its session in the agents list, on the fake
 * agent and chord's own server: each child's beside its name, renamed in
 * place, and a task's never shown (CHD-445, the owner's Q200).
 */
import { describe, expect, test } from 'bun:test';
import stripAnsi from 'strip-ansi';
import assert from 'node:assert/strict';
import { openSession } from '../../../src/session/session.ts';
import type { Caller } from '../../../src/server/tools.ts';
import { fakeAgentCommand } from '../../fixtures/fake.ts';
import { LONG_SESSION_TITLE } from '../../fixtures/fake_agent/scenarios/text.ts';
import { serveChord } from '../../../src/server/server.ts';
import {
  DOWN,
  ESC,
  UP,
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

describe('CHD-445 U3 tester: title lifetime and constrained list navigation', () => {
  for (const [columns, rows, limit] of [
    [80, 24, 4],
    [120, 40, 6],
  ] as const) {
    test(`a long title remains readable by line and the next agent remains reachable at ${columns}×${rows}`, () =>
      withAgents(async (window) => {
        await window.resize({ columns, rows });
        await titled(window);
        await send(window, 'titledlong');
        await window.shows('Named at length.');
        await window.press(DOWN);
        await window.shows('❯ main');
        await window.shows('Find out why');

        for (let presses = 0; !window.frame().includes('changes'); presses++) {
          expect(presses).toBeLessThan(30);
          await window.press(DOWN);

          const lines = stripAnsi(window.frame()).split('\n');
          const bottom = lines.findLastIndex((line) => line.startsWith('╰'));
          const list = lines
            .slice(bottom + 2)
            .filter((line) => line.trim() !== '');

          expect(list.length).toBeLessThanOrEqual(limit);
        }

        expect(window.frame()).not.toContain('Find out why');
        await window.press(DOWN);
        await window.shows('❯ parser');
        await window.shows('Fix the tokenizer');
        await window.press(UP);
        await window.shows('❯ main');
        await window.shows('Find out why');
      }));

    test(`/clear leaves main blank when new titled children reopen at ${columns}×${rows}`, () =>
      withAgents(async (window) => {
        await window.resize({ columns, rows });
        await titled(window);
        await send(window, 'titledlook');
        await window.shows('Looking.');
        expect(rowOf(window, 'main')).toContain('Look at the parser');
        await send(window, '/clear');
        await titled(window);

        const main = rowOf(window, 'main')!;

        expect(
          main.slice(main.indexOf('main') + 4, main.indexOf('fake')).trim(),
        ).toBe('');
        expect(rowOf(window, 'parser')).toContain('Fix the tokenizer');
        expect(rowOf(window, 'docs')).toContain('Fix the parser');
      }));

    for (const scenario of ['crash', 'error', 'longheld']) {
      test(`a child's title survives ${scenario === 'longheld' ? 'a cancelled turn' : scenario} at ${columns}×${rows}`, () =>
        withAgents(async (window) => {
          await window.resize({ columns, rows });
          await titled(window);
          await window.press(DOWN);
          await window.press(DOWN);
          await window.press('\r');
          await window.shows('╭─ parser');
          await send(window, scenario);

          if (scenario === 'longheld') {
            await window.shows('20. Line 20');
            await window.press(ESC);
            await window.shows('Interrupted');
          } else if (scenario === 'error') {
            await window.shows('The fake agent failed on purpose.');
          } else {
            await until(
              'the titled child to exit',
              () => rowOf(window, 'parser')?.includes('exited') === true,
            );
          }

          expect(rowOf(window, 'parser')).toContain('Fix the tokenizer');
        }));
    }

    test(`a hung start has no title and closes from the list at ${columns}×${rows}`, async () => {
      const server = serveChord();
      const admit = server.admit.bind(server);
      let main: Caller | undefined;
      let opened = 0;

      server.admit = (caller) => {
        if (caller.role === 'person') {
          main = caller;
        }

        return admit(caller);
      };

      try {
        await withWindow(
          async (window) => {
            await ready(window);
            assert(main);

            const caller = main;

            await caller.window.open(caller.key, {
              agent: 'fake',
              name: 'worker',
              prompt: 'text',
            });
            await until(
              'the starting child in the list',
              () => rowOf(window, 'worker') !== undefined,
            );
            expect(window.frame()).not.toContain('Never published');
            await window.press(DOWN);
            await window.press(DOWN);
            await window.shows('❯ worker');
            await window.press('x');
            await until(
              'the hung child to leave the list',
              () =>
                caller.window
                  .sessions()
                  .find((session) => session.key === caller.key)
                  ?.children.some((child) => child.name === 'worker') === false,
            ).catch((error: Error) => {
              throw new Error(`${error.message}\n${window.frame()}`);
            });

            expect(window.frame()).not.toContain('Never published');
            expect(window.frame()).not.toMatch(/(?:❯\s+| {4})worker\s+fake/);
          },
          {
            server,
            runtimes: ['fake'],
            columns,
            rows,
            openWith: (options) =>
              openSession({
                ...options,
                agentCommand:
                  ++opened === 1
                    ? fakeAgentCommand()
                    : fakeAgentCommand(
                        undefined,
                        '--hang',
                        'start',
                        '--title',
                        'Never published',
                      ),
              }),
          },
        );
      } finally {
        await server.close();
      }
    });
  }
});
