import { describe, expect, test } from 'bun:test';
import assert from 'node:assert/strict';
import { mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { useReducer } from 'react';
import { serveChord } from '../../../src/server/server.ts';
import { openSession, type Session } from '../../../src/session/session.ts';
import { readPast } from '../../../src/session/record.ts';
import { earlierSessions, readRecords } from '../../../src/session/sessions.ts';
import { useSessions } from '../../../src/ui/app/sessions.ts';
import {
  frontState,
  initialAppState,
  reduceWindowed,
  windowed,
  type WindowedAction,
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
    openChild(): Promise<unknown>;
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
    const admit = server.admit.bind(server);
    let main: Parameters<typeof admit>[0] | undefined;

    server.admit = (caller) => {
      if (caller.role === 'person') {
        main = caller;
      }

      return admit(caller);
    };

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

      seen = {
        all,
        drive,
        dir,
        openChild: () => {
          assert(main);

          return main.window.open(main.key, {
            agent: 'fake',
            name: 'other',
            prompt: 'costwait',
          });
        },
      };

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

  test('busy main and child close concurrently and keep their final costs once each', () =>
    withSessions(async (read, releaseCloses) => {
      await read().openChild();
      await until(
        'the busy child exists',
        () => read().drive.sessions.agents.children.length === 1,
      );

      const child = read().drive.sessions.agents.children[0]!;

      await until(
        'child cost before closing',
        () =>
          read().all.sessions[child.key]?.transcript.usage?.cost?.amount ===
          0.01,
      );
      await costStarted(read, 1);

      const mainId = read().all.sessions[1]!.sessionId!;

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
        'child removed while closing',
        () => read().all.sessions[child.key] === undefined,
      );
      read().drive.clearFront(() => {});

      await until(
        'main replaced while both closes are held',
        () =>
          read().all.sessions[1]?.sessionId !== mainId &&
          read().all.sessions[1]?.connection.status === 'ready',
      );
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
        sum(windowSpend(drive.sessions.agents, all.sessions, kept)),
      ).toMatchObject({ cost: 0.02 });
    }, true));

  test('a busy child keeps its final cost after close, independently of its parent', () =>
    withSessions(async (read) => {
      read().drive.conversation()!.send('agentcost');
      await until(
        'parser exists',
        () => read().drive.sessions.agents.children.length === 1,
      );

      const child = read().drive.sessions.agents.children[0]!;

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
        sessionId: child.conversation.session?.id,
        part: {
          name: 'parser',
          kind: 'agent',
          ended: true,
          figure: { cost: { amount: 0.01, currency: 'USD' } },
        },
      });
      expect(all.sessions[child.key]).toBeUndefined();
      expect(drive.sessions.agents.children).toHaveLength(0);
      expect(all.closing).toEqual({});
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
          read().drive.sessions.agents,
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
          read().drive.pickResume(session);
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

              read().drive.pickResume(latest);
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

    test('a real spawned task ends into its retired record once even after quit closes its replacement', () =>
      withSessions(async (read) => {
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
        await settled(read, 1);
        read().drive.quit();
        await until(
          'quit closed the replacement',
          () => read().drive.sessions.agents.main === undefined,
        );
        await until('retired task end persisted after quit', async () => {
          const records = await readRecords(join(read().dir, 'state'));
          const parent = records.find((each) => each.sessionId === old);

          return (
            parent !== undefined &&
            (await readPast(parent.path)).some(
              (entry) =>
                entry.type === 'update' &&
                entry.update.sessionUpdate === 'subagent_update' &&
                entry.update._meta?.['chord/spent'] !== undefined,
            )
          );
        });

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
        expect(read().all.sessions[1]?.spent).toBeUndefined();
        expect(
          JSON.stringify(read().all.sessions[1]?.transcript.entries ?? []),
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

describe('CHD-373 S3c: a session /clear let go before its turn ends', () => {
  test("its turn's end, its last cost with it, is kept where it was let go, and nothing of it reaches the next session", async () => {
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

      const conversation = read().drive.sessions.conversationOf(1);

      assert(conversation);
      conversation.send('costwaitlate');
      await until(
        'its cost so far',
        () => read().all.sessions[1]?.transcript.usage?.cost?.amount === 0.01,
      );

      // Let go before the old turn has ended: what that turn says comes
      // through the let-go session's own events.
      read().drive.clearFront(() => {});

      await until(
        'the let-go session kept',
        () =>
          read().all.window.keptSpend?.length === 1 &&
          Object.keys(read().all.closing ?? {}).length === 0,
      );

      const [kept] = read().all.window.keptSpend!;

      // Its turn to its end, the late cost included.
      expect(kept).toMatchObject({
        part: { name: 'main', figure: { cost: { amount: 0.02 } } },
      });
      // Nothing of it reached the session the window went on with.
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

describe("CHD-434: dimcode's notice comes due from any session of the window", () => {
  type Admitted = Parameters<ReturnType<typeof serveChord>['admit']>[0];
  interface Seen {
    all: WindowedState;
    drive: ReturnType<typeof useSessions>;
    dispatch: (action: WindowedAction) => void;
  }

  /**
   * The window's sessions on the fake, `main` on `agent`, `dimcode` on the
   * fake starting at `permission`, `read-only` unless said, until a turn
   * moves it, chord's user directory
   * holding `record` as its notices file, or a directory in its place.
   */
  async function withNotices(
    body: (read: () => Seen, main: Admitted) => Promise<void>,
    {
      agent = 'fake',
      record,
      permission = 'read-only',
    }: {
      agent?: string;
      record?: string | 'directory' | 'blocked';
      permission?: string;
    } = {},
  ) {
    const dir = await mkdtemp(join(tmpdir(), 'chord-notice-'));
    const configHome = join(dir, 'config');
    const file = join(configHome, 'chord', 'notices.json');
    const server = serveChord();
    const admit = server.admit.bind(server);
    let main: Admitted | undefined;
    const fake = fakeAgentCommand();
    const dimcode = fakeAgentCommand(
      undefined,
      '--dimcode-permission',
      permission,
    );
    const opened: Session[] = [];
    let seen: Seen | undefined;
    const read = () => {
      assert(seen);

      return seen;
    };

    server.admit = (caller) => {
      if (caller.role === 'person') {
        main = caller;
      }

      return admit(caller);
    };

    if (record === 'directory') {
      await mkdir(file, { recursive: true });
    } else if (record === 'blocked') {
      // A file where chord's directory goes: nothing is written there.
      await mkdir(configHome, { recursive: true });
      await writeFile(join(configHome, 'chord'), '');
    } else if (record !== undefined) {
      await mkdir(join(configHome, 'chord'), { recursive: true });
      await writeFile(file, record);
    }

    function Host() {
      const [all, dispatch] = useReducer(
        reduceWindowed,
        windowed(initialAppState, 1),
      );
      const [, redraw] = useReducer((n: number) => n + 1, 0);
      const drive = useSessions(
        {
          agent,
          place: {
            cwd: dir,
            startupOf: (runtime) =>
              runtime === 'dimcode'
                ? { agentCommand: dimcode }
                : runtime === 'fake'
                  ? { agentCommand: fake }
                  : undefined,
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
          server,
          runtimes: ['fake', 'dimcode'],
          home: undefined,
          configHome,
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

      seen = { all, drive, dispatch };

      return <text>Notice host</text>;
    }

    const drawn = await draw(<Host />);

    try {
      await until(
        'main ready',
        () => read().all.sessions[1]?.connection.status === 'ready',
      );
      assert(main);
      await body(read, main);
    } finally {
      await read().drive.sessions.closeAll();
      await drawn.unmount();

      for (const session of opened) {
        await session.close();
      }

      await server.close();
      await rm(dir, { recursive: true });
    }
  }

  const permissionOf = (read: () => Seen, key: number) =>
    read().all.sessions[key]?.options.find(
      (option) => option.id === 'permission',
    )?.current;

  /** A dimcode child opened beside `main`, not picked, at `read-only`. */
  const openDimcode = async (read: () => Seen, main: Admitted) => {
    const before = new Set(Object.keys(read().all.sessions));
    const answer = await main.window.open(main.key, {
      agent: 'dimcode',
      name: `Scout ${before.size}`,
      prompt: 'hello',
    });

    assert('id' in answer, JSON.stringify(answer));

    let key: number | undefined;

    await until('the child at read-only', () => {
      key = Object.keys(read().all.sessions)
        .map(Number)
        .find((each) => !before.has(String(each)));

      return key !== undefined && permissionOf(read, key) === 'read-only';
    });

    assert(key !== undefined);
    expect(read().drive.sessions.agents.picked).toBe(1);

    return key;
  };

  const fullAccess = async (read: () => Seen, key: number) => {
    read().drive.sessions.conversationOf(key)?.send('fullaccess');
    await until(
      'full-access heard',
      () => permissionOf(read, key) === 'full-access',
    );
  };

  /** A moment for a notice that is not due to have come anyway. */
  const settle = () => new Promise((resolve) => setTimeout(resolve, 200));

  test('an unpicked dimcode child leaving read-only opens it in the window; at read-only it stays shut', () =>
    withNotices(async (read, main) => {
      const child = await openDimcode(read, main);

      await settle();
      expect(read().all.window.notice).toBe(undefined);

      await fullAccess(read, child);
      await until(
        'the notice',
        () => read().all.window.notice === 'dimcode-agents',
      );
    }));

  test("a dimcode task's own option leaving read-only opens it", () =>
    withNotices(async (read, main) => {
      void main.window.spawn(main, {
        agent: 'dimcode',
        name: 'Probe',
        prompt: 'fullaccess',
      });
      await until(
        'the notice',
        () => read().all.window.notice === 'dimcode-agents',
      );
    }));

  test('after "show it again" for one session, another reaching that moment opens it again', () =>
    withNotices(async (read, main) => {
      const first = await openDimcode(read, main);
      const second = await openDimcode(read, main);

      await fullAccess(read, first);
      await until(
        'the first notice',
        () => read().all.window.notice === 'dimcode-agents',
      );
      read().dispatch({ type: 'notice_closed' });
      await settle();
      expect(read().all.window.notice).toBe(undefined);

      await fullAccess(read, second);
      await until(
        'the second notice',
        () => read().all.window.notice === 'dimcode-agents',
      );
    }));

  test('a record that does not read, a directory in its place, shows it rather than failing', () =>
    withNotices(
      async (read, main) => {
        await fullAccess(read, await openDimcode(read, main));
        await until(
          'the notice',
          () => read().all.window.notice === 'dimcode-agents',
        );
      },
      { record: 'directory' },
    ));

  test('once dismissed on this machine it never opens', () =>
    withNotices(
      async (read, main) => {
        await fullAccess(read, await openDimcode(read, main));
        await settle();
        expect(read().all.window.notice).toBe(undefined);
      },
      { record: JSON.stringify({ dismissed: ['dimcode-agents'] }) },
    ));

  test("a main session of dimcode's opens it as its children do", () =>
    withNotices(
      async (read) => {
        await until(
          'main at read-only',
          () => permissionOf(read, 1) === 'read-only',
        );
        await settle();
        expect(read().all.window.notice).toBe(undefined);

        await fullAccess(read, 1);
        await until(
          'the notice',
          () => read().all.window.notice === 'dimcode-agents',
        );
      },
      { agent: 'dimcode' },
    ));

  test('"show it again", then /clear to a session that starts at full-access too: that session opens it anew', () =>
    withNotices(
      async (read) => {
        await until(
          "the first session's notice",
          () => read().all.window.notice === 'dimcode-agents',
        );
        read().dispatch({ type: 'notice_closed' });

        const old = read().all.sessions[1]?.sessionId;

        read().drive.clearFront(() => {});

        await until(
          'the session after it, at full-access',
          () =>
            read().all.sessions[1]?.sessionId !== old &&
            permissionOf(read, 1) === 'full-access',
        );
        await until(
          'the notice anew',
          () => read().all.window.notice === 'dimcode-agents',
        );
      },
      { agent: 'dimcode', permission: 'full-access' },
    ));

  for (const blocked of [false, true]) {
    test(
      blocked
        ? 'a dismissal that cannot be written is given back: the next session at risk shows it'
        : '1 dismisses it for the window at once: a child coming due after shows nothing',
      () =>
        withNotices(
          async (read, main) => {
            await fullAccess(read, await openDimcode(read, main));
            await until(
              'the notice',
              () => read().all.window.notice === 'dimcode-agents',
            );
            read().drive.dismissNotice('dimcode-agents');
            read().dispatch({ type: 'notice_closed' });
            await fullAccess(read, await openDimcode(read, main));
            await settle();
            expect(read().all.window.notice).toBe(
              blocked ? 'dimcode-agents' : undefined,
            );
          },
          blocked ? { record: 'blocked' } : {},
        ),
    );
  }
});

describe('CHD-559 U4 tester: replay delivery and persisted events', () => {
  test('one window batch retains every notification and records replay and live events once', async () => {
    const dir = await mkdtemp(join(tmpdir(), 'chord-replay-delivery-'));
    const stateDir = join(dir, 'state');
    const actions: WindowedAction[] = [];
    const notified: string[] = [];
    const opened: Session[] = [];
    const past: ReturnType<Session['history']> = [
      { type: 'prompt', turnId: 'old', text: 'saved prompt', at: 1 },
      {
        type: 'update',
        turnId: 'old',
        update: {
          sessionUpdate: 'agent_message_chunk',
          content: { type: 'text', text: 'SAVED_REPLAY_MARKER' },
        },
      },
      {
        type: 'result',
        turnId: 'old',
        result: { status: 'completed', stopReason: 'end_turn' },
      },
    ];
    let seen:
      | {
          all: WindowedState;
          drive: ReturnType<typeof useSessions>;
        }
      | undefined;
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
            startupOf: () => ({ agentCommand: fakeAgentCommand() }),
            mcpServers: [],
            mcpIgnored: [],
          },
          stateDir,
          readRecords,
          open: async (options) => {
            const session = await openSession(options);

            session.history = () => past;

            opened.push(session);

            return session;
          },
          resume: undefined,
          server: undefined,
          runtimes: ['fake'],
          home: undefined,
          configHome: undefined,
          onQuit: undefined,
        },
        {
          all,
          state: frontState(all),
          dispatch: (action) => {
            actions.push(action);
            dispatch(action);
          },
          redraw,
          showDraft: () => {},
          notify: (_, name) => {
            notified.push(name);
          },
          remember: () => {},
          stopCommand: () => {},
        },
      );

      seen = { all, drive };

      return <text>Replay delivery fixture</text>;
    }

    const drawn = await draw(<Host />);

    try {
      await until(
        'replay connected',
        () => read().all.sessions[1]?.connection.status === 'ready',
      );

      const batches = actions.filter(
        (action) => action.type === 'in_session_past',
      );

      expect(batches).toHaveLength(1);
      expect(batches[0]).toMatchObject({ key: 1, actions: past });
      expect(notified).toHaveLength(
        actions.reduce(
          (count, action) =>
            count +
            (action.type === 'in_session'
              ? 1
              : action.type === 'in_session_past'
                ? action.actions.length
                : 0),
          0,
        ),
      );

      const conversation = read().drive.sessions.conversationOf(1);

      assert(conversation);
      conversation.send('text');
      await until('live reply completed', () =>
        actions.some(
          (action) =>
            action.type === 'in_session' && action.action.type === 'result',
        ),
      );
      expect(
        actions.filter((action) => action.type === 'in_session_past'),
      ).toHaveLength(1);
      await read().drive.sessions.closeAll();

      const records = await readRecords(stateDir);

      expect(records).toHaveLength(1);

      const entries = await readPast(records[0]!.path);

      expect(
        entries
          .filter((entry) => entry.type === 'prompt')
          .map((entry) => entry.prompt),
      ).toStrictEqual(['saved prompt', 'text']);
      expect(
        entries.filter(
          (entry) =>
            entry.type === 'update' &&
            entry.update.sessionUpdate === 'agent_message_chunk' &&
            entry.update.content.type === 'text' &&
            entry.update.content.text === 'SAVED_REPLAY_MARKER',
        ),
      ).toHaveLength(1);
    } finally {
      await read().drive.sessions.closeAll();
      await drawn.unmount();

      for (const session of opened) {
        await session.close();
        await session.exited;
        expect(session.agentPids.size).toBe(0);
      }

      await rm(dir, { recursive: true });
    }
  });
});
