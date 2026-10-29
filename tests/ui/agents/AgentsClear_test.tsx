/**
 * clear_agent: a parent clears a child it opened, which keeps its id and
 * name in a fresh session that knows nothing of earlier turns (CHD-476).
 */
import { describe, expect, test } from 'bun:test';
import assert from 'node:assert/strict';
import { existsSync } from 'node:fs';
import { readFile, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { quote } from 'shell-quote';
import type { WindowedState } from '../../../src/ui/app/state.ts';
import { openSession, type Session } from '../../../src/session/session.ts';
import { fakeAgentCommand } from '../../fixtures/fake.ts';
import type { Admitted } from '../../../src/server/server.ts';
import { serveChord } from '../../../src/server/server.ts';
import type { Caller } from '../../../src/server/tools.ts';
import {
  DOWN,
  isAlive,
  ready,
  send,
  until,
  UP,
  type Window,
  withWindow,
} from '../app/render.tsx';
import { count, withAgents } from './agents_window.tsx';
import { BUGFIX, withTeams } from './teams_window.tsx';
import { PIXEL_BYTES, PIXEL_PNG } from '../../fixtures/images.ts';
import { RECEIVED } from '../prompt/prompt_window.tsx';

/** Picks `name` in the list under the prompt and shows it. */
async function pick(window: Window, name: string) {
  await window.press(DOWN);
  await until(`${name} picked in the list`, async () => {
    if (new RegExp(`❯ (└─ )?${name} `).test(window.frame())) {
      return true;
    }

    await window.press(DOWN);

    return false;
  });

  await window.press('\r');
  await window.shows(`╭─ ${name} `);
}

test('main clears its working child: the queued message is not delivered and said so, the next is its first, an unknown name is refused, and main is told nothing more', () =>
  withAgents(async (window) => {
    await ready(window);
    await send(window, 'agentcost');
    await window.shows('Open(parser)');
    await until('parser at work', () =>
      /^ {4}parser .*✻/m.test(window.frame()),
    );
    await send(window, 'agentclear');
    await window.shows('parser was cleared.');

    expect(window.frame()).toContain('Clear(parser)');
    expect(window.frame()).toMatch(/Fresh session · id \w+/);
    expect(window.frame()).toContain(
      '1 queued message from main was not delivered.',
    );
    expect(window.frame()).toContain('Clear(nobody)');
    expect(window.frame()).not.toContain('The person cleared');
    expect(count(window, '    parser ')).toBe(1);

    // Its view has the message sent after the clear and its answer, and
    // nothing of the work before it.
    await pick(window, 'parser');
    await window.shows('This reply came in chunks.');

    expect(window.frame()).not.toContain('Queued before the clear.');
    await window.press(DOWN);
    await window.press(UP);
  }));

test("a lead clears its member: the member's next message carries the team's part again, as a first one does", () =>
  withTeams(async (window) => {
    await ready(window);
    await send(window, '/team run bugfix leadclear');
    await window.shows('└─ tester ');
    await pick(window, 'bugfix');
    await window.shows('tester was cleared.');

    expect(window.frame()).toContain('Clear(tester)');
    await pick(window, 'tester');
    await window.shows('The team part from bugfix reached this session.');
  }));

test('the old session of a cleared child reaches no one once it is let go, even as it still runs', () =>
  withAgents(async (window) => {
    await ready(window);
    await send(window, 'agentlate');
    await window.shows('Open(parser)');
    await until('parser at work', () =>
      /^ {4}parser .*✻/m.test(window.frame()),
    );
    await send(window, 'agentclearonly');
    await window.shows('parser was cleared.');
    // Another round trip of main's, by which the old turn has tried.
    await send(window, 'text');
    await window.shows('This reply came in chunks.');

    expect(window.frame()).not.toContain('Late from the old session.');
  }));

test('two clears at once: one is refused, and a message sent meanwhile goes once to the fresh session, as its first', () =>
  withTeams(async (window) => {
    await ready(window);
    await send(window, '/team run bugfix leadclearrace');
    await window.shows('└─ tester ');
    await pick(window, 'bugfix');
    await window.shows('tester was cleared once.');

    expect(window.frame()).toContain(
      'Could not clear tester: it is being cleared already',
    );
    expect(window.frame()).toMatch(/Fresh session · id \w+/);
    await pick(window, 'tester');
    await window.shows('The team part from bugfix reached this session.');

    expect(
      count(window, 'The team part from bugfix reached this session.'),
    ).toBe(1);
  }));

test("the person's first message to a member its lead cleared carries the team's part, as a first one does", () =>
  withTeams(async (window) => {
    await ready(window);
    await send(window, '/team run bugfix leadclearonly');
    await window.shows('└─ tester ');
    await pick(window, 'bugfix');
    await window.shows('tester was cleared.');
    await pick(window, 'tester');
    await send(window, 'teampartof');
    await window.shows('The team part from the person reached this session.');
  }));

/** A window on the fake, and main's caller as chord's server admitted it. */
async function withMain(body: (window: Window, main: Caller) => Promise<void>) {
  const server = serveChord();
  const admit = server.admit.bind(server);
  let main: Caller | undefined;

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
        assert(main?.launch);
        await body(window, main);
      },
      { server, runtimes: ['fake'], columns: 120, rows: 40 },
    );
  } finally {
    await server.close();
  }
}

/** `main` as it would speak once its session has been let go meanwhile. */
function lettingGo(main: Caller): { caller: Caller; letGo: () => void } {
  let live = true;

  assert(main.launch);

  const { signal } = main.launch;

  return {
    caller: { ...main, launch: { valid: () => live, signal } },
    letGo: () => {
      live = false;
    },
  };
}

test('a spawn_task or open_agent whose session is let go while it waits starts nothing', () =>
  withMain(async (window, main) => {
    const spawning = lettingGo(main);
    const spawned = main.window.spawn(spawning.caller, {
      agent: 'fake',
      prompt: 'text',
    });

    spawning.letGo();

    expect(await spawned).toStrictEqual({
      error: 'Your session was cleared or closed; nothing more goes from it',
    });

    const opening = lettingGo(main);
    const opened = main.window.open(
      main.key,
      { agent: 'fake', prompt: 'text', name: 'late' },
      opening.caller,
    );

    opening.letGo();

    expect(await opened).toStrictEqual({
      error: 'Your session was cleared or closed; nothing more goes from it',
    });
    expect(window.frame()).not.toContain('late');
  }));

test('a child closed while it restarts says the message sent meanwhile was not delivered', () =>
  withMain(async (window, main) => {
    const opened = await main.window.open(main.key, {
      agent: 'fake',
      prompt: 'text',
      name: 'parser',
    });

    expect(opened).toHaveProperty('id');
    // Up and done with its first prompt, so nothing of that is waiting.
    await until('parser replied', () =>
      /^ {4}parser .*✓ new reply/m.test(window.frame()),
    );

    const clearing = main.window.clear(main, 'parser');
    const told = main.window.tell(
      main,
      'parser',
      'During the restart.',
      () => {},
    );

    main.window.close(main, 'parser');

    expect(told).toMatchObject({ delivered: 'queued' });
    expect(await clearing).toStrictEqual({
      error:
        'Could not clear parser: it was closed. 1 queued message from main was not delivered.',
    });
  }));

test("the person's /clear on a working child: its turn goes, their queued prompt comes back into the box, and its view starts over", () =>
  withAgents(async (window) => {
    await ready(window);
    await send(window, 'agentcost');
    await window.shows('Open(parser)');
    await until('parser at work', () =>
      /^ {4}parser .*✻/m.test(window.frame()),
    );
    await pick(window, 'parser');
    await window.shows('Working until stopped.');
    await send(window, 'Later.');
    await window.shows('› Later.');
    await send(window, '/clear');
    await until(
      "parser's view empty",
      () => !window.frame().includes('Working until stopped.'),
    );
    await until('the queued prompt back in the box', () =>
      window.frame().includes('│ › Later.'),
    );

    expect(window.frame()).toContain('╭─ parser ');
    expect(window.frame()).toMatch(/^ {4}parser .*◦ idle/m);
  }));

test("main's clear_agent puts the person's queued prompt for the child back into the child's box, whatever is in front", () =>
  withAgents(async (window) => {
    await ready(window);
    await send(window, 'agentcost');
    await window.shows('Open(parser)');
    await until('parser at work', () =>
      /^ {4}parser .*✻/m.test(window.frame()),
    );
    await pick(window, 'parser');
    await window.shows('Working until stopped.');
    await send(window, 'Later.');
    await window.shows('› Later.');
    await window.press(DOWN);
    await until('main picked in the list', async () => {
      if (window.frame().includes('  ❯ main ')) {
        return true;
      }

      await window.press(UP);

      return false;
    });

    await window.press('\r');
    await until('main in view', () => !/╭─ \S/.test(window.frame()));
    await send(window, 'agentclearonly');
    await window.shows('parser was cleared.');
    await pick(window, 'parser');
    await until('the queued prompt back in its box', () =>
      window.frame().includes('│ › Later.'),
    );
  }));

for (const columns of [80, 120]) {
  test(`a queued prompt's image comes back with it after /clear and goes when it is sent again, at ${columns} columns`, async () => {
    const server = serveChord();

    try {
      await withWindow(
        async (window) => {
          await ready(window);
          await send(window, 'agentcost');
          await window.shows('Open(parser)');
          await until('parser at work', () =>
            /^ {4}parser .*✻/m.test(window.frame()),
          );
          await pick(window, 'parser');
          await window.shows('Working until stopped.');

          // Typed key by key: pasted, the path would be read at once.
          for (const key of 'see /shots/a.png') {
            await window.press(key);
          }

          await window.press('\r');
          await window.shows('› see [Image #1]');
          await send(window, '/clear');
          await until('the queued prompt back in its box', () =>
            window.frame().includes('│ › see [Image #1]'),
          );
          // Enter sends once the fresh session is up; before, it waits.
          await until('sent to the fresh session', async () => {
            if (!window.frame().includes('│ › see [Image #1]')) {
              return true;
            }

            await window.press('\r');

            return false;
          });

          await window.shows(RECEIVED);
        },
        {
          server,
          runtimes: ['fake'],
          columns,
          rows: columns === 80 ? 24 : 40,
          readImage: () =>
            Promise.resolve({
              mediaType: 'image/png',
              data: PIXEL_PNG,
              bytes: PIXEL_BYTES.length,
            }),
        },
      );
    } finally {
      await server.close();
    }
  });
}

describe('CHD-476 U1 tester: restart generations and held deliveries', () => {
  for (const fails of [false, true]) {
    test(`a ${fails ? 'failed' : 'successful'} gated restart revokes old authority and preserves child identity`, async () => {
      const server = serveChord();
      const admit = server.admit.bind(server);
      const admissions: { caller: Caller; admission: Admitted }[] = [];
      const sessions: Session[] = [];
      const restart = Promise.withResolvers<void>();
      let restarting = false;
      let entered = false;
      const sent: string[] = [];

      server.admit = (caller) => {
        const admission = admit(caller);

        admissions.push({ caller, admission });

        return admission;
      };

      try {
        await withWindow(
          async (window) => {
            try {
              await ready(window);

              const main = admissions[0]!.caller;
              const opened = await main.window.open(main.key, {
                agent: 'fake',
                name: 'worker',
                prompt: '/echo startup-job',
              });

              assert('id' in opened);
              await until('worker startup complete', () =>
                sent.some((text) => text.includes('startup-job')),
              );
              await until('worker idle', () =>
                /^ {4}worker .*◦ idle/m.test(window.frame()),
              );

              const old = admissions.find(
                ({ caller }) => caller.agent === opened.id,
              );

              assert(old);

              const before = main.window
                .sessions()[0]!
                .children.find((child) => child.id === opened.id);
              const oldSession = sessions[1]!;
              const oldPromptCount = sent.length;

              restarting = true;

              const pending = old.caller.window.spawn(old.caller, {
                agent: 'fake',
                prompt: 'text',
                name: 'stale-task',
              });
              const clearing = main.window.clear(main, opened.id);

              await until('restart gate reached', () => entered);
              expect(old.caller.launch?.valid()).toBe(false);
              expect(
                (
                  await fetch(server.url, {
                    headers: { Authorization: `Bearer ${old.admission.token}` },
                  })
                ).status,
              ).toBe(401);
              expect(await pending).toHaveProperty('error');
              expect(
                main.window.tell(main, opened.id, '/echo held-one', () => {}),
              ).toMatchObject({ delivered: 'queued' });
              expect(
                main.window.tell(main, 'worker', '/echo held-two', () => {}),
              ).toMatchObject({ delivered: 'queued' });
              expect(await main.window.clear(main, 'worker')).toMatchObject({
                error: 'Could not clear worker: it is being cleared already',
              });
              expect(sent).toHaveLength(oldPromptCount);
              restart.resolve();

              const answer = await clearing;

              if (fails) {
                expect(answer).toHaveProperty('error');
                expect(JSON.stringify(answer)).toContain(
                  '2 queued messages from main were not delivered.',
                );
                expect(sent).toHaveLength(oldPromptCount);
              } else {
                expect(answer).toMatchObject({
                  cleared: 'worker',
                  id: opened.id,
                });
                await until(
                  'both held messages delivered once',
                  () => sent.slice(oldPromptCount).length === 2,
                );
                expect(
                  sent
                    .slice(oldPromptCount)
                    .filter((text) => text.includes('held-one')),
                ).toHaveLength(1);
                expect(
                  sent
                    .slice(oldPromptCount)
                    .filter((text) => text.includes('held-two')),
                ).toHaveLength(1);
                expect(sent.slice(oldPromptCount).join('')).not.toContain(
                  'startup-job',
                );
                expect(sessions.at(-1)!.id).not.toBe(oldSession.id);
              }

              const after = main.window
                .sessions()[0]!
                .children.find((child) => child.id === opened.id);

              expect(after).toMatchObject({
                id: before!.id,
                name: before!.name,
                runtime: before!.runtime,
              });
              expect(
                main.window.sessions()[0]!.children.map((child) => child.id),
              ).toStrictEqual([opened.id]);
              expect(main.window.sessions()).toHaveLength(1);
            } finally {
              restart.resolve();
            }
          },
          {
            server,
            runtimes: ['fake'],
            columns: 80,
            rows: 24,
            openWith: async (options) => {
              if (restarting) {
                entered = true;

                await restart.promise;
              }

              const session = await openSession(
                restarting && fails
                  ? {
                      ...options,
                      agentCommand: fakeAgentCommand(
                        undefined,
                        '--start-fails',
                        'stdout',
                      ),
                    }
                  : options,
              );
              const prompt = session.prompt.bind(session);

              session.prompt = (...args) => {
                sent.push(args[0]);

                return prompt(...args);
              };

              sessions.push(session);

              return session;
            },
          },
        );
      } finally {
        restart.resolve();
        await server.close();
      }
    });
  }
});

describe('CHD-476 U1 tester: clearing owned work without closing peers', () => {
  test('old tasks and monitors stop while main and a long-lived sibling remain addressable', async () => {
    const server = serveChord();
    const admit = server.admit.bind(server);
    const callers: Caller[] = [];
    const opened: Session[] = [];
    const firstSent = new Set<string>();

    server.admit = (caller) => {
      callers.push(caller);

      return admit(caller);
    };

    try {
      await withWindow(
        async (window) => {
          await ready(window);

          const main = callers[0]!;
          const owner = await main.window.open(main.key, {
            agent: 'fake',
            name: 'owner',
            prompt: 'text',
          });

          await until(
            'owner first job went before sibling opens',
            () => opened.length === 2 && firstSent.size === 1,
          );

          const sibling = await main.window.open(main.key, {
            agent: 'fake',
            name: 'sibling',
            prompt: 'text',
          });

          assert('id' in owner && 'id' in sibling);

          const source = callers.find((caller) => caller.agent === owner.id);

          assert(source);

          await until(
            'both long-lived first jobs went',
            () => opened.length === 3 && firstSent.size === 2,
          );

          const survivors = opened.slice();
          const sourceSession = survivors[1]!;

          await until('owner connected', () =>
            /^ {4}owner .*◦ idle/m.test(window.frame()),
          );

          const task = await source.window.spawn(source, {
            agent: 'fake',
            name: 'owned-task',
            prompt: 'costwait',
          });

          assert('id' in task, JSON.stringify(task));
          await until('task opened', () => opened.length === 4);

          const taskSession = opened[3]!;
          const monitor = source.window.monitor(source, {
            command: quote([
              process.execPath,
              '-e',
              'require("node:fs").writeFileSync("clear-monitor.pid", String(process.pid)); setInterval(() => {}, 1000)',
            ]),
            description: 'clear ownership fixture',
          });

          expect(monitor).not.toHaveProperty('error');
          await until('monitor recorded its pid', () =>
            existsSync(join(window.dir, 'clear-monitor.pid')),
          );

          const monitorPid = Number(
            await readFile(join(window.dir, 'clear-monitor.pid'), 'utf8'),
          );

          expect(await main.window.clear(main, owner.id)).toMatchObject({
            cleared: 'owner',
            id: owner.id,
          });

          for (const [kind, pid] of [
            ...[...sourceSession.agentPids].map(
              (pid) => ['source', pid] as const,
            ),
            ...[...taskSession.agentPids].map((pid) => ['task', pid] as const),
            ['monitor', monitorPid] as const,
          ]) {
            await until(
              `old owned ${kind} process ${pid} stopped`,
              async () => !(await isAlive(pid)),
            );
          }

          for (const session of survivors.filter(
            (session) => session !== sourceSession,
          )) {
            for (const pid of session.agentPids) {
              expect(await isAlive(pid)).toBe(true);
            }
          }

          const fresh = callers.findLast((caller) => caller.agent === owner.id);

          assert(fresh && fresh !== source);
          expect(fresh.window.monitors(fresh)).toStrictEqual([]);
          expect(
            main.window.tell(
              main,
              sibling.id,
              '/echo sibling-survived',
              () => {},
            ),
          ).not.toHaveProperty('error');
          expect(
            main.window.sessions()[0]!.children.map((child) => child.id),
          ).toStrictEqual([owner.id, sibling.id]);
          expect(await source.window.clear(source, sibling.id)).toHaveProperty(
            'error',
          );
        },
        {
          server,
          runtimes: ['fake'],
          columns: 80,
          rows: 24,
          openWith: async (options) => {
            const session = await openSession(options);

            const prompt = session.prompt.bind(session);

            session.prompt = (...args) => {
              firstSent.add(session.id);

              return prompt(...args);
            };

            opened.push(session);

            return session;
          },
        },
      );
    } finally {
      await server.close();
    }
  });
});

describe('CHD-476 U1 tester: team ownership across fresh sessions', () => {
  test('main clears its lead without closing members, and the fresh lead clears only its own member', async () => {
    const server = serveChord();
    const admit = server.admit.bind(server);
    const callers: Caller[] = [];
    const opened: Session[] = [];
    const sent: { id: string; text: string }[] = [];

    server.admit = (caller) => {
      callers.push(caller);

      return admit(caller);
    };

    try {
      await withWindow(
        async (window) => {
          await ready(window);

          const main = callers[0]!;
          const run = await main.window.runTeam(main, {
            team: 'bugfix',
            job: 'text',
          });

          assert(!('error' in run));
          await until('lead admitted', () =>
            callers.some((caller) => caller.agent === run.id),
          );

          const lead = callers.find((caller) => caller.agent === run.id)!;

          await until(
            'lead first job went',
            () => opened.length === 2 && sent.length === 1,
          );

          const member = await lead.window.openMember(lead, {
            member: 'tester',
            prompt: 'text',
          });

          assert('id' in member, JSON.stringify(member));
          await until(
            'member first job went',
            () => opened.length === 3 && sent.length === 2,
          );

          const before = main.window
            .sessions()[0]!
            .children.map((child) => ({ ...child }));
          const memberSession = opened[2]!;

          expect(await main.window.clear(main, member.id)).toHaveProperty(
            'error',
          );
          expect(await lead.window.clear(lead, 'main')).toHaveProperty('error');
          expect(await main.window.clear(main, run.id)).toMatchObject({
            cleared: run.name,
            id: run.id,
          });

          const freshLeadSession = opened.at(-1)!;
          const freshLead = callers.findLast(
            (caller) => caller.agent === run.id,
          )!;

          expect(freshLead).not.toBe(lead);
          expect(freshLead.team).toBe('lead');
          expect(
            sent.filter((prompt) => prompt.id === freshLeadSession.id),
          ).toStrictEqual([]);
          expect(main.window.sessions()[0]!.children).toMatchObject(before);

          for (const pid of memberSession.agentPids) {
            expect(await isAlive(pid)).toBe(true);
          }

          expect(
            freshLead.window.tell(freshLead, member.id, 'teampartof', () => {}),
          ).not.toHaveProperty('error');
          expect(
            await freshLead.window.clear(freshLead, member.id),
          ).toMatchObject({ cleared: 'tester', id: member.id });

          const freshMember = callers.findLast(
            (caller) => caller.agent === member.id,
          )!;
          const freshMemberSession = opened.at(-1)!;

          expect(freshMember.team).toBe('member');
          expect(
            sent.filter((prompt) => prompt.id === freshMemberSession.id),
          ).toStrictEqual([]);
          expect(
            freshLead.window.tell(freshLead, member.id, 'teampartof', () => {}),
          ).not.toHaveProperty('error');
          await until('fresh member received first role prompt', () =>
            sent.some((prompt) => prompt.id === freshMemberSession.id),
          );

          const first = sent.find(
            (prompt) => prompt.id === freshMemberSession.id,
          )!.text;

          expect(first).toContain(
            '<team name="bugfix" role="member" member="tester">',
          );
          expect(first).toContain('Write the smallest test');
          expect(first).toContain('teampartof');
          expect(
            main.window.tell(main, run.id, 'teampartof', () => {}),
          ).not.toHaveProperty('error');
          await until('fresh lead received first role prompt', () =>
            sent.some((prompt) => prompt.id === freshLeadSession.id),
          );
          expect(
            sent.find((prompt) => prompt.id === freshLeadSession.id)!.text,
          ).toContain('<team name="bugfix" role="lead">');
          expect(
            sent.find((prompt) => prompt.id === freshLeadSession.id)!.text,
          ).toContain('tester');
        },
        {
          server,
          teams: { bugfix: BUGFIX },
          runtimes: ['fake'],
          columns: 120,
          rows: 40,
          openWith: async (options) => {
            const session = await openSession(options);
            const prompt = session.prompt.bind(session);

            session.prompt = (...args) => {
              sent.push({ id: session.id, text: args[0] });

              return prompt(...args);
            };

            opened.push(session);

            return session;
          },
        },
      );
    } finally {
      await server.close();
    }
  });
});

describe('CHD-476 U2 tester: restored bitmap and link ownership', () => {
  for (const columns of [80, 120]) {
    for (const method of ['person', 'parent'] as const) {
      test(`${method} clear restores the child payload once and preserves unrelated drafts at ${columns} columns`, async () => {
        const server = serveChord();
        const admit = server.admit.bind(server);
        const callers: Caller[] = [];
        const prompts: { id: string; args: Parameters<Session['prompt']> }[] =
          [];
        let all: WindowedState | undefined;
        const text = 'see [Image #1] @a.ts done';

        server.admit = (caller) => {
          callers.push(caller);

          return admit(caller);
        };

        try {
          await withWindow(
            async (window) => {
              await ready(window);
              await writeFile(join(window.dir, 'a.ts'), '');
              await send(window, 'agentcost');
              await window.shows('Open(parser)');
              await pick(window, 'parser');
              await window.shows('Working until stopped.');

              const target = all!.front;
              const originalId = all!.sessions[target]!.sessionId;
              const main = callers.find((caller) => caller.role === 'person')!;

              for (const key of 'see /shots/a.png @a.ts done') {
                await window.press(key);
              }

              await window.press('\r');
              await until(
                'child image and link queued',
                () =>
                  all?.sessions[target]?.queue.some(
                    (row) => row.text === text,
                  ) === true,
              );
              expect(prompts.some(({ args }) => args[0].includes(text))).toBe(
                false,
              );

              if (method === 'person') {
                await send(window, '/clear');
              } else {
                await window.type('child draft');
                await window.press(DOWN);
                await window.press(DOWN);
                await until('main selected', async () => {
                  if (window.frame().includes('  ❯ main ')) {
                    return true;
                  }

                  await window.press(UP);

                  return false;
                });

                await window.press('\r');
                await until(
                  'main in view',
                  () => !/╭─ \S/.test(window.frame()),
                );
                await window.type('main draft stays');

                expect(await main.window.clear(main, 'parser')).toHaveProperty(
                  'cleared',
                );
                expect(all!.sessions[all!.front]!.draft).toBe(
                  'main draft stays',
                );
                expect(all!.sessions[all!.front]!.images).toStrictEqual([]);
                await pick(window, 'parser');
              }

              const restored = text;

              if (method === 'parent') {
                expect(
                  all!.sessions[target]!.kept?.map((draft) => draft.text),
                ).toContain('child draft');
              }

              await until(
                'fresh child owns the restored payload',
                () =>
                  all?.sessions[target]?.sessionId !== originalId &&
                  all?.sessions[target]?.sessionId !== undefined,
              );
              expect(all!.sessions[target]!.draft).toBe(restored);
              expect(
                all!.sessions[target]!.images.map((image) => image.data),
              ).toStrictEqual([PIXEL_PNG]);
              expect(all!.sessions[target]!.queue).toStrictEqual([]);
              await window.press('\r');
              await window.shows(RECEIVED);
              await window.shows('Received a link: a.ts');

              const delivered = prompts.filter(({ args }) =>
                args[0].includes(text),
              );

              expect(delivered).toHaveLength(1);
              expect(delivered[0]!.id).not.toBe(originalId);
              expect(delivered[0]!.args.slice(1, 3)).toStrictEqual([
                [{ mediaType: 'image/png', data: PIXEL_PNG }],
                ['a.ts'],
              ]);
              expect(all!.sessions[target]!.images).toStrictEqual([]);
            },
            {
              server,
              runtimes: ['fake'],
              columns,
              rows: columns === 80 ? 24 : 40,
              onState: (state) => {
                all = state;
              },
              readImage: () =>
                Promise.resolve({
                  mediaType: 'image/png',
                  data: PIXEL_PNG,
                  bytes: PIXEL_BYTES.length,
                }),
              openWith: async (options) => {
                const session = await openSession(options);
                const prompt = session.prompt.bind(session);

                session.prompt = (...args) => {
                  prompts.push({ id: session.id, args });

                  return prompt(...args);
                };

                return session;
              },
            },
          );
        } finally {
          await server.close();
        }
      });
    }
  }
});
