/**
 * What a team's members report and spend in the window, a member's name
 * across runs, opt-in members and a refused runtime.
 */
import { describe, expect, test } from 'bun:test';
import { readFile } from 'node:fs/promises';
import { serveChord } from '../../../src/server/server.ts';
import { fakeAgentCommand } from '../../fixtures/fake.ts';
import {
  DOWN,
  ESC,
  UP,
  leader,
  ready,
  send,
  until,
  type Window,
  withWindow,
} from '../app/render.tsx';
import { BUGFIX, withTeams, started } from './teams_window.tsx';

test("/cost, /context and /status on a picked member name its runtime, not the tab's (CHD-405)", async () => {
  const server = serveChord();
  // tester on another runtime than main's, its agent still the fake.
  const team = BUGFIX.replace(
    /(- name: tester\n(?:.*\n)*?\s+agent: )fake/,
    '$1codex',
  );

  expect(team).not.toStrictEqual(BUGFIX);

  try {
    await withWindow(
      async (window) => {
        await started(window);
        await leader(window, 'a');
        await window.shows('╭─ tester · bugfix ─');
        await window.press('3');
        await window.shows('Not run; I will ask bugfix how to go on.');

        for (const [command, line] of [
          ['/cost', 'codex has not reported what this session has used.'],
          [
            '/context',
            'codex has not reported how full its context window is.',
          ],
          ['/status', 'Agent'],
        ] as const) {
          await send(window, command);
          await window.shows(line);
        }

        expect(window.frame()).toMatch(/Agent: +codex/);
        expect(window.frame()).not.toContain('fake has not reported');
      },
      {
        server,
        runtimes: ['fake', 'codex'],
        rows: 80,
        columns: 120,
        teams: { bugfix: team },
        agentCommand: fakeAgentCommand(undefined, '--no-usage'),
        // Every runtime on the fake: a test never starts a real Codex.
        startupOf: () => ({
          agentCommand: fakeAgentCommand(undefined, '--no-usage'),
        }),
      },
    );
  } finally {
    await server.close();
  }
});

describe('CHD-389 U3 tester: same member name across runs', () => {
  for (const [columns, rows] of [
    [80, 24],
    [120, 40],
  ] as const) {
    test(`each tester permission names its own run at ${columns} columns`, () =>
      withTeams(async (window) => {
        await window.resize({ columns, rows });
        await started(window);
        await send(window, 'team2');
        await window.shows('Team(bugfix 2) · fake · fake-large');
        await window.shows('● 2 agents wait');

        for (const team of ['bugfix', 'bugfix 2']) {
          const heading = `╭─ tester · ${team} ─`;

          for (
            let presses = 0;
            presses < 10 && !window.frame().includes(heading);
            presses++
          ) {
            await window.press(DOWN);
          }

          await window.shows(heading);
          await window.shows(`tester · ${team} asks`);
          expect(window.frame()).not.toContain(
            `tester · ${team === 'bugfix' ? 'bugfix 2' : 'bugfix'} asks`,
          );
        }
      }));
  }
});

describe('CHD-407 R2 tester: opt-in lead members', () => {
  for (const extra of [false, true]) {
    test(`${extra ? 'flagged' : 'default'} lead opens the expected members on fake runtimes`, async () => {
      const server = serveChord();
      const team = await readFile(
        new URL('../../../scripts/dev/screenshots_team.md', import.meta.url),
        'utf8',
      );
      const command = fakeAgentCommand(
        undefined,
        '--tokens-only',
        ...(extra ? ['--lead-opens', 'tester,coder,reviewer'] : []),
      );

      try {
        await withWindow(
          async (window) => {
            await ready(window);
            await send(window, 'team');
            await window.shows('← from @bugfix · claude');
            await window.shows('tester');
            await window.shows('coder');

            if (extra) {
              await window.shows('reviewer');
            } else {
              expect(window.frame()).not.toMatch(/└─ reviewer/);
            }
          },
          {
            server,
            teams: { bugfix: team },
            runtimes: ['fake', 'claude', 'codex'],
            agentCommand: command,
            startupOf: () => ({ agentCommand: command }),
            rows: 40,
            columns: 120,
          },
        );
      } finally {
        await server.close();
      }
    });
  }
});

describe('a runtime whose command was refused (CHD-466)', () => {
  const REFUSED =
    'codex not started: agents.codex.command in .chord/settings.json: expected a string, got a number';
  const options = (team: string) => ({
    server: serveChord(),
    runtimes: ['fake', 'codex'],
    rows: 80,
    columns: 120,
    teams: { bugfix: team },
    // codex refused, as its command was; nothing starts it.
    startupOf: (name: string) =>
      name === 'codex'
        ? { refused: REFUSED }
        : { agentCommand: fakeAgentCommand() },
  });

  test('/new codex is refused as another chord, and nothing is cleared (CHD-493)', async () => {
    const opened = options(BUGFIX);

    try {
      await withWindow(async (window) => {
        await ready(window);
        await send(window, 'hello');
        await window.shows('› hello');
        await send(window, '/new codex');
        await window.shows(
          '/new starts a new fake session here; for codex, run chord codex in another pane',
        );
        expect(window.frame()).toContain('› hello');
      }, opened);
    } finally {
      await opened.server.close();
    }
  });

  test('a member on it is refused with the cause, which its lead hears', async () => {
    const opened = options(
      BUGFIX.replace(/(- name: tester\n(?:.*\n)*?\s+agent: )fake/, '$1codex'),
    );

    try {
      await withWindow(async (window) => {
        await ready(window);
        await send(window, 'team');
        await window.shows('Team(bugfix) · fake · fake-large');
        // The lead's transcript has its open_agent's refusal.
        await window.press(DOWN);
        await window.press(DOWN);
        await window.press('\r');
        await window.shows('╭─ bugfix ─');
        await window.shows(REFUSED.slice(0, 60));
        expect(window.frame()).not.toContain('├─ tester');
      }, opened);
    } finally {
      await opened.server.close();
    }
  });
});

describe('CHD-405 N2 tester: member spend follows the picked session', () => {
  for (const [columns, rows] of [
    [80, 24],
    [120, 40],
  ] as const) {
    test(`a member running under idle main and idle member under running main report independently at ${columns} columns`, async () => {
      const server = serveChord();
      const command = fakeAgentCommand(
        undefined,
        '--no-usage',
        '--step-ms',
        '30',
      );
      const team = BUGFIX.replace(
        /(- name: tester\n(?:.*\n)*?\s+agent: )fake/,
        '$1codex',
      );
      const cost = async (window: Window, agent: string) => {
        await send(window, '/cost');
        await until('the cost report has its Total row', () =>
          window.mounted('Total'),
        );

        // The wrapped table can put its command and session figure above
        // the viewport. Read this report's own section, not its old prompt.
        for (let step = 0; step < 12; step++) {
          const lines = window.frame().split('\n');
          const at = lines.findLastIndex((line) =>
            line.includes(`${agent} has not reported`),
          );
          const table = lines.findIndex(
            (line, index) => index > at && line.includes('This session'),
          );

          if (at >= 0 && table > at) {
            const report = lines.slice(at, table).join('\n');

            await window.press('\x1b[1;2F');

            return report;
          }

          await window.press(at < 0 ? '\x1b[5~' : '\x1b[1;2B');
        }

        throw new Error(`session cost figure not in view: ${window.frame()}`);
      };

      try {
        await withWindow(
          async (window) => {
            await started(window);
            await leader(window, 'a');
            await window.shows('╭─ tester · bugfix ─');
            await window.press('3');
            await window.shows('Not run; I will ask bugfix how to go on.');
            await send(window, 'slow');
            await window.shows('Working.');

            const running = await cost(window, 'codex');

            expect(running).toContain('codex has not reported');
            expect(running).toContain('counted when it ends');
            await window.press(DOWN);

            for (
              let step = 0;
              step < 8 && !/❯ main/.test(window.frame());
              step++
            ) {
              await window.press(UP);
            }

            await window.press('\r');
            await until(
              'main is idle',
              () => !window.frame().includes('Working…'),
            );
            expect(await cost(window, 'fake')).not.toContain('This turn:');
            await send(window, 'slow');
            await window.shows('Working.');
            await window.press(DOWN);

            for (
              let step = 0;
              step < 8 && !/❯ ├─ tester/.test(window.frame());
              step++
            ) {
              await window.press(DOWN);
            }

            await window.press('\r');
            await window.shows('╭─ tester · bugfix ─');
            await window.press(ESC);
            await window.shows('Interrupted by user');
            expect(await cost(window, 'codex')).not.toContain('This turn:');
          },
          {
            server,
            teams: { bugfix: team },
            runtimes: ['fake', 'codex'],
            columns,
            rows,
            agentCommand: command,
            startupOf: () => ({ agentCommand: command }),
          },
        );
      } finally {
        await server.close();
      }
    });
  }
});

describe('CHD-373 S4: a team member that starts a task agent', () => {
  test("its task is a row under the run with its owner, and the run's own row adds up its lead and members alone", async () => {
    const server = serveChord();
    const command = fakeAgentCommand(undefined, '--tester-plays', 'taskcost');

    try {
      await withWindow(
        async (window) => {
          await ready(window);
          await send(window, 'team');
          await window.shows('Team(bugfix) · fake · fake-large');
          await window.shows('1 task running');
          await send(window, '/cost');
          await window.shows('This session');
          await window.shows('task agent of tester, running');

          const run = window
            .frame()
            .split('\n')
            .find((line) => line.includes('team run: lead'));

          // The run's breakdown names its lead and members, never the task.
          expect(run, window.frame()).toBeDefined();
          expect(run).not.toContain('Count the cost');
        },
        {
          server,
          runtimes: ['fake'],
          rows: 80,
          columns: 160,
          teams: { bugfix: BUGFIX },
          agentCommand: command,
          startupOf: () => ({ agentCommand: command }),
        },
      );
    } finally {
      await server.close();
    }
  });
});
