import { describe, expect, test } from 'bun:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { useReducer } from 'react';
import { serveChord } from '../../../src/server/server.ts';
import { openSession, type Session } from '../../../src/session/session.ts';
import { earlierWindows } from '../../../src/session/windows.ts';
import { readPast } from '../../../src/session/record.ts';
import { earlierSessions, readRecords } from '../../../src/session/sessions.ts';
import { useSessions } from '../../../src/ui/app/sessions.ts';
import {
  frontState,
  initialAppState,
  reduceWindowed,
  windowed,
  type WindowedState,
} from '../../../src/ui/app/state.ts';
import { sum, windowSpend } from '../../../src/ui/transcript/spend.ts';
import { fakeAgentCommand } from '../../fixtures/fake.ts';
import { draw } from '../harness.tsx';
import { isAlive, until } from './render.tsx';

describe('CHD-373 S3b tester: session close wiring', () => {
  type Drive = ReturnType<typeof useSessions>;
  interface Seen {
    all: WindowedState;
    drive: Drive;
    dir: string;
  }

  async function withSessions(
    body: (read: () => Seen, releaseCloses: () => void) => Promise<void>,
    holdCloses = false,
    {
      agent = 'fake',
      flags = [] as string[],
      resumedCosts = new Map<string, number>(),
    } = {},
  ) {
    const dir = await mkdtemp(join(tmpdir(), 'chord-spend-close-'));
    const closes = Promise.withResolvers<void>();

    if (!holdCloses) {
      closes.resolve();
    }

    const opened: Session[] = [];
    const pids = new Set<number>();
    const server = serveChord();
    const command = fakeAgentCommand(undefined, ...flags);
    let seen: Seen | undefined;
    const read = () => {
      assert(seen);

      return seen;
    };

    function Host() {
      const [all, dispatch] = useReducer(
        reduceWindowed,
        windowed(initialAppState, 1),
      );
      const [, redraw] = useReducer((n: number) => n + 1, 0);
      const drive = useSessions(
        {
          agent,
          agentCommand: command,
          place: {
            cwd: dir,
            startupOf: (runtime) =>
              [agent, 'fake'].includes(runtime)
                ? { agentCommand: command }
                : undefined,
            mcpServers: [],
            mcpIgnored: [],
          },
          stateDir: join(dir, 'state'),
          readRecords,
          open: async (options) => {
            const from =
              options.resume && resumedCosts.get(options.resume.sessionId);
            const session = await openSession({
              ...options,
              ...(from === undefined
                ? {}
                : {
                    agentCommand: fakeAgentCommand(
                      undefined,
                      ...flags,
                      '--resume-only',
                      '--cost-from',
                      String(from),
                    ),
                  }),
            });

            const close = session.close.bind(session);

            session.close = async () => {
              await close();
              await closes.promise;
            };

            opened.push(session);

            for (const pid of session.agentPids) {
              pids.add(pid);
            }

            return session;
          },
          resume: undefined,
          resumes: undefined,
          resumedFront: undefined,
          resumedNote: undefined,
          server,
          runtimes: [...new Set([agent, 'fake'])],
          home: undefined,
          configHome: undefined,
          onQuit: undefined,
        },
        {
          all,
          state: frontState(all),
          dispatch,
          redraw,
          showDraft: () => {},
          notify: () => {},
          remember: () => {},
          stopCommand: () => {},
        },
      );

      seen = { all, drive, dir };

      return <text>Session accounting host</text>;
    }

    const drawn = await draw(<Host />);

    try {
      await until(
        'main ready',
        () => read().all.sessions[1]?.connection.status === 'ready',
      );
      await body(read, closes.resolve);
    } finally {
      closes.resolve();
      await read().drive.sessions.closeAll();
      await drawn.unmount();

      for (const session of opened) {
        await session.close();
        await session.exited;
        expect(session.agentPids.size).toBe(0);
      }

      for (const pid of pids) {
        expect(await isAlive(pid), `fake ${pid} survived close`).toBe(false);
      }

      await server.close();
      await rm(dir, { recursive: true });
    }
  }

  const costStarted = async (read: () => Seen, key: number) => {
    const conversation = read().drive.sessions.conversationOf(key);

    assert(conversation);
    conversation.send('costwait');
    await until(
      'costwait usage before cancellation',
      () => read().all.sessions[key]?.transcript.usage?.cost?.amount === 0.01,
    );
  };

  test('two busy tabs close concurrently and keep their final costs separately, once each', () =>
    withSessions(async (read, releaseCloses) => {
      await costStarted(read, 1);
      read().drive.openBeside();
      await until(
        'second ready',
        () => read().all.sessions[2]?.connection.status === 'ready',
      );
      await costStarted(read, 2);
      read().drive.openBeside();
      await until(
        'surviving tab ready',
        () => read().all.sessions[3]?.connection.status === 'ready',
      );

      for (const key of [1, 2]) {
        read().drive.sessions.pick(key);
        read().drive.showFront();
        await until('tab shown', () => read().all.front === key);
        read().drive.closeFront();
        await until(
          'busy close armed',
          () => read().all.window.closeArmed === key,
        );
        read().drive.closeFront();
        await until(
          'closed tab removed',
          () => read().all.sessions[key] === undefined,
        );
      }

      expect(Object.keys(read().all.closing ?? {})).toHaveLength(2);
      releaseCloses();
      await until(
        'both costs settled',
        () => read().all.window.keptSpend?.length === 2,
      );

      const { all, drive } = read();
      const kept = all.window.keptSpend!;

      expect(kept.map((part) => part.sessionId).filter(Boolean)).toHaveLength(
        2,
      );
      expect(new Set(kept.map((part) => part.sessionId)).size).toBe(2);
      expect(kept.map((part) => part.part.figure?.cost?.amount)).toEqual([
        0.01, 0.01,
      ]);
      expect(all.closing).toEqual({});
      expect(
        sum(windowSpend(drive.sessions.tabs.tabs, all.sessions, kept)),
      ).toMatchObject({ cost: 0.02 });
    }, true));

  test('a busy child keeps its final cost after close, independently of its parent', () =>
    withSessions(async (read) => {
      read().drive.conversation()!.send('agentcost');
      await until(
        'parser exists',
        () => read().drive.sessions.tabs.tabs[0]?.children.length === 1,
      );

      const child = read().drive.sessions.tabs.tabs[0]!.children[0]!;

      await until(
        'child cost before cancellation',
        () =>
          read().all.sessions[child.key]?.transcript.usage?.cost?.amount ===
          0.01,
      );
      read().drive.sessions.pick(child.key);
      read().drive.showFront();
      await until('child shown', () => read().all.front === child.key);
      read().drive.closePicked();
      await until(
        'child close armed',
        () => read().all.window.agentCloseArmed === child.key,
      );
      read().drive.closePicked();
      await until(
        'child final cost retained',
        () =>
          read().all.window.keptSpend?.some(
            (part) => part.part.name === 'parser',
          ) === true,
      );

      const { all, drive } = read();
      const kept = all.window.keptSpend!;

      expect(kept).toHaveLength(1);
      expect(kept[0]).toMatchObject({
        tab: 1,
        sessionId: child.conversation.session?.id,
        part: {
          name: 'parser',
          kind: 'agent',
          ended: true,
          figure: { cost: { amount: 0.01, currency: 'USD' } },
        },
      });
      expect(all.sessions[child.key]).toBeUndefined();
      expect(drive.sessions.tabs.tabs[0]?.children).toHaveLength(0);
      expect(all.closing).toEqual({});
    }));

  test('restoring a closed session into an unused tab replaces that tab and counts the session only once', () =>
    withSessions(async (read) => {
      await costStarted(read, 1);

      const sessionId = read().all.sessions[1]!.sessionId!;

      read().drive.openBeside();
      await until(
        'unused tab ready',
        () => read().all.sessions[2]?.connection.status === 'ready',
      );
      read().drive.sessions.pick(1);
      read().drive.showFront();
      await until('busy tab shown', () => read().all.front === 1);
      read().drive.closeFront();
      await until('close armed', () => read().all.window.closeArmed === 1);
      read().drive.closeFront();
      await until(
        'old spend settled',
        () => read().all.window.keptSpend?.length === 1,
      );

      const { dir } = read();
      const records = await readRecords(join(dir, 'state'));
      const window = earlierWindows(
        [
          {
            id: 'w-qa',
            at: 1,
            tabs: [{ sessionId, agent: 'fake', cwd: dir }],
            front: 0,
          },
        ],
        records,
      )[0];

      assert(window);
      read().drive.pickResume({ kind: 'window', window }, 80);
      await until('restored session ready', () =>
        Object.values(read().all.sessions).some(
          (session) =>
            session.sessionId === sessionId &&
            session.connection.status === 'ready',
        ),
      );
      await until(
        'unused tab close settled',
        () => read().all.window.keptSpend?.length === 2,
      );

      let { all, drive } = read();
      const figure = () =>
        sum(
          windowSpend(
            read().drive.sessions.tabs.tabs,
            read().all.sessions,
            read().all.window.keptSpend ?? [],
          ),
        );

      expect(all.sessions[2]).toBeUndefined();
      expect(drive.sessions.tabs.tabs).toHaveLength(1);
      expect(figure()).toMatchObject({ cost: 0.01 });

      const key = drive.sessions.tabs.tabs[0]!.key;

      drive.pickResume({ kind: 'window', window }, 80);
      await until('same restored tab selected', () => read().all.front === key);

      ({ all, drive } = read());

      expect(drive.sessions.tabs.tabs).toHaveLength(1);
      expect(all.window.keptSpend).toHaveLength(2);
      expect(figure()).toMatchObject({ cost: 0.01 });
    }));

  describe('CHD-373 S3c tester: retirement through the window session hook', () => {
    const settled = (read: () => Seen, count: number) =>
      until(
        'retirements settled',
        () =>
          read().all.window.keptSpend?.length === count &&
          Object.keys(read().all.closing ?? {}).length === 0,
      );
    const figure = (read: () => Seen) =>
      sum(
        windowSpend(
          read().drive.sessions.tabs.tabs,
          read().all.sessions,
          read().all.window.keptSpend ?? [],
        ),
      );
    const costLate = async (read: () => Seen) => {
      read().drive.conversation()!.send('costwaitlate');
      await until(
        'running old session cost',
        () => read().all.sessions[1]?.transcript.usage?.cost?.amount === 0.01,
      );
    };

    const replacement = async (read: () => Seen, old: string) => {
      await until(
        'replacement session ready',
        () =>
          read().all.sessions[1]?.sessionId !== old &&
          read().all.sessions[1]?.connection.status === 'ready',
      );
    };

    test('two successive clears retain both late final costs while replacement work stays independent', () =>
      withSessions(async (read) => {
        const oldIds: string[] = [];

        for (let n = 0; n < 2; n++) {
          await costLate(read);

          const old = read().all.sessions[1]!.sessionId!;

          oldIds.push(old);
          read().drive.clearFront(() => {});

          await replacement(read, old);
        }

        read().drive.conversation()!.send('text');
        await until(
          'replacement turn cost',
          () =>
            Object.keys(read().all.sessions[1]?.spent?.costs ?? {}).length ===
            1,
        );
        await settled(read, 2);

        const { all, dir } = read();
        const kept = all.window.keptSpend!;

        expect(kept.map((part) => part.sessionId).sort()).toEqual(
          oldIds.toSorted(),
        );
        expect(kept.map((part) => part.part.figure?.cost?.amount)).toEqual([
          0.02, 0.02,
        ]);
        expect(figure(read).cost).toBeCloseTo(0.0525, 9);
        expect(
          JSON.stringify(all.sessions[1]?.transcript.entries),
        ).not.toContain('Working until stopped.');

        const records = await readRecords(join(dir, 'state'));

        for (const id of oldIds) {
          const record = records.find((each) => each.sessionId === id);

          assert(record);

          const entries = await readPast(record.path);
          const last = entries.findLast((entry) => entry.type === 'usage');

          expect(last).toMatchObject({ cost: { amount: 0.02 } });
          expect(
            entries
              .filter(
                (entry) =>
                  entry.type === 'update' &&
                  entry.update.sessionUpdate === 'usage_update',
              )
              .at(-1),
          ).toMatchObject({
            update: { cost: { amount: 0.02 } },
          });
        }
      }));

    test('a later clear preserves each earlier settled retirement in the whole-window total', () =>
      withSessions(async (read) => {
        for (const count of [1, 2]) {
          await costLate(read);

          const old = read().all.sessions[1]!.sessionId!;

          read().drive.clearFront(() => {});

          await replacement(read, old);
          await until(
            'this retirement finished',
            () => Object.keys(read().all.closing ?? {}).length === 0,
          );
          expect(read().all.window.keptSpend).toHaveLength(count);
          expect(figure(read).cost).toBeCloseTo(count * 0.02, 9);
        }
      }));

    test('repeated resume in place counts from the retired raw baseline without duplicating earlier lives', () => {
      const resumedCosts = new Map<string, number>();

      return withSessions(
        async (read) => {
          await costLate(read);

          const original = read().all.sessions[1]!.sessionId!;

          read().drive.clearFront(() => {});

          await replacement(read, original);
          await settled(read, 1);
          await costLate(read);

          const second = read().all.sessions[1]!.sessionId!;
          const records = await readRecords(join(read().dir, 'state'));
          const session = earlierSessions(records, {
            agent: 'kilo',
            cwd: read().dir,
          }).find((each) => each.resume.sessionId === original);

          assert(session);
          read().drive.conversation()!.interrupt();
          await until(
            'resume permitted after interrupt',
            () => read().all.sessions[1]?.transcript.turn.status === 'idle',
          );
          resumedCosts.set(original, 0.02);
          read().drive.pickResume({ kind: 'session', session }, 80);
          await replacement(read, second);
          await settled(read, 2);
          expect(read().all.sessions[1]?.sessionId).toBe(original);

          for (const [before, after] of [
            [0.02, 0.0325],
            [0.0325, 0.045],
          ] as const) {
            expect(figure(read).cost).toBeCloseTo(before + 0.02, 9);
            read().drive.conversation()!.send('text');
            await until(
              'resumed increment',
              () => Math.abs((figure(read).cost ?? 0) - (after + 0.02)) < 1e-9,
            );

            if (after === 0.0325) {
              read().drive.clearFront(() => {});

              await replacement(read, original);
              await settled(read, 3);

              const entries = await readRecords(join(read().dir, 'state'));
              const latest = earlierSessions(entries, {
                agent: 'kilo',
                cwd: read().dir,
              }).find((each) => each.resume.sessionId === original);

              assert(latest);
              resumedCosts.set(original, after);

              const empty = read().all.sessions[1]!.sessionId!;

              read().drive.pickResume({ kind: 'session', session: latest }, 80);
              await replacement(read, empty);
              await settled(read, 4);
            }
          }

          expect(figure(read).cost).toBeCloseTo(0.065, 9);
        },
        false,
        { agent: 'kilo', resumedCosts },
      );
    });

    for (const increment of [0, 0.005]) {
      test(`clear on the first cycle update retains its eventual ${increment} increment`, () =>
        withSessions(
          async (read) => {
            let cleared = false;
            const session = read().drive.conversation()!.session!;
            const old = session.id;
            const off = session.subscribe((update) => {
              if (
                update.sessionUpdate === 'agent_message_chunk' &&
                update.content.type === 'text' &&
                update.content.text ===
                  'The background build ended; reading its log.'
              ) {
                // The wire update already reached Conversation; clear before its next update.
                queueMicrotask(() => {
                  read().drive.clearFront(() => {});

                  cleared = true;
                });
              }
            });

            try {
              read().drive.conversation()!.send('claudecycle');
              await until('clear triggered by cycle update', () => cleared);
              await replacement(read, old);
              await settled(read, 1);

              const kept = read().all.window.keptSpend![0]!;

              expect(kept.part.figure?.cost?.amount).toBeCloseTo(
                0.0125 + increment,
                9,
              );
              expect(read().all.sessions[1]?.spent).toBeUndefined();

              const records = await readRecords(join(read().dir, 'state'));
              const record = records.find((each) => each.sessionId === old);

              assert(record);

              const entries = await readPast(record.path);
              const costs = new Map(
                entries.flatMap((entry) =>
                  entry.type === 'usage'
                    ? [[entry.turnId, entry.cost?.amount] as const]
                    : [],
                ),
              );

              expect([...costs.values()]).toEqual([
                expect.closeTo(0.0125, 9),
                expect.closeTo(increment, 9),
              ]);
            } finally {
              off();
            }
          },
          false,
          {
            agent: 'claude',
            flags: ['--adapter', 'claude', '--cycle-cost', String(increment)],
          },
        ));
    }

    test('a real spawned task ends into its retired record once even after the replacement tab closes', () =>
      withSessions(async (read) => {
        read().drive.openBeside();
        await until(
          'surviving tab ready',
          () => read().all.sessions[2]?.connection.status === 'ready',
        );
        read().drive.sessions.pick(1);
        read().drive.showFront();
        await until('main shown', () => read().all.front === 1);

        const old = read().all.sessions[1]!.sessionId!;

        read().drive.conversation()!.send('taskcost');
        await until('task has persisted its running cost', async () => {
          const records = await readRecords(join(read().dir, 'state'));
          const task = records.find((each) => each.name === 'Count the cost');

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

        await until(
          'parent turn ended',
          () => read().all.sessions[1]?.transcript.turn.status === 'idle',
        );
        read().drive.clearFront(() => {});

        await replacement(read, old);
        read().drive.closeFront();
        await until(
          'replacement tab closed',
          () => read().all.sessions[1] === undefined,
        );
        await settled(read, 2);

        const kept = read().all.window.keptSpend!.find(
          (part) => part.sessionId === old,
        );

        assert(kept);
        expect(kept.part.parts).toHaveLength(1);
        expect(kept.part.parts![0]).toMatchObject({
          name: 'Count the cost',
          figure: { cost: { amount: 0.01 } },
        });
        expect(figure(read).cost).toBeCloseTo(0.0225, 9);
        expect(read().all.sessions[2]?.spent).toBeUndefined();
        expect(
          JSON.stringify(read().all.sessions[2]?.transcript.entries),
        ).not.toContain('Count the cost');

        const records = await readRecords(join(read().dir, 'state'));
        const parent = records.find((each) => each.sessionId === old);

        assert(parent);

        const entries = await readPast(parent.path);
        const ends = entries.filter(
          (entry) =>
            entry.type === 'update' &&
            entry.update.sessionUpdate === 'subagent_update' &&
            entry.update._meta?.['chord/spent'] !== undefined,
        );

        expect(ends).toHaveLength(1);
      }));
  });
});

describe('CHD-373 S3c: a session /clear let go, its tab closed before it ends', () => {
  test("its turn's end, its last cost with it, is kept where it was let go, and nothing of it reaches the tab's next session", async () => {
    const dir = await mkdtemp(join(tmpdir(), 'chord-spend-retire-'));
    const server = serveChord();
    const command = fakeAgentCommand();
    const opened: Session[] = [];
    let seen:
      { all: WindowedState; drive: ReturnType<typeof useSessions> } | undefined;
    const read = () => {
      assert(seen);

      return seen;
    };

    function Host() {
      const [all, dispatch] = useReducer(
        reduceWindowed,
        windowed(initialAppState, 1),
      );
      const [, redraw] = useReducer((n: number) => n + 1, 0);
      const drive = useSessions(
        {
          agent: 'fake',
          place: {
            cwd: dir,
            startupOf: (agent) =>
              agent === 'fake' ? { agentCommand: command } : undefined,
            mcpServers: [],
            mcpIgnored: [],
          },
          stateDir: join(dir, 'state'),
          readRecords,
          open: async (options) => {
            const session = await openSession(options);

            opened.push(session);

            return session;
          },
          resume: undefined,
          resumes: undefined,
          resumedFront: undefined,
          resumedNote: undefined,
          server,
          runtimes: ['fake'],
          home: undefined,
          configHome: undefined,
          onQuit: undefined,
        },
        {
          all,
          state: frontState(all),
          dispatch,
          redraw,
          showDraft: () => {},
          notify: () => {},
          remember: () => {},
          stopCommand: () => {},
        },
      );

      seen = { all, drive };

      return <text>Session retirement host</text>;
    }

    const drawn = await draw(<Host />);

    try {
      await until(
        'main ready',
        () => read().all.sessions[1]?.connection.status === 'ready',
      );
      // A second tab, so closing the first leaves the window open.
      read().drive.openBeside();
      await until(
        'second ready',
        () => read().all.sessions[2]?.connection.status === 'ready',
      );
      read().drive.sessions.pick(1);
      read().drive.showFront();
      await until('first in front', () => read().all.front === 1);

      const conversation = read().drive.sessions.conversationOf(1);

      assert(conversation);
      conversation.send('costwaitlate');
      await until(
        'its cost so far',
        () => read().all.sessions[1]?.transcript.usage?.cost?.amount === 0.01,
      );

      // Let go, and its tab gone at once, before the old turn has ended:
      // what that turn says comes through the closed tab's events.
      read().drive.clearFront(() => {});

      const closed = read().drive.sessions.close(1);

      await until(
        'the let-go session kept',
        () =>
          read().all.window.keptSpend?.length === 1 &&
          Object.keys(read().all.closing ?? {}).length === 0,
      );
      await closed;

      const [kept] = read().all.window.keptSpend!;

      // Its turn to its end, the late cost included, under its tab.
      expect(kept).toMatchObject({
        tab: 1,
        part: { name: 'main', figure: { cost: { amount: 0.02 } } },
      });
      // Nothing of it reached the session the tab went on with.
      expect(read().all.sessions[1]?.spent?.costs).toBe(undefined);
    } finally {
      await read().drive.sessions.closeAll();
      await drawn.unmount();

      for (const session of opened) {
        await session.close();
      }

      await server.close();
      await rm(dir, { recursive: true });
    }
  });
});
