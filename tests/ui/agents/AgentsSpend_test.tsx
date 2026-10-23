/**
 * What long-lived agents spend and how their rows read in the window: the
 * report each runtime gives, a child's own spend, messages in the strip and
 * picker, and rows taller than the list.
 */
import { describe, expect, test } from 'bun:test';
import { pickAgent } from '../app/child_window.tsx';
import assert from 'node:assert/strict';
import { readdir } from 'node:fs/promises';
import { join } from 'node:path';
import { serveChord } from '../../../src/server/server.ts';
import { readPast } from '../../../src/session/record.ts';
import { fakeAgentCommand } from '../../fixtures/fake.ts';
import {
  GATE,
  GATE_RELEASE,
  HELD_AGAIN,
  LONG_TITLE,
} from '../../fixtures/fake_agent/scenarios/agents.ts';
import {
  DOWN,
  ESC,
  ready,
  send,
  until,
  UP,
  type Window,
  withWindow,
} from '../app/render.tsx';
import { withAgents } from './agents_window.tsx';

describe('CHD-405 tester: reports follow the picked runtime', () => {
  async function report(window: Window, command: string, expected: RegExp) {
    const latest = () => {
      const lines = window.frame().split('\n');
      const at = lines.findLastIndex((line) => line.includes(`› ${command}`));

      return at < 0 ? '' : lines.slice(at + 1).join('\n');
    };

    await send(window, command);
    await until(`the latest ${command} report`, () => expected.test(latest()));

    return latest();
  }

  async function childFinished(dir: string) {
    const records = join(dir, 'state', 'records');
    let files: string[];

    try {
      files = await readdir(records);
    } catch (error) {
      if (
        error instanceof Error &&
        'code' in error &&
        error.code === 'ENOENT'
      ) {
        return false;
      }

      throw error;
    }

    for (const file of files) {
      const past = await readPast(join(dir, 'state', 'records', file));
      const session = past.find((entry) => entry.type === 'session');

      if (
        session?.type === 'session' &&
        session.name === 'foreign' &&
        past.some((entry) => entry.type === 'result')
      ) {
        return true;
      }
    }

    return false;
  }

  for (const [columns, rows] of [
    [80, 24],
    [120, 40],
  ] as const) {
    for (const usage of ['missing', 'tokens', 'values'] as const) {
      test(`a standalone child, main and another child keep their own report runtime with ${usage} usage at ${columns} columns`, async () => {
        const server = serveChord();
        const admit = server.admit.bind(server);
        let main: Parameters<typeof admit>[0] | undefined;
        const command = fakeAgentCommand(
          undefined,
          ...(usage === 'missing'
            ? ['--no-usage']
            : usage === 'tokens'
              ? ['--tokens-only']
              : []),
        );

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
              await main.window.open(main.key, {
                agent: 'codex',
                name: 'foreign',
                prompt: 'text',
              });
              await until("the child's actual recorded result", () =>
                childFinished(window.dir),
              );
              await window.press(DOWN);
              await window.press(DOWN);
              await window.press('\r');
              await window.shows('╭─ foreign ─');
              await report(window, '/status', /Agent: +codex/);

              const cost = await report(
                window,
                '/cost',
                usage === 'missing'
                  ? /codex has not reported what this session has used\./
                  : /Total cost:/,
              );

              if (usage === 'tokens') {
                expect(cost).toContain("(chord's estimate)");
                expect(cost).toMatch(/Tokens in: +1,000/);
              } else if (usage === 'values') {
                expect(cost).toContain('$0.0125');
                expect(cost).toMatch(/Tokens in: +1,000/);
              }

              await report(
                window,
                '/context',
                usage === 'missing'
                  ? /codex has not reported how full its context window is\./
                  : /Used: +/,
              );
              await window.press(DOWN);
              await window.press(UP);
              await window.press('\r');
              await report(window, '/status', /Agent: +fake/);
              await report(
                window,
                '/cost',
                /fake has not reported what this session has used\./,
              );
              await report(
                window,
                '/context',
                /fake has not reported how full its context window is\./,
              );
              await main.window.open(main.key, {
                agent: 'other',
                name: 'other',
                prompt: 'text',
              });
              await pickAgent(window, 'other');
              await ready(window);
              await report(window, '/status', /Agent: +other/);
              await report(
                window,
                '/cost',
                /other has not reported what this session has used\./,
              );
              await pickAgent(window, 'main');
              await report(window, '/status', /Agent: +fake/);
              await window.press(DOWN);
              await window.press(DOWN);
              await window.press('\r');
              await window.shows('╭─ foreign ─');
              await report(window, '/status', /Agent: +codex/);
            },
            {
              server,
              columns,
              rows,
              runtimes: ['fake', 'codex', 'other'],
              agentCommand: command,
              startupOf: (runtime) => ({
                agentCommand:
                  runtime === 'other'
                    ? fakeAgentCommand(undefined, '--no-usage')
                    : command,
              }),
            },
          );
        } finally {
          await server.close();
        }
      });
    }
  }
});

describe('CHD-405 N2 tester: standalone child spend is independent', () => {
  for (const [columns, rows] of [
    [80, 24],
    [120, 40],
  ] as const) {
    test(`the picked child gets its own running row and loses it when cancelled while main runs at ${columns} columns`, async () => {
      const server = serveChord();
      const admit = server.admit.bind(server);
      let main: Parameters<typeof admit>[0] | undefined;
      const command = fakeAgentCommand(
        undefined,
        '--no-usage',
        '--step-ms',
        '30',
      );
      const cost = async (window: Window) => {
        await send(window, '/cost');
        await window.shows('› /cost');

        const lines = window.frame().split('\n');
        const at = lines.findLastIndex((line) => line.includes('› /cost'));

        return lines.slice(at + 1).join('\n');
      };

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
            await main.window.open(main.key, {
              agent: 'codex',
              name: 'foreign',
              prompt: 'slow',
            });
            await window.shows('foreign');
            await window.press(DOWN);
            await window.press(DOWN);
            await window.press('\r');
            await window.shows('╭─ foreign ─');
            await window.shows('Working.');
            expect(await cost(window)).toContain('counted when it ends');
            await window.press(DOWN);
            await window.press(UP);
            await window.press('\r');
            expect(await cost(window)).not.toContain('This turn:');
            await send(window, 'slow');
            await window.shows('Working.');
            await window.press(DOWN);
            await window.press(DOWN);
            await window.press('\r');
            await window.shows('╭─ foreign ─');
            await window.press(ESC);
            await window.shows('Interrupted by user');
            expect(await cost(window)).not.toContain('This turn:');
          },
          {
            server,
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

describe('CHD-471 L2 tester: child messages in the agents list', () => {
  for (const [columns, rows] of [
    [80, 24],
    [120, 40],
  ] as const) {
    test(`a working child's unread message clears only when that child is picked at ${columns} columns`, async () => {
      const server = serveChord();

      try {
        await withWindow(
          async (window) => {
            await ready(window);
            await send(window, 'agentcallgated');
            await window.shows('← new message');

            const childRow = () =>
              window
                .frame()
                .split('\n')
                .find((line) => /^ {4}parser /.test(line)) ?? '';

            expect(childRow()).toMatch(/✻ working \d+s +← new message/);
            await window.press(DOWN);
            await window.press('\r');
            expect(childRow()).toContain('← new message');
            await window.press(DOWN);
            await window.press(DOWN);
            await window.shows(
              `← from @main · after the running calls: ${HELD_AGAIN}`,
            );
            await window.press(ESC);
            await window.press(DOWN);
            await window.press(UP);
            await window.press('\r');
            await until(
              'reading the child clears only its message mark',
              () =>
                /✻ working \d+s/.test(childRow()) &&
                !childRow().includes('← new message'),
            );
            expect(await readdir(join(window.dir, GATE))).not.toContain(
              GATE_RELEASE,
            );
          },
          {
            server,
            runtimes: ['fake'],
            columns,
            rows,
            agentCommand: fakeAgentCommand(undefined, '--steering', 'claude'),
          },
        );
      } finally {
        await server.close();
      }
    });
  }
});

test("a child's row taller than the list at 80x24 is read by line with ↑ ↓, and a resize, away and back or in height alone, reads it from its first line again (CHD-471)", () =>
  withAgents(async (window) => {
    const list = (lines: number) =>
      window.frame().split('\n').slice(-lines).join('\n');
    const FIRST = '  ❯ Summarise the release      fake';

    await window.resize({ columns: 80, rows: 24 });
    await ready(window);
    await send(window, 'agenttitled');
    // The prompt keeps the keys: the last row fills the list, ↓ beside it.
    await window.shows('  ↓ commits since 0.55.2,');
    await window.press(DOWN);
    await window.press(DOWN);
    await window.shows(FIRST);

    for (let press = 0; press < 4; press += 1) {
      await window.press(DOWN);
    }

    await until('read four lines on', () =>
      list(4).startsWith('  ↑ grouped by area, with a'),
    );
    expect(list(4)).toContain('  ↓ each breaking one, then');
    expect(list(4)).not.toContain('❯');

    // To 82 and back with no key: from its first line again.
    await window.resize({ columns: 82, rows: 24 });
    await window.resize({ columns: 80, rows: 24 });
    await until('its first line again', () => list(4).includes(FIRST));

    for (let press = 0; press < 4; press += 1) {
      await window.press(DOWN);
    }

    await until('read on again', () =>
      list(4).startsWith('  ↑ grouped by area, with a'),
    );

    // The same width, another height.
    await window.resize({ columns: 80, rows: 30 });
    await until('its first line after a taller window', () =>
      list(5).includes(FIRST),
    );
  }));

test("↓ past a last row's last line leaves the list at its end, as the last stays the last, and goes round nothing (CHD-471)", () =>
  withAgents(async (window) => {
    const list = () => window.frame().split('\n').slice(-4).join('\n');

    await window.resize({ columns: 80, rows: 24 });
    await ready(window);
    await send(window, 'agenttitled');
    await window.shows('  ↓ commits since 0.55.2,');
    await window.press(DOWN);
    await window.press(DOWN);
    await window.shows('  ❯ Summarise the release      fake');

    // Thirteen lines in a four-line list: nine presses read it to its end,
    // and the ones after stay there.
    for (let press = 0; press < 12; press += 1) {
      await window.press(DOWN);
    }

    await until('at its end', () => list().endsWith('    before the tag.'));
    expect(list()).toMatch(/^ {2}↑ /);
    expect(list()).not.toContain('❯');
    expect(list()).not.toContain('↓');

    await window.press(DOWN);
    await window.press(DOWN);
    await new Promise((resolve) => setTimeout(resolve, 200));
    expect(list().endsWith('    before the tag.')).toBeTruthy();
    expect(list()).not.toContain('Summarise the release');
  }));

describe('CHD-471 L1b tester: tall row actions and summary boundary', () => {
  for (const [columns, rows] of [
    [80, 24],
    [120, 40],
  ] as const) {
    test(`reading a tall row reaches the summary then returns to its first line at ${columns} columns`, () =>
      withAgents(async (window) => {
        await window.resize({ columns, rows });
        await ready(window);
        await send(window, 'agenttitled');
        await window.shows('Waiting on it.');
        await until('main turn finished', async () => {
          for (const file of await readdir(
            join(window.dir, 'state', 'records'),
          )) {
            const past = await readPast(
              join(window.dir, 'state', 'records', file),
            );
            const prompt = past.find(
              (entry) =>
                entry.type === 'prompt' && entry.prompt === 'agenttitled',
            );

            if (
              prompt?.type === 'prompt' &&
              past.some(
                (entry) =>
                  entry.type === 'result' && entry.turnId === prompt.turnId,
              )
            ) {
              return true;
            }
          }

          return false;
        });

        await send(window, 'monitors');
        await window.shows('2 monitors running');
        await window.press(DOWN);
        await window.press(DOWN);
        await window.shows('❯ Summarise the release');

        for (
          let step = 0;
          step < 40 && !window.frame().includes('❯ background');
          step += 1
        ) {
          await window.press(DOWN);
        }

        await window.shows('❯ background');
        await window.press(UP);
        await window.shows('❯ Summarise the release');
        await window.press(UP);
        await window.shows('❯ main');
        await window.press(UP);
        await until(
          'above main returns the keys to the prompt',
          () => !window.frame().includes('❯ main'),
        );
        await window.press(DOWN);
        await window.shows('❯ main');
      }));

    test(`Enter and x still address the tall child while its first line is out of sight at ${columns} columns`, () =>
      withAgents(async (window) => {
        await window.resize({ columns, rows });
        await ready(window);
        await send(window, 'agenttitled');
        await window.shows('Waiting on it.');
        await window.press(DOWN);
        await window.press(DOWN);
        await window.shows('❯ Summarise the release');

        for (let step = 0; step < 5; step += 1) {
          await window.press(DOWN);
        }

        const budget = rows === 24 ? 4 : 6;

        expect(
          window.frame().split('\n').slice(-budget).join('\n'),
        ).not.toContain('❯ Summarise');
        await window.press('\r');
        await window.shows('Hello, world. This reply came in chunks.');
        await send(window, '/echo tall-row-target');
        await window.shows('tall-row-target');
        await window.press(DOWN);

        for (let step = 0; step < 5; step += 1) {
          await window.press(DOWN);
        }

        await window.press('x');
        await until(
          'the long-named child is closed',
          () =>
            window.frame().includes('The person closed') ||
            window.frame().includes('x again to stop'),
        );

        if (window.frame().includes('x again to stop')) {
          await window.press('x');
        }

        await window.shows('The person closed');
        expect(window.frame()).not.toContain('❯ Summarise the release');
        await until(
          'the echoed and closed session is the long-named child',
          async () => {
            const records = join(window.dir, 'state', 'records');
            const pasts = await Promise.all(
              (await readdir(records)).map((file) =>
                readPast(join(records, file)),
              ),
            );
            const child = pasts.find((past) =>
              past.some(
                (entry) =>
                  entry.type === 'session' && entry.name === LONG_TITLE,
              ),
            );
            const own = child?.find((entry) => entry.type === 'session');

            return (
              own?.type === 'session' &&
              child!.some(
                (entry) =>
                  entry.type === 'prompt' &&
                  entry.prompt === '/echo tall-row-target',
              ) &&
              pasts.some((past) =>
                past.some(
                  (entry) => entry.type === 'closed' && entry.agent === own.id,
                ),
              )
            );
          },
        );
      }));
  }
});
