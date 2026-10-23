/**
 * The task agents long-lived agents start, in the window: their asking, its
 * mark and attention key, and who a box that asks names.
 */
import { describe, expect, test } from 'bun:test';
import assert from 'node:assert/strict';
import { readdir } from 'node:fs/promises';
import { join } from 'node:path';
import { serveChord } from '../../../src/server/server.ts';
import { readPast } from '../../../src/session/record.ts';
import { fakeAgentCommand } from '../../fixtures/fake.ts';
import {
  DOWN,
  ESC,
  leader,
  ready,
  send,
  until,
  type Window,
  withWindow,
} from '../app/render.tsx';
import {
  opened,
  PARSER_TASK,
  parserTaskAsks,
  withAgents,
} from './agents_window.tsx';

test("a child's task permission keeps its mark and ctrl+x a once the child's turn has ended (CHD-266)", () =>
  withAgents(async (window) => {
    await ready(window);
    await send(window, 'agenttask');
    await parserTaskAsks(window);
    // parser's own turn ends about 3 s after it starts; its task still asks.
    await new Promise((resolve) => setTimeout(resolve, 4500));
    expect(window.frame()).toMatch(PARSER_TASK);
    expect(window.frame()).not.toContain('parser replied');
    await leader(window, 'a');
    await window.shows('╭─ parser ─');
    // Asked in a turn that has ended: it waits between turns.
    await window.shows('Agent(Fix the tokenizer) · fake asks · between turns');
    expect(window.frame()).toMatch(/parser .*● permission/);
    await leader(window, 'a');
    await window.shows('Esc to reject');
    await window.press('1');
    await window.shows('← from Fix the tokenizer · fake · report');
    expect(window.frame()).not.toMatch(/parser .*● permission/);
  }));

describe('CHD-266 tester: attention after an observed parent result', () => {
  async function taskAsks(window: Window, job: 'task' | 'taskask' = 'task') {
    const hint =
      job === 'task'
        ? /● (Agent\(Fix the tokenizer\) · fake|parser's task) needs your permission/
        : /● (Agent\(Ask the person\) · fake|parser's task) asks for input/;

    await until("parser's task hint", () => hint.test(window.frame()));

    return hint;
  }

  async function parserResult(dir: string): Promise<boolean> {
    const records = join(dir, 'state', 'records');

    for (const file of await readdir(records)) {
      const past = await readPast(join(records, file));
      const own = past.find((entry) => entry.type === 'session');

      if (own?.type !== 'session' || own.name !== 'parser') {
        continue;
      }

      const prompt = past.find((entry) => entry.type === 'prompt');

      if (
        prompt?.type === 'prompt' &&
        past.some(
          (entry) => entry.type === 'result' && entry.turnId === prompt.turnId,
        )
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
    for (const job of ['task', 'taskask'] as const) {
      test(`${job}: attention reaches the pending task after parser's recorded result at ${columns} columns`, async () => {
        const server = serveChord();
        const admit = server.admit.bind(server);
        let main: Parameters<typeof admit>[0] | undefined;

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
                agent: 'fake',
                model: 'fake-small',
                name: 'parser',
                prompt: job,
              });

              const hint = await taskAsks(window, job);

              await until('parser’s spawning turn result in its record', () =>
                parserResult(window.dir),
              );
              expect(window.frame()).toMatch(hint);
              expect(window.frame()).not.toContain('parser replied');
              await leader(window, 'a');
              await window.shows('╭─ parser ─');
              await window.shows('between turns');
              await leader(window, 'a');

              if (job === 'task') {
                await window.shows('Esc to reject');
                await window.press('1');
                await window.shows('← from Fix the tokenizer · fake · report');
              } else {
                await window.shows('Esc to cancel');
                await window.press(ESC);
                await window.shows('← from Ask the person · fake · report');
              }

              expect(window.frame()).not.toMatch(
                /parser .*● (permission|input)/,
              );
            },
            { server, runtimes: ['fake'], columns, rows },
          );
        } finally {
          await server.close();
        }
      });
    }
  }

  test('clear removes an unanswered task mark and a later child request asks again', () =>
    withAgents(async (window) => {
      await ready(window);
      await send(window, 'agenttask');
      await taskAsks(window);
      await until('the first parser result', () => parserResult(window.dir));
      await send(window, '/clear');
      await until(
        'the old parser and its attention to leave',
        () =>
          !window.frame().includes('    parser') &&
          !window.frame().includes('needs your permission'),
      );
      // Clear drops the old child before the new session is ready for Enter.
      await ready(window);
      await send(window, 'agenttask');
      await taskAsks(window);
      await leader(window, 'a');
      await window.shows('Agent(Fix the tokenizer) · fake asks');
    }));
});

describe('who a box that asks names (CHD-389)', () => {
  test('a picked child is named in its question, form and link boxes, not its runtime', () =>
    withAgents(async (window) => {
      await opened(window);
      await window.press(DOWN);
      await window.press(DOWN);
      // Enter takes the keys from the list back to parser's prompt.
      await window.press('\r');
      await window.shows('╭─ parser ─');

      for (const [prompt, heading] of [
        ['askclaude', 'parser asks you 2 questions'],
        ['form', 'parser asks for input'],
        ['link', 'parser asks you to open a link'],
      ] as const) {
        await send(window, prompt);
        await window.shows(heading);
        expect(window.frame()).not.toContain(`fake ${heading.slice(7)}`);
        await window.press(ESC);
        await window.shows('Elicitation answer: cancel');
      }
    }));
});

describe('CHD-431 tester: task input and permission in different children', () => {
  for (const [columns, rows] of [
    [80, 24],
    [120, 40],
  ] as const) {
    test(`settling the older task input changes the count to the remaining task's name at ${columns} columns`, async () => {
      const server = serveChord();
      const admit = server.admit.bind(server);
      let main: Parameters<typeof admit>[0] | undefined;

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
              agent: 'fake',
              name: 'questions',
              prompt: 'taskask',
            });
            await until('the first task input hint', () =>
              /● (Agent\(Ask the person\) · fake|questions's task) asks for input/.test(
                window.frame(),
              ),
            );
            await main.window.open(main.key, {
              agent: 'fake',
              name: 'parser',
              prompt: 'task',
            });
            await window.shows('● 2 agents wait');
            await leader(window, 'a');
            await window.shows('╭─ questions ─');
            await window.shows('between turns');
            await leader(window, 'a');
            await window.shows('Esc to cancel');
            await window.press(ESC);
            await until('the remaining task permission hint', () =>
              /● (Agent\(Fix the tokenizer\) · fake|parser's task) needs your permission/.test(
                window.frame(),
              ),
            );
            expect(window.frame()).not.toContain('● 2 agents wait');
            expect(window.frame()).not.toMatch(
              /● (Agent\(Ask the person\) · fake|questions's task) asks for input/,
            );
          },
          { server, runtimes: ['fake'], columns, rows },
        );
      } finally {
        await server.close();
      }
    });
  }
});

describe('CHD-158 C5 tester: a task returns with input open', () => {
  for (const [columns, rows] of [
    [80, 24],
    [120, 40],
  ] as const) {
    test(`the task form remains held and answerable after its result at ${columns} columns`, async () => {
      const server = serveChord();
      const admit = server.admit.bind(server);
      let main: Parameters<typeof admit>[0] | undefined;

      server.admit = (caller) => {
        if (caller.agent === undefined) {
          main = caller;
        }

        return admit(caller);
      };

      try {
        await withWindow(
          async (window) => {
            await ready(window);
            assert(main);
            await main.window.spawn(main, {
              agent: 'fake',
              name: 'Carry the form',
              prompt: 'leftform',
            });
            await window.shows(
              'Agent(Carry the form) · fake asks for input · between turns',
            );
            await window.shows('ctrl+x a to answer');
            expect(window.frame()).not.toContain('❯ * Project name');
            await send(window, 'text');
            await window.shows('after your answer: text');
            await leader(window, 'a');
            await window.shows('❯ * Project name');
            await window.shows('Esc to cancel');
            await window.press(ESC);
            await window.shows('Hello, world.');
            expect(window.frame()).not.toContain('after your answer: text');
          },
          { server, runtimes: ['fake'], columns, rows },
        );
      } finally {
        await server.close();
      }
    });
  }
});

describe('CHD-466 U2 tester: refusal before cached offers and child starts', () => {
  for (const [columns, rows] of [
    [80, 24],
    [120, 40],
  ] as const) {
    test(`a refusal beats a warm probe and child/task starts at ${columns} columns`, async () => {
      const server = serveChord();
      const admit = server.admit.bind(server);
      const callers: Parameters<typeof admit>[0][] = [];
      let refused = false;
      const reason = 'codex not started: command refused in this project';

      server.admit = (caller) => {
        callers.push(caller);

        return admit(caller);
      };

      try {
        await withWindow(
          async (window) => {
            await ready(window);

            const main = callers.find((caller) => caller.agent === undefined);

            assert(main);
            expect(
              await main.window.offer('codex', true, main.key),
            ).toHaveProperty('models');
            await main.window.open(main.key, {
              agent: 'fake',
              name: 'worker',
              prompt: 'text',
            });
            await until('child admitted', () =>
              callers.some((caller) => caller.agent !== undefined),
            );

            const child = callers.find((caller) => caller.agent !== undefined);

            assert(child);
            await until('child connected', () =>
              main.window
                .sessions()
                .some((session) =>
                  session.children.some(
                    (item) =>
                      item.id === child.agent && item.model !== undefined,
                  ),
                ),
            );

            refused = true;

            for (const caller of [main, child]) {
              for (const probe of [false, true]) {
                expect(
                  await caller.window.offer('codex', probe, caller.key),
                ).toEqual({ error: reason });
              }

              expect(
                await caller.window.spawn(caller, {
                  agent: 'codex',
                  prompt: 'text',
                }),
              ).toEqual({ error: reason });
            }

            expect(
              await main.window.open(main.key, {
                agent: 'codex',
                prompt: 'text',
              }),
            ).toEqual({ error: reason });
            expect(window.frame()).not.toContain('╭─ other ');
          },
          {
            server,
            runtimes: ['fake', 'codex'],
            columns,
            rows,
            startupOf: (agent) =>
              agent === 'codex' && refused
                ? { refused: reason, agentCommand: fakeAgentCommand() }
                : { agentCommand: fakeAgentCommand() },
          },
        );
      } finally {
        await server.close();
      }
    });
  }
});
