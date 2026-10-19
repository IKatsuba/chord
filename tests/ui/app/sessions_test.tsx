import { describe, expect, test } from 'bun:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { useReducer } from 'react';
import { serveChord } from '../../../src/server/server.ts';
import { openSession, type Session } from '../../../src/session/session.ts';
import { earlierWindows } from '../../../src/session/windows.ts';
import { readRecords } from '../../../src/session/sessions.ts';
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
  ) {
    const dir = await mkdtemp(join(tmpdir(), 'chord-spend-close-'));
    const closes = Promise.withResolvers<void>();

    if (!holdCloses) {
      closes.resolve();
    }

    const opened: Session[] = [];
    const pids = new Set<number>();
    const server = serveChord();
    const command = fakeAgentCommand();
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
          agent: 'fake',
          agentCommand: command,
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
          agentCommand: command,
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
