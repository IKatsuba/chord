/** Session titles stay outside the agents list (CHD-523, Q200). */
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
  UP,
  ready,
  send,
  statusReports,
  until,
  type Window,
  withWindow,
} from '../app/render.tsx';
import { withAgents } from './agents_window.tsx';
import { BUGFIX, started } from './teams_window.tsx';

/** The list's row for `name`, as the screen shows it. */
function rowOf(window: Window, name: string): string | undefined {
  return stripAnsi(window.frame())
    .split('\n')
    .find((line) => new RegExp(`^ {4}${name}  `).test(line));
}

/** Both of `agentstitled`'s children have answered their naming prompts. */
async function titled(window: Window): Promise<void> {
  await ready(window);
  await send(window, 'agentstitled');
  await until(
    'both children titled',
    () =>
      rowOf(window, 'parser') !== undefined &&
      rowOf(window, 'docs') !== undefined &&
      !window.frame().includes('esc to interrupt'),
  );
}

describe('session titles stay outside every agents-list row (CHD-523)', () => {
  for (const [columns, rows] of [
    [120, 40],
    [80, 24],
  ] as const) {
    for (const team of [false, true]) {
      test(`long-titled ${team ? 'lead and nested members' : 'main and children'} take one line each at ${columns}×${rows}`, async () => {
        const server = serveChord();

        try {
          await withWindow(
            async (window) => {
              if (team) {
                await started(window);
              } else {
                await ready(window);
                await send(window, 'agentsquiet');
                await window.shows('● docs needs your permission');
                await until(
                  'both children in the list',
                  () =>
                    rowOf(window, 'parser') !== undefined &&
                    rowOf(window, 'docs') !== undefined,
                );
              }

              const lines = stripAnsi(window.frame()).split('\n');
              const bottom = lines.findLastIndex((line) =>
                line.startsWith('╰'),
              );
              const list = lines
                .slice(bottom + 2)
                .filter((line) => line.trim());
              const names = team
                ? ['main', 'bugfix', '├─ tester', '└─ coder']
                : ['main', 'parser', 'docs'];

              expect(list).toHaveLength(names.length);

              for (const [at, name] of names.entries()) {
                expect(list[at]).toContain(name);
                expect(list[at]).not.toContain(LONG_SESSION_TITLE.slice(0, 12));
                expect(list[at]).not.toMatch(
                  /Fix the tokenizer|Fix the parser/,
                );
              }

              if (!team) {
                await window.press(DOWN);
                await window.shows('❯ main');
                await window.press(DOWN);
                await window.shows('❯ parser');
                await window.press(UP);
                await window.shows('❯ main');
              }
            },
            {
              server,
              runtimes: ['fake'],
              columns,
              rows,
              teams: { bugfix: BUGFIX },
              agentCommand: fakeAgentCommand(
                undefined,
                '--title',
                LONG_SESSION_TITLE,
              ),
            },
          );
        } finally {
          await server.close();
        }
      });
    }
  }
});

describe("an agent's own title in the agents list (CHD-445)", () => {
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

  test("a task's session resumed as main stays untitled: the terminal's title says its first prompt, before and after its agent names it again (Q200)", async () => {
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
          // A child makes the list visible too.
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
  for (const [columns, rows] of [
    [80, 24],
    [120, 40],
  ] as const) {
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
