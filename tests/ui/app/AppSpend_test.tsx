/**
 * What the window reports the session spent: `/cost` during a turn, held
 * requests and cycles, whole-spend reports and turns on changed models.
 */
import { describe, expect, test } from 'bun:test';
import {
  withChild,
  openOther,
  pickAgent,
  readyAgent,
} from './child_window.tsx';
import { mkdir, writeFile, readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { readRecords } from '../../../src/session/sessions.ts';
import { readPast } from '../../../src/session/record.ts';
import { openSession } from '../../../src/session/session.ts';
import { serveChord } from '../../../src/server/server.ts';
import { fakeAgentCommand } from '../../fixtures/fake.ts';
import {
  DOWN,
  ESC,
  isAlive,
  leader,
  send,
  until,
  type Window,
  withWindow,
} from './render.tsx';

import { reported } from './app_window.tsx';

test("/cost while a turn runs says that turn is counted when it ends, beside the earlier turns' estimate, and no longer once it has ended (CHD-405)", () =>
  withWindow(
    async (window) => {
      await send(window, 'text');
      await window.shows('This reply came in chunks.');
      await until('the turn to end', () => !window.frame().includes('Working'));
      await send(window, 'slow');
      await window.shows('Working');

      const during = await reported(window, '/cost');

      expect(during).toContain('Total cost:   $');
      expect(during).toContain("(chord's estimate)");
      expect(during).toMatch(
        /Total cost:.*\n\s+This turn: {4}counted when it ends/,
      );

      await window.press(ESC);
      await until(
        'the turn to end',
        () => !window.frame().includes('Working…'),
      );
      expect(await reported(window, '/cost')).not.toContain('This turn:');
    },
    {
      agentCommand: fakeAgentCommand(undefined, '--tokens-only'),
      rows: 60,
    },
  ));

describe('CHD-405 N2 tester: held requests do not imply running spend', () => {
  for (const [columns, rows] of [
    [80, 24],
    [120, 40],
  ] as const) {
    test(`cost has no current-turn row while a between-turn permission remains open at ${columns} columns`, () =>
      withWindow(
        async (window) => {
          await readyAgent(window);
          await send(window, 'leftask');
          await window.shows('main asks · between turns');

          const cost = await reported(window, '/cost');

          expect(cost).toContain('fake has not reported');
          expect(cost).not.toContain('This turn:');
          expect(window.frame()).toContain('ctrl+x a to answer');
          expect(window.frame()).not.toContain('❯ 1. Allow');
        },
        {
          columns,
          rows,
          agentCommand: fakeAgentCommand(undefined, '--no-usage'),
        },
      ));
  }
});

describe('CHD-405 N2 tester: cycle-held permission cost', () => {
  for (const [columns, rows] of [
    [80, 24],
    [120, 40],
  ] as const) {
    test(`a held cycle has a current-turn row until its end, while a plain held request does not at ${columns} columns`, () =>
      withWindow(
        async (window) => {
          await readyAgent(window);
          await send(window, 'claudecycleask');
          await window.shows('main asks · between turns');
          expect(await reported(window, '/cost')).toContain(
            'counted when it ends',
          );
          await leader(window, 'a');
          await window.shows('❯ 1. Allow');
          await window.press('1');
          await window.shows('Permission: allow.');
          await until(
            'the cycle ended',
            () => !window.frame().includes('Working…'),
          );
          expect(await reported(window, '/cost')).not.toContain('This turn:');
          await send(window, 'leftask');
          await window.shows('main asks · between turns');
          expect(await reported(window, '/cost')).not.toContain('This turn:');
        },
        {
          columns,
          rows,
          agentCommand: fakeAgentCommand(
            undefined,
            '--adapter',
            'claude',
            '--no-usage',
          ),
        },
      ));
  }
});

describe('CHD-373 S4 tester: whole-spend reports in the window', () => {
  const table = (window: Window) => {
    const lines = window.frame().split('\n');
    const start = lines.findLastIndex((line) => line.includes('This session'));

    expect(start).toBeGreaterThanOrEqual(0);

    return lines.slice(start).filter((line) => line.trim() !== '');
  };

  const row = (window: Window, name: string) =>
    table(window).find((line) => line.trimStart().startsWith(name)) ?? '';
  const teamBreakdown = (window: Window) => {
    const shown = table(window);

    return shown
      .slice(
        shown.findIndex((line) => line.trimStart().startsWith('bugfix')),
        shown.findIndex((line) =>
          line.trimStart().startsWith('Count the cost'),
        ),
      )
      .join(' ');
  };

  const showCost = async (window: Window, total?: string) => {
    await send(window, '/cost');
    await window.shows('This session');

    if (total) {
      await until('current cost snapshot', () =>
        row(window, 'Total').includes(total),
      );
    }
  };

  const rootTurns = async (window: Window, prompt: string, count: number) => {
    await until('root usage recorded', async () => {
      const records = await readRecords(join(window.dir, 'state'));
      const record = records.find(
        (each) => each.parent === undefined && each.prompt === prompt,
      );

      if (!record) {
        return false;
      }

      const lines = await readPast(record.path);

      return (
        new Set(
          lines.flatMap((entry) =>
            entry.type === 'usage' ? [entry.turnId] : [],
          ),
        ).size >= count
      );
    });
  };

  async function onWindow(
    body: (window: Window) => Promise<void>,
    columns: number,
    flags: string[] = [],
    more: NonNullable<Parameters<typeof withWindow>[1]> = {},
  ) {
    const server = serveChord();

    try {
      await withWindow(body, {
        columns,
        rows: columns === 80 ? 24 : 40,
        server,
        runtimes: ['fake'],
        agentCommand: fakeAgentCommand(undefined, ...flags),
        ...more,
      });
    } finally {
      await server.close();
    }
  }

  for (const columns of [80, 120]) {
    test(`closed child and clear history remain in /cost at ${columns} columns`, () =>
      onWindow(async (window) => {
        await readyAgent(window);
        await send(window, 'agentcost');
        await window.shows('Waiting on parser.');
        await rootTurns(window, 'agentcost', 1);
        await window.press(DOWN);
        await window.press(DOWN);
        await window.shows('Working until stopped.');
        await window.press('x');
        await window.shows('x again to stop');
        await window.press('x');
        await window.shows('The person closed parser');
        await rootTurns(window, 'agentcost', 2);
        await until(
          'parser process closed',
          async () => !(await isAlive(window.pids[1]!)),
        );
        await showCost(window, '$0.0350');
        expect(row(window, 'parser')).toContain('$0.0100');
        expect(row(window, 'parser')).toContain('closed');
        expect(row(window, 'Total')).toContain('$0.0350');

        await send(window, '/clear');
        await readyAgent(window);
        await send(window, 'text');
        await rootTurns(window, 'text', 1);
        await showCost(window, '$0.0475');
        expect(row(window, 'before /clear')).toContain('$0.0250');
        expect(row(window, 'parser')).toContain('$0.0100');
        expect(row(window, 'Total')).toContain('$0.0475');
      }, columns));

    test(`a closed child's ended task stays under its owner and is added once at ${columns} columns`, () =>
      onWindow(async (window) => {
        await readyAgent(window);
        await send(window, 'agenttask');
        await window.shows('Waiting on parser.');
        await rootTurns(window, 'agenttask', 1);
        await window.shows('1 task asking');
        await until('parser spawning turn recorded', async () => {
          const records = await readRecords(join(window.dir, 'state'));
          const parser = records.find((record) => record.name === 'parser');

          if (!parser) {
            return false;
          }

          const past = await readPast(parser.path);
          const prompt = past.find((entry) => entry.type === 'prompt');

          return (
            prompt?.type === 'prompt' &&
            past.some(
              (entry) =>
                entry.type === 'result' && entry.turnId === prompt.turnId,
            )
          );
        });

        await leader(window, 'a');
        await window.shows('between turns');
        await leader(window, 'a');
        await window.shows('Agent(Fix the tokenizer)');
        await window.shows('Esc to reject');
        await window.press('1');
        await window.shows('Received the message from Fix the tokenizer');
        // The early progress message precedes the task's report and usage.
        await window.shows('← from Fix the tokenizer · fake · report');
        await window.press(DOWN);
        await window.shows('❯ parser');
        await window.press('x');
        await until(
          'child close decision',
          () =>
            window.frame().includes('x again to stop') ||
            window.frame().includes('The person closed parser'),
        );

        if (window.frame().includes('x again to stop')) {
          await window.press('x');
        }

        await window.shows('The person closed parser');
        await rootTurns(window, 'agenttask', 2);
        await until(
          'parser process closed',
          async () => !(await isAlive(window.pids[1]!)),
        );
        await showCost(window);

        const parser = row(window, 'parser');
        const task = row(window, 'Fix the tokenizer');
        const amount = (line: string) => {
          const matched = line.match(/\$(\d+\.\d+)/);

          expect(matched).not.toBeNull();

          return Number(matched![1]);
        };

        expect(parser).toContain('closed');
        expect(task).toContain('$0.0125');
        expect(task).toContain('ended');
        expect(task.indexOf('Fix the tokenizer')).toBe(
          parser.indexOf('parser') + 2,
        );
        expect(amount(row(window, 'Total'))).toBeCloseTo(
          amount(row(window, 'main')) + amount(parser) + 0.0125,
          9,
        );
      }, columns));

    test(`an agent that exits without usage stays not reported rather than zero at ${columns} columns`, () =>
      onWindow(async (window) => {
        await readyAgent(window);
        await send(window, 'agentexit');
        await window.shows('Received the message from chord.');
        await window.shows('parser exited');
        await rootTurns(window, 'agentexit', 2);
        expect(window.pids.length).toBeGreaterThanOrEqual(2);
        await until(
          'exited parser reaped',
          async () => !(await isAlive(window.pids[1]!)),
        );
        await showCost(window);

        const parser = row(window, 'parser');
        const total = row(window, 'Total');
        const main = row(window, 'main');

        expect(parser).toContain('not reported');
        expect(parser).not.toContain('$0.0000');
        expect(total).toContain('not reported');
        expect(Number(total.match(/\$(\d+\.\d+)/)?.[1])).toBeCloseTo(
          Number(main.match(/\$(\d+\.\d+)/)?.[1]),
          9,
        );
      }, columns));

    test(`a team's task is owned by tester and kept out of the run subtotal at ${columns} columns`, async () => {
      const team = await readFile(
        new URL('../../fixtures/teams/fake/bugfix.md', import.meta.url),
        'utf8',
      );

      await onWindow(
        async (window) => {
          await readyAgent(window);
          await send(window, 'team');
          await window.shows('Team(bugfix)');
          await window.shows('1 task running');
          await until('all team members recorded', async () => {
            const records = await readRecords(join(window.dir, 'state'));

            return ['tester', 'coder'].every((name) =>
              records.some((record) => record.name === name),
            );
          });

          await until('team task cost recorded', async () => {
            const records = await readRecords(join(window.dir, 'state'));
            const task = records.find(
              (record) => record.name === 'Count the cost',
            );

            return (
              task !== undefined &&
              (await readPast(task.path)).some(
                (entry) =>
                  entry.type === 'update' &&
                  entry.update.sessionUpdate === 'usage_update' &&
                  entry.update.cost?.amount === 0.01,
              )
            );
          });

          await showCost(window);

          const run = row(window, 'bugfix');
          const task = row(window, 'Count the cost');
          const amount = (line: string) => {
            const matched = line.match(/\$(\d+\.\d+)/);

            expect(matched).not.toBeNull();

            return Number(matched![1]);
          };

          expect(run).not.toContain('Count the cost');
          expect(task).toContain('running');
          expect(task).toMatch(/Count the cost\s+—\s+—/);

          if (columns === 80) {
            expect(run).toContain('team run: lead');

            for (const member of ['lead', 'tester', 'coder']) {
              expect(teamBreakdown(window)).toContain(member + ' ');
            }
          }

          if (columns === 120) {
            expect(task).toContain('task agent of tester');
          }

          expect(task.indexOf('Count the cost')).toBe(
            run.indexOf('bugfix') + 2,
          );
          expect(amount(row(window, 'Total'))).toBeCloseTo(
            amount(row(window, 'main')) + amount(run),
            9,
          );

          // Pick tester in the real list and close its still-running task with it.
          await window.press(DOWN);
          await window.press(DOWN);
          await window.press(DOWN);
          await window.shows('╭─ tester · bugfix');
          await window.press('x');
          await window.shows('x again to stop');
          await window.press('x');
          await until('tester closed in the records', async () => {
            const records = await readRecords(join(window.dir, 'state'));
            const lead = records.find((record) => record.name === 'bugfix');
            const tester = records.find((record) => record.name === 'tester');

            if (!lead || !tester) {
              return false;
            }

            const header = (await readPast(tester.path))[0];

            return (
              header?.type === 'session' &&
              (await readPast(lead.path)).some(
                (entry) => entry.type === 'closed' && entry.agent === header.id,
              )
            );
          });

          await window.press(ESC);
          await send(window, '/cost');
          await window.shows('This session');
          await until('ended task in cost snapshot', () =>
            row(window, 'Count the cost').includes('$0.0100'),
          );

          const ended = row(window, 'Count the cost');
          const keptRun = row(window, 'bugfix');

          expect(ended).toContain('ended');

          if (columns === 120) {
            expect(ended).toContain('task agent of tester');
          }

          expect(amount(row(window, 'Total'))).toBeCloseTo(
            amount(row(window, 'main')) + amount(keptRun) + 0.01,
            9,
          );

          if (columns === 80) {
            expect(keptRun).toMatch(/team run(, ended)?: lead/);

            for (const member of ['lead', 'tester', 'coder']) {
              expect(teamBreakdown(window)).toContain(member + ' ');
            }
          }
        },
        columns,
        ['--tester-plays', 'taskcost'],
        {
          teams: { bugfix: team },
          startupOf: () => ({
            agentCommand: fakeAgentCommand(
              undefined,
              '--tester-plays',
              'taskcost',
            ),
          }),
        },
      );
    });

    test(`an estimated session beside a silent agent keeps the estimate and missing note at ${columns} columns`, () =>
      onWindow(
        async (window) => {
          await readyAgent(window);
          await send(window, 'text');
          await rootTurns(window, 'text', 1);
          await send(window, 'agentother');
          await pickAgent(window, 'other');
          await readyAgent(window);
          await send(window, 'text');
          await window.shows('This reply came in chunks.');
          await until(
            'silent turn ended',
            () => !window.frame().includes('Working…'),
          );
          await showCost(window);

          const estimate = row(window, 'main');
          const total = row(window, 'Total');

          expect(estimate).toContain('~$');
          expect(row(window, 'other')).toContain('not reported');
          expect(total).toContain('~$');
          expect(total).toContain('not reported');

          const estimatedAmount = Number(estimate.match(/\$(\d+\.\d+)/)?.[1]);
          const totalAmount = Number(total.match(/\$(\d+\.\d+)/)?.[1]);

          expect(Number.isFinite(estimatedAmount)).toBe(true);
          expect(totalAmount).toBeCloseTo(estimatedAmount, 9);
          expect(estimate).toContain("chord's estimate");
        },
        columns,
        ['--tokens-only'],
        {
          runtimes: ['fake', 'silent'],
          agentCommand: fakeAgentCommand(
            undefined,
            '--tokens-only',
            '--child-runtime',
            'silent',
          ),
          startupOf: (agent) => ({
            agentCommand:
              agent === 'silent'
                ? fakeAgentCommand(undefined, '--no-usage')
                : fakeAgentCommand(undefined, '--tokens-only'),
          }),
        },
      ));
  }

  test('a resumed legacy record says Before and Not counted without silently turning unknown spend into zero', async () => {
    let seeded = false;

    await onWindow(
      async (window) => {
        await readyAgent(window);
        await send(window, '/resume');
        await window.shows('legacy seed');
        await window.press('\r');
        await window.shows('› legacy seed');
        await readyAgent(window);
        await send(window, 'text');
        await rootTurns(window, 'legacy seed', 2);
        await send(window, '/cost');
        await window.shows('Not counted:');

        const shown = window.frame();

        expect(shown).toContain('Before:');
        expect(shown).toContain('$0.0400 as last reported');
        expect(shown).toContain('1 turn');
        expect(shown).toContain('Total cost:');
        expect(shown).toContain('$0.0400');
      },
      120,
      ['--resume-only', '--cost-from', '0.04'],
      {
        readRecords: async (stateDir) => {
          if (!seeded) {
            seeded = true;

            const dir = join(stateDir, 'records');
            const id = crypto.randomUUID();
            const entries = [
              {
                type: 'session',
                version: 1,
                sessionId: id,
                agent: 'fake',
                cwd: stateDir.slice(0, -'/state'.length),
                at: 1,
              },
              {
                type: 'prompt',
                turnId: 'legacy',
                prompt: 'legacy seed',
                images: 0,
                at: 1,
              },
              {
                type: 'update',
                turnId: 'legacy',
                update: {
                  sessionUpdate: 'usage_update',
                  used: 10,
                  size: 100,
                  cost: { amount: 0.04, currency: 'USD' },
                },
              },
              { type: 'usage', turnId: 'legacy', usage: { totalTokens: 2000 } },
              {
                type: 'result',
                turnId: 'legacy',
                result: { status: 'completed', stopReason: 'end_turn' },
                at: 2,
              },
            ];

            await mkdir(dir, { recursive: true });
            await writeFile(
              join(dir, `${id}.jsonl`),
              entries.map((entry) => JSON.stringify(entry)).join('\n') + '\n',
            );
          }

          return readRecords(stateDir);
        },
      },
    );
  });
});

describe('CHD-472 U2 tester: model changes price only the growth (Q133)', () => {
  for (const columns of [80, 120]) {
    for (const [model, moves, expected] of [
      ['claude-haiku-4-5', 1, '$0.0068'],
      ['claude-opus-5-5', 2, '$0.0129'],
    ] as const) {
      test(`${model} after Codex keeps both prices at ${columns} columns`, () => {
        let readings = 0;
        let unsubscribe: (() => void) | undefined;

        return withChild(
          async (window) => {
            await readyAgent(window);
            await openOther(window);
            await pickAgent(window, 'other');
            await until(
              'dirac session opened',
              () => window.session()?.agent === 'dirac',
            );

            const connected = () =>
              until(
                'dirac prompt ready',
                () =>
                  !window.frame().includes('Starting dirac') &&
                  window
                    .frame()
                    .split('\n')
                    .some(
                      (line) =>
                        line.includes('? for shortcuts') &&
                        !line.includes('/help'),
                    ),
              );

            await connected();

            try {
              await until('first cost reading', () => readings === 1);
              await connected();
              await send(window, '/model');
              await window.shows("Switch dirac's model");

              for (let move = 0; move < moves; move++) {
                await window.press(DOWN);
              }

              await window.press('\r');
              await until(
                'new model selected',
                () =>
                  window.session()!.models()?.current === model &&
                  !window.frame().includes("Switch dirac's model"),
              );
              await send(window, 'text');
              await until('second cost reading', () => readings === 2);
              await connected();
              await send(window, '/cost');
              await window.shows('Tokens in:    2,000');

              const words = window.frame().replace(/\s+/g, ' ');

              expect(words).toContain(
                `Total cost: ${expected} (chord's estimate)`,
              );
              expect(words).toContain(
                "dirac's provider reports no cost, so chord priced each answer's tokens at the price of the model that gave it.",
              );
              expect(words).not.toContain('Not counted:');
            } finally {
              unsubscribe?.();
            }
          },
          {
            columns,
            rows: 40,
            runtimes: ['fake', 'dirac'],
            agentCommand: fakeAgentCommand(
              undefined,
              '--child-runtime',
              'dirac',
            ),
            openWith: async (options) => {
              const session = await openSession(options);

              if (options.agent === 'dirac') {
                unsubscribe = session.subscribe((update) => {
                  if (update.sessionUpdate === 'usage_update') {
                    readings++;
                  }
                });
              }

              return session;
            },
            startupOf: (agent) => ({
              agentCommand:
                agent === 'dirac'
                  ? fakeAgentCommand(
                      undefined,
                      '--session-usage',
                      '--tokens-only',
                    )
                  : fakeAgentCommand(),
            }),
          },
        );
      });
    }
  }
});

describe('CHD-472 mixed tester: unpriced turns stay counted through further model changes', () => {
  for (const columns of [80, 120]) {
    for (const [models, cost, missing] of [
      [
        ['gpt-5.3-codex', 'fake-unpriced', 'claude-haiku-4-5'],
        '$0.0068',
        '1 turn',
      ],
      [
        ['fake-unpriced', 'gpt-5.3-codex', 'fake-unpriced'],
        '$0.0047',
        '2 turns',
      ],
    ] as const) {
      test(`${models.join(' → ')} at ${columns} columns`, () => {
        let reply = '';
        let unsubscribe: (() => void) | undefined;

        return withChild(
          async (window) => {
            await readyAgent(window);
            await openOther(window);
            await pickAgent(window, 'other');
            await until(
              'dirac opened',
              () => window.session()?.agent === 'dirac',
            );

            const connected = () =>
              until(
                'prompt ready',
                () =>
                  !window.frame().includes('Starting dirac') &&
                  window
                    .frame()
                    .split('\n')
                    .some(
                      (line) =>
                        line.includes('? for shortcuts') &&
                        !line.includes('/help'),
                    ),
              );

            await connected();

            try {
              for (const [index, model] of models.entries()) {
                if (window.session()!.models()?.current !== model) {
                  await send(window, '/model');
                  await window.shows("Switch dirac's model");
                  await window.press(
                    model === 'fake-unpriced'
                      ? '5'
                      : model === 'gpt-5.3-codex'
                        ? '1'
                        : '2',
                  );
                  await until(
                    'model chosen',
                    () =>
                      window.session()!.models()?.current === model &&
                      !window.frame().includes("Switch dirac's model"),
                  );
                }

                if (index !== 0) {
                  await send(window, 'text');
                }

                await until(
                  'reply complete',
                  () =>
                    (reply.match(/This reply came in chunks\./g) ?? [])
                      .length ===
                    index + 1,
                );
                await connected();
              }

              await send(window, '/cost');
              await until('last total on screen', () =>
                /Tokens in:\s+3,000/.test(window.frame()),
              );

              const words = window.frame().replace(/\s+/g, ' ');

              expect(words).toContain(`Total cost: ${cost} (chord's estimate)`);
              expect(words).toContain(`Not counted: ${missing}`);
              expect(words).toContain(
                "dirac's provider reports no cost, so chord priced each answer's tokens at the price of the model that gave it; it has no price for Fake Unpriced.",
              );
              expect(words).not.toContain("(part chord's estimate)");
            } finally {
              unsubscribe?.();
            }
          },
          {
            columns,
            rows: 40,
            runtimes: ['fake', 'dirac'],
            agentCommand: fakeAgentCommand(
              undefined,
              '--child-runtime',
              'dirac',
            ),
            openWith: async (options) => {
              const session = await openSession(options);

              if (options.agent === 'dirac') {
                unsubscribe = session.subscribe((update) => {
                  if (
                    update.sessionUpdate === 'agent_message_chunk' &&
                    update.content.type === 'text'
                  ) {
                    reply += update.content.text;
                  }
                });
              }

              return session;
            },
            startupOf: (agent) => ({
              ...(agent === 'dirac' ? { model: models[0] } : {}),
              agentCommand:
                agent === 'dirac'
                  ? fakeAgentCommand(
                      undefined,
                      '--session-usage',
                      '--tokens-only',
                      '--no-cost',
                      '--unpriced-model',
                    )
                  : fakeAgentCommand(),
            }),
          },
        );
      });
    }
  }
});
