import { expect, test } from 'bun:test';
import { resumeMessage } from '../../../src/session/sessions.ts';
import {
  emptyTranscript,
  type TurnState,
} from '../../../src/session/transcript/types.ts';
import {
  agentCloseArmedLine,
  type Busy,
  busyOf,
  closeArmedLine,
  ctrlCArmedLine,
  quitArmedLine,
  tabBusy,
  teamCloseArmedLine,
} from '../../../src/ui/app/closing.ts';
import {
  initialAppState,
  initialSession,
  reduceWindowed,
  windowed,
} from '../../../src/ui/app/state.ts';

const working: TurnState = { status: 'working', turnId: 't', since: 0 };

test('a session is busy while asked, queued or working, the person first', () => {
  const session = (turn: TurnState, queued = 0, asking = false) => ({
    transcript: {
      ...emptyTranscript,
      turn,
      ...(asking
        ? {
            asking: [{} as (typeof emptyTranscript.asking)[number]],
          }
        : {}),
    },
    queue: Array.from({ length: queued }, (_, i) => ({
      turnId: `q${i}`,
      text: `${i}`,
    })),
  });

  expect(busyOf(session({ status: 'idle' }))).toStrictEqual(undefined);
  expect(
    busyOf({
      transcript: {
        ...emptyTranscript,
        entries: [
          {
            kind: 'shell',
            turnId: 's',
            run: {
              command: 'sleep 60',
              stdout: '',
              stderr: '',
              running: true,
            },
          },
        ],
      },
      queue: [],
    }),
  ).toStrictEqual({ kind: 'working' });
  expect(busyOf(session(working))).toStrictEqual({ kind: 'working' });
  expect(busyOf(session(working, 2))).toStrictEqual({
    kind: 'queued',
    count: 2,
  });
  expect(busyOf(session(working, 2, true))).toStrictEqual({ kind: 'input' });
  expect(
    busyOf(
      session(
        { ...working, status: 'awaiting_permission', permissions: [] },
        2,
      ),
    ),
  ).toStrictEqual({ kind: 'permission' });
});

const tab = (number: number, agent: string, busy: Busy) => ({
  number,
  agent,
  busy,
});

test('the armed close line says what closing would stop', () => {
  expect(
    closeArmedLine(tab(1, 'fake', { kind: 'working' }), 'ctrl+x k'),
  ).toStrictEqual('1 fake is working · ctrl+x k again to stop it and close');
  expect(
    closeArmedLine(tab(2, 'claude', { kind: 'permission' }), 'ctrl+x k'),
  ).toStrictEqual(
    '2 claude waits for your permission · ctrl+x k again to stop it and close',
  );
  expect(
    closeArmedLine(tab(3, 'fake', { kind: 'queued', count: 2 }), 'ctrl+x k'),
  ).toStrictEqual(
    '3 fake has 2 prompts queued · ctrl+x k again to stop it and close',
  );
});

test('the armed quit line names the busy sessions, or counts them where it must', () => {
  const busy = [
    tab(2, 'claude', { kind: 'permission' }),
    tab(3, 'fake', { kind: 'working' }),
  ];

  expect(quitArmedLine(busy, 116)).toStrictEqual(
    '2 sessions are busy: 2 claude waits for permission, 3 fake is working · ctrl+d again to quit',
  );
  expect(quitArmedLine(busy, 76)).toStrictEqual(
    '2 sessions busy · ctrl+d again to quit',
  );
  expect(
    quitArmedLine([tab(2, 'fake', { kind: 'working' })], 76),
  ).toStrictEqual('2 fake is working · ctrl+d again to quit');
  expect(quitArmedLine([], 76)).toStrictEqual('Press ctrl+d again to quit');
  expect(ctrlCArmedLine(0)).toStrictEqual('Press ctrl+c again to quit');
  expect(ctrlCArmedLine(2)).toStrictEqual(
    'Press ctrl+c again to quit · 2 sessions busy',
  );
});

test('one resume command for each session, in tab order', () => {
  expect(resumeMessage([])).toStrictEqual(undefined);
  expect(
    resumeMessage([{ agent: 'fake', sessionId: 'a', cwd: '/work' }]),
  ).toStrictEqual('Resume this session with:\nchord fake --resume a');
  expect(
    resumeMessage(
      [
        { agent: 'fake', sessionId: 'a', cwd: '/work' },
        { agent: 'claude', sessionId: 'b', cwd: '/work' },
      ],
      { agent: 'fake', agentCommand: 'run fake' },
    ),
  ).toStrictEqual(
    'Resume these sessions with:\n' +
      "chord fake --agent-command 'run fake' --resume a\n" +
      'chord claude --resume b',
  );
});

test('a closed session leaves the window, the one beside it in front', () => {
  const one = windowed(initialAppState, 1);
  const two = reduceWindowed(one, { type: 'session_opened', key: 2 });
  const armed = reduceWindowed(two, { type: 'close_armed', key: 2 });

  expect(armed.window.closeArmed).toStrictEqual(2);

  const closed = reduceWindowed(armed, {
    type: 'session_closed',
    key: 2,
    front: 1,
  });

  expect(closed.front).toStrictEqual(1);
  expect(Object.keys(closed.sessions)).toStrictEqual(['1']);
  expect(closed.window.closeArmed).toStrictEqual(undefined);
  expect(closed.sessions[1]).toStrictEqual(initialSession);
  expect(
    reduceWindowed(armed, { type: 'close_disarmed' }).window.closeArmed,
  ).toStrictEqual(undefined);
});

test('an armed close or quit takes the place of a note of the sessions for good', () => {
  const noted = reduceWindowed(windowed(initialAppState, 1), {
    type: 'sessions_noted',
    message: 'Closed 2 fake · /resume opens it again',
  });

  for (const [arm, disarm] of [
    [{ type: 'close_armed', key: 1 }, { type: 'close_disarmed' }],
    [{ type: 'quit_armed', by: 'ctrl+d' }, { type: 'quit_disarmed' }],
    [{ type: 'quit_armed' }, { type: 'quit_disarmed' }],
  ] as const) {
    const expired = reduceWindowed(reduceWindowed(noted, arm), disarm);

    expect(expired.window.sessionsNote, arm.type).toStrictEqual(undefined);
  }
});

test("a tab's long-lived agents at work count with its task agents, and one that waits makes the tab wait", () => {
  const idle = { transcript: emptyTranscript, queue: [] };
  const running = {
    transcript: { ...emptyTranscript, turn: working },
    queue: [],
  };
  const waiting = {
    transcript: {
      ...emptyTranscript,
      turn: {
        status: 'awaiting_permission' as const,
        turnId: 't',
        since: 0,
        permissions: [{ id: 'p', options: [] }],
      },
    },
    queue: [],
  };

  expect(tabBusy(idle, [idle])).toStrictEqual(undefined);
  expect(tabBusy(running, [idle])).toStrictEqual({ kind: 'working' });
  expect(tabBusy(idle, [running, running])).toStrictEqual({
    kind: 'agents',
    count: 2,
  });
  expect(tabBusy(running, [waiting])).toStrictEqual({ kind: 'permission' });
  expect(
    closeArmedLine(
      { number: 1, agent: 'claude', busy: { kind: 'agents', count: 3 } },
      'ctrl+x k',
    ),
  ).toStrictEqual(
    '1 claude has 3 agents working · ctrl+x k again to stop them and close',
  );
  expect(agentCloseArmedLine('parser', { kind: 'working' }, 'x')).toStrictEqual(
    'parser is working · x again to stop it and close',
  );
  expect(teamCloseArmedLine('bugfix', 3, 'x')).toStrictEqual(
    'bugfix and its 3 members are working · x again to stop them and close',
  );
  expect(teamCloseArmedLine('bugfix', 1, 'x')).toStrictEqual(
    'bugfix and its member are working · x again to stop them and close',
  );
});
